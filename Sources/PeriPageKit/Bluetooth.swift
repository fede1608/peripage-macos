import Foundation
import IOBluetooth

public struct BluetoothDeviceInfo: Identifiable, Hashable, Sendable {
    public let address: String
    public let name: String
    public let isPaired: Bool
    public let isConnected: Bool
    public var id: String { address }
    public var model: PrinterModel? { PrinterModel.detect(bluetoothName: name) }

    init(_ device: IOBluetoothDevice) {
        address = device.addressString ?? ""
        name = device.name ?? device.addressString ?? "?"
        isPaired = device.isPaired()
        isConnected = device.isConnected()
    }

    /// A printer remembered from a previous session; RFCOMM works without OS-level pairing.
    public init(address: String, name: String) {
        self.address = address
        self.name = name
        isPaired = false
        isConnected = false
    }
}

public enum PrinterError: LocalizedError {
    case deviceNotFound(String)
    case connectionFailed(IOReturn)
    case notConnected
    case writeFailed(IOReturn)
    case timeout(String)
    case printerProblem(PrinterEvent)

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound(let a): "No encontré el dispositivo \(a)"
        case .connectionFailed(let r): "No se pudo abrir el canal RFCOMM (\(String(format: "0x%08X", r))). ¿Está prendida y cerca?"
        case .notConnected: "La impresora no está conectada"
        case .writeFailed(let r): "Falló el envío de datos (\(String(format: "0x%08X", r)))"
        case .timeout(let what): "Sin respuesta de la impresora (\(what))"
        case .printerProblem(let e): e.message
        }
    }
}

public enum BluetoothDirectory {
    /// Paired devices whose name looks like a PeriPage printer.
    public static func pairedPrinters() -> [BluetoothDeviceInfo] {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return devices.map(BluetoothDeviceInfo.init).filter { PrinterModel.looksLikePeriPage($0.name) }
    }

    public static func device(address: String) -> BluetoothDeviceInfo? {
        IOBluetoothDevice(addressString: address).map(BluetoothDeviceInfo.init)
    }

    public static var isPoweredOn: Bool {
        IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }
}

/// Classic Bluetooth inquiry for unpaired printers. Callbacks arrive on the main run loop.
@MainActor
public final class PrinterScanner: NSObject, IOBluetoothDeviceInquiryDelegate {
    public private(set) var found: [BluetoothDeviceInfo] = []
    public var onUpdate: (([BluetoothDeviceInfo]) -> Void)?
    public var onFinish: (() -> Void)?
    private var inquiry: IOBluetoothDeviceInquiry?

    public override init() { super.init() }

    public func start(seconds: UInt8 = 10) {
        stop()
        found = []
        let inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry?.inquiryLength = seconds
        inquiry?.updateNewDeviceNames = true
        self.inquiry = inquiry
        inquiry?.start()
    }

    public func stop() {
        inquiry?.stop()
        inquiry = nil
    }

    nonisolated public func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        MainActor.assumeIsolated { add(device) }
    }

    nonisolated public func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        MainActor.assumeIsolated { add(device) }
    }

    nonisolated public func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        MainActor.assumeIsolated { onFinish?() }
    }

    private func add(_ device: IOBluetoothDevice?) {
        guard let device, let name = device.name, PrinterModel.looksLikePeriPage(name) else { return }
        let info = BluetoothDeviceInfo(device)
        found.removeAll { $0.address == info.address }
        found.append(info)
        onUpdate?(found)
    }
}

/// One RFCOMM (SPP) connection to a PeriPage printer.
///
/// All IOBluetooth callbacks are delivered on the run loop of the thread that opened the channel,
/// so this type lives on the main actor and requires a running main run loop.
@MainActor
public final class PeriPagePrinter: NSObject, IOBluetoothRFCOMMChannelDelegate {
    public let address: String
    public let name: String
    public let model: PrinterModel

    public var onEvent: ((PrinterEvent) -> Void)?
    public var onDisconnect: (() -> Void)?
    /// Raw traffic log, useful when debugging unknown firmware.
    public var onLog: ((String) -> Void)?

    public var isConnected: Bool { channel?.isOpen() ?? false }

    private let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var sdpContinuation: CheckedContinuation<Void, Never>?

    private struct PendingWrite {
        let buffer: UnsafeMutableRawPointer
        let length: Int
        let continuation: CheckedContinuation<Void, Error>
    }
    private var inFlight: [UnsafeMutableRawPointer: PendingWrite] = [:]

    private struct PendingRequest {
        let id = UUID()
        var buffer: [UInt8] = []
        let isComplete: ([UInt8]) -> Bool
        let continuation: CheckedContinuation<[UInt8], Error>
    }
    private var request: PendingRequest?
    private var printWaiter: (id: UUID, continuation: CheckedContinuation<Void, Error>)?

    public init(address: String, name: String? = nil, model: PrinterModel? = nil) throws {
        guard let device = IOBluetoothDevice(addressString: address) else { throw PrinterError.deviceNotFound(address) }
        self.device = device
        self.address = address
        let resolvedName = name ?? device.name ?? address
        self.name = resolvedName
        self.model = model ?? PrinterModel.detect(bluetoothName: resolvedName) ?? .a6
        super.init()
    }

    // MARK: Connection

    /// Retries once: right after another program releases the printer, the first attempt often times out.
    public func connect(attempts: Int = 2) async throws {
        var lastError: Error = PrinterError.notConnected
        for attempt in 1...max(1, attempts) {
            do {
                try await openChannel()
                return
            } catch {
                lastError = error
                log("Intento \(attempt) de conexión falló: \(error.localizedDescription)")
                if attempt < attempts { try? await Task.sleep(for: .seconds(1.5)) }
            }
        }
        throw lastError
    }

    private func openChannel() async throws {
        if isConnected { return }
        let channelID = await rfcommChannelID()
        log("Conectando a \(name) [\(address)] canal \(channelID)")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            openContinuation = cont
            var ch: IOBluetoothRFCOMMChannel?
            let result = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
            if result != kIOReturnSuccess {
                openContinuation = nil
                cont.resume(throwing: PrinterError.connectionFailed(result))
                return
            }
            channel = ch
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                guard let pending = openContinuation else { return }
                openContinuation = nil
                channel?.close()
                channel = nil
                pending.resume(throwing: PrinterError.timeout("conexión"))
            }
        }
    }

    public func disconnect() {
        channel?.close()
        channel = nil
        device.closeConnection()
    }

    /// SPP channel from the SDP record; the official app falls back to channel 1.
    private func rfcommChannelID() async -> BluetoothRFCOMMChannelID {
        let spp = IOBluetoothSDPUUID(uuid16: 0x1101)
        if let id = channelID(from: device.getServiceRecord(for: spp)) { return id }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sdpContinuation = cont
            if device.performSDPQuery(self) != kIOReturnSuccess {
                sdpContinuation = nil
                cont.resume()
            }
        }
        return channelID(from: device.getServiceRecord(for: spp)) ?? 1
    }

    private func channelID(from record: IOBluetoothSDPServiceRecord?) -> BluetoothRFCOMMChannelID? {
        guard let record else { return nil }
        var id: BluetoothRFCOMMChannelID = 0
        return record.getRFCOMMChannelID(&id) == kIOReturnSuccess ? id : nil
    }

    @objc nonisolated public func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        MainActor.assumeIsolated {
            sdpContinuation?.resume()
            sdpContinuation = nil
        }
    }

    // MARK: Writing

    /// Sends bytes in MTU-sized chunks, each awaited, so RFCOMM flow control paces the transfer.
    public func send(_ bytes: [UInt8], progress: ((Int) -> Void)? = nil) async throws {
        guard let channel, channel.isOpen() else { throw PrinterError.notConnected }
        let mtu = max(16, Int(channel.getMTU()))
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + mtu, bytes.count)
            try await writeChunk(Array(bytes[offset..<end]))
            offset = end
            progress?(offset)
        }
    }

    private func writeChunk(_ chunk: [UInt8]) async throws {
        guard let channel else { throw PrinterError.notConnected }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: chunk.count, alignment: 1)
        chunk.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: chunk.count) }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            inFlight[buffer] = PendingWrite(buffer: buffer, length: chunk.count, continuation: cont)
            let result = channel.writeAsync(buffer, length: UInt16(chunk.count), refcon: buffer)
            if result != kIOReturnSuccess {
                inFlight[buffer] = nil
                buffer.deallocate()
                cont.resume(throwing: PrinterError.writeFailed(result))
            }
        }
    }

    // MARK: Requests

    /// Sends `command` and collects the reply until `isComplete` or until `timeout`.
    /// Text replies have no terminator, so they complete after a short quiet period.
    public func request(_ command: [UInt8], timeout: TimeInterval = 2,
                        isComplete: @escaping ([UInt8]) -> Bool) async throws -> [UInt8] {
        guard request == nil else { throw PrinterError.timeout("otra consulta en curso") }
        let reply = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[UInt8], Error>) in
            let pendingRequest = PendingRequest(isComplete: isComplete, continuation: cont)
            request = pendingRequest
            Task { @MainActor in
                do { try await send(command) } catch { finishRequest(.failure(error)) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let pending = request, pending.id == pendingRequest.id {
                    if pending.buffer.isEmpty {
                        finishRequest(.failure(PrinterError.timeout(Self.hex(command))))
                    } else {
                        finishRequest(.success(pending.buffer))
                    }
                }
            }
        }
        return reply
    }

    private func finishRequest(_ result: Result<[UInt8], Error>) {
        guard let pending = request else { return }
        request = nil
        pending.continuation.resume(with: result)
    }

    public func batteryPercent() async throws -> Int {
        let reply = try await request(PeriPageCommand.queryBattery) { $0.count >= 2 }
        guard reply.count >= 2 else { throw PrinterError.timeout("batería") }
        return Int(reply[1])
    }

    public func status() async throws -> PrinterStatus {
        let reply = try await request(PeriPageCommand.queryStatus, timeout: 1.2) { $0.count >= 1 }
        return PrinterStatus(raw: reply.first ?? 0xFF)
    }

    public func firmwareVersion() async throws -> String {
        ResponseText.firmware(try await request(PeriPageCommand.queryFirmware, timeout: 0.8) { _ in false })
    }

    public func serialNumber() async throws -> String {
        ResponseText.clean(try await request(PeriPageCommand.querySerial, timeout: 0.8) { _ in false })
    }

    public func modelName() async throws -> String {
        ResponseText.clean(try await request(PeriPageCommand.queryModel, timeout: 0.8) { _ in false })
    }

    /// Mirrors the app: 12 padding bytes, then `10 FF 10 00 n`, acknowledged with `OK`.
    @discardableResult
    public func setDensity(_ density: Density) async throws -> Bool {
        let raw = model.densityValues[density.rawValue]
        try await send(PeriPageCommand.padding)
        let reply = try? await request(PeriPageCommand.density(raw), timeout: 2) { $0.count >= 2 }
        return reply == [0x4F, 0x4B]
    }

    public func setPaperType(_ type: PaperType) async throws {
        try await send(PeriPageCommand.paperType(type))
    }

    // MARK: Printing

    /// Sends a full job and waits for the printer's `0xAA` "done" byte.
    public func print(_ bitmap: MonoBitmap, options: PrintJobOptions = .init(),
                      progress: ((Double) -> Void)? = nil) async throws {
        precondition(bitmap.width == model.widthDots, "bitmap width \(bitmap.width) != printer width \(model.widthDots)")
        let job = PrintJobEncoder.encode(bitmap, model: model, options: options)
        log("Imprimiendo \(bitmap.width)×\(bitmap.height) (\(job.count) bytes)")
        try await send(job) { sent in progress?(Double(sent) / Double(job.count)) }

        // Rough upper bound: the A6 prints ~15 mm/s.
        let mm = model.mm(forDots: bitmap.height * max(1, options.copies))
        let deadline = 8 + mm / 10
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let id = UUID()
            printWaiter = (id, cont)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(deadline))
                if let waiter = printWaiter, waiter.id == id {
                    printWaiter = nil
                    log("No llegó 0xAA en \(Int(deadline)) s; asumo que terminó")
                    waiter.continuation.resume()
                }
            }
        }
    }

    // MARK: RFCOMM delegate

    nonisolated public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        MainActor.assumeIsolated {
            guard let cont = openContinuation else { return }
            openContinuation = nil
            if error == kIOReturnSuccess {
                channel = rfcommChannel
                log("Conectado (MTU \(rfcommChannel.getMTU()))")
                cont.resume()
            } else {
                channel = nil
                cont.resume(throwing: PrinterError.connectionFailed(error))
            }
        }
    }

    nonisolated public func rfcommChannelWriteComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status error: IOReturn) {
        MainActor.assumeIsolated {
            guard let refcon, let pending = inFlight.removeValue(forKey: refcon) else { return }
            pending.buffer.deallocate()
            if error == kIOReturnSuccess {
                pending.continuation.resume()
            } else {
                pending.continuation.resume(throwing: PrinterError.writeFailed(error))
            }
        }
    }

    nonisolated public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        MainActor.assumeIsolated { receive(bytes) }
    }

    nonisolated public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated {
            log("Canal cerrado")
            channel = nil
            for (_, pending) in inFlight {
                pending.buffer.deallocate()
                pending.continuation.resume(throwing: PrinterError.notConnected)
            }
            inFlight.removeAll()
            finishRequest(.failure(PrinterError.notConnected))
            printWaiter?.continuation.resume(throwing: PrinterError.notConnected)
            printWaiter = nil
            onDisconnect?()
        }
    }

    private func receive(_ bytes: [UInt8]) {
        log("← \(Self.hex(bytes))")
        let event = PrinterEvent.parse(bytes)
        let isAsyncEvent: Bool = {
            guard let event else { return false }
            switch event {
            case .ok: return false
            case .printFinished: return bytes == [0xAA] || request == nil
            default: return true
            }
        }()

        if isAsyncEvent, let event {
            onEvent?(event)
            if event == .printFinished, let waiter = printWaiter {
                printWaiter = nil
                waiter.continuation.resume()
            } else if event.isProblem, event != .lowBattery, let waiter = printWaiter {
                printWaiter = nil
                waiter.continuation.resume(throwing: PrinterError.printerProblem(event))
            }
            return
        }

        if var pending = request {
            pending.buffer += bytes
            request = pending
            if pending.isComplete(pending.buffer) { finishRequest(.success(pending.buffer)) }
        } else if let event {
            onEvent?(event)
        }
    }

    private func log(_ message: String) { onLog?(message) }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ") + (bytes.count > 32 ? " …" : "")
    }
}
