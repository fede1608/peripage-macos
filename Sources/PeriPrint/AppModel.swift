import AppKit
import Observation
import PeriPageKit
import PeriRender
import PuzzleKit
import ResourceStore
import SocialKit

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)
}

@Observable
@MainActor
final class AppModel {
    // MARK: Documents
    var mode: Mode = .photo { didSet { scheduleRender(); persist() } }
    var photo = PhotoDoc() { didSet { scheduleRender(); persist() } }
    var sticker = StickerDoc() { didSet { scheduleRender(); persist() } }
    var label = LabelDoc() { didSet { scheduleRender(); persist() } }
    var collage = CollageDoc() { didSet { scheduleRender(); persist() } }
    var text = TextDoc() { didSet { scheduleRender(); persist() } }
    var banner = BannerDoc() { didSet { scheduleRender(); persist() } }
    var qr = QRDoc() { didSet { scheduleRender(); persist() } }
    var puzzle = PuzzleDoc() { didSet { scheduleRender(); persist() } }
    var social = SocialDoc() { didSet { scheduleRender(); persist() } }
    var settings = PrintSettings() { didSet { persist(); scheduleRender() } }

    var image: CGImage? { didSet { scheduleRender() } }
    var imageName: String?
    var labelImage: CGImage? { didSet { scheduleRender() } }
    var collageImages: [CGImage] = [] { didSet { scheduleRender() } }
    static let maxCollageImages = 8
    var labelImageName: String?
    var socialPost: SocialPost? { didSet { scheduleRender() } }

    private(set) var preview: MonoBitmap?
    /// Rows of label backing paper, shaded in the preview.
    private(set) var previewGaps: [Range<Int>] = []
    private(set) var isRendering = false

    // MARK: History
    private(set) var history: [HistoryEntry] = []
    var selectedHistoryID: UUID? { didSet { loadSelectedHistory() } }
    private var historyBitmap: MonoBitmap? { didSet { scheduleRender() } }

    // MARK: Presets
    private(set) var userPresets: [Preset] = []
    var selectedPresetID: UUID?

    // MARK: Printer
    private(set) var pairedPrinters: [BluetoothDeviceInfo] = []
    var selectedAddress: String? { didSet { UserDefaults.standard.set(selectedAddress, forKey: Keys.address) } }
    /// Used for previews when no printer is connected or the name is not recognized.
    var fallbackModel: PrinterModel = .a6 { didSet { UserDefaults.standard.set(fallbackModel.family.rawValue, forKey: Keys.model); scheduleRender() } }
    private(set) var connection: ConnectionState = .disconnected
    private(set) var printer: PeriPagePrinter?
    private(set) var battery: Int?
    private(set) var status: PrinterStatus?
    private(set) var firmware: String?
    private(set) var isPrinting = false
    private(set) var printProgress: Double = 0
    private(set) var log: [String] = []
    var lastMessage: String?
    /// IOBluetooth must not be touched before this is true (see BluetoothAuthorization).
    private(set) var bluetoothReady = false
    private(set) var bluetoothProblem: String?

    var model: PrinterModel { printer?.model ?? selectedDevice?.model ?? fallbackModel }
    var selectedDevice: BluetoothDeviceInfo? { pairedPrinters.first { $0.address == selectedAddress } }

    /// Label positioning applies to the label mode and to social posts printed as labels.
    var printsOnLabels: Bool { mode == .label || (mode == .social && social.layout == .label) }

    /// Set when another process asks for the printer while we are still connecting.
    private var releaseRequested = false
    private var renderTask: Task<Void, Never>?
    private var batteryTask: Task<Void, Never>?
    private var restoring = false

    private enum Keys {
        static let address = "printer.address"
        static let name = "printer.name"
        static let model = "printer.fallbackModel"
        static let state = "documents.state"
        static let defaultsVersion = "defaults.version"
    }

    init() {
        restoring = true
        FontLibrary.registerInstalledFonts()
        selectedAddress = UserDefaults.standard.string(forKey: Keys.address)
        if let raw = UserDefaults.standard.string(forKey: Keys.model),
           let m = PrinterModel.all.first(where: { $0.family.rawValue == raw }) { fallbackModel = m }
        restoreState()
        UserDefaults.standard.set(2, forKey: Keys.defaultsVersion)
        userPresets = PresetStore.load()
        history = HistoryStore.load()
        restoring = false
        scheduleRender()
        // PeriPrint Driver asks for the printer before printing a job from another app.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("app.periprint.releasePrinter"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPrinting else { return }
                if self.connection == .connecting {
                    self.releaseRequested = true
                } else if self.printer != nil {
                    self.appendLog("Otra app pidió la impresora; desconectando")
                    self.disconnect()
                }
            }
        }
    }

    func startBluetooth() async {
        guard !bluetoothReady else { return }
        switch await BluetoothAuthorization().request() {
        case .allowed:
            bluetoothReady = true
            bluetoothProblem = nil
            refreshPairedPrinters()
            if selectedAddress != nil, printer == nil { await connect(quietly: true) }
        case .poweredOff:
            bluetoothProblem = "Bluetooth está apagado"
        case .denied:
            bluetoothProblem = "Sin permiso de Bluetooth: habilitalo en Ajustes → Privacidad y seguridad → Bluetooth"
        case .unsupported:
            bluetoothProblem = "Esta Mac no soporta Bluetooth"
        }
    }

    // MARK: Rendering

    func scheduleRender() {
        guard !restoring else { return }
        renderTask?.cancel()
        let input = Renderer.Input(mode: mode, photo: photo, sticker: sticker, text: text, banner: banner, qr: qr, label: label,
                                   collage: collage, collageImages: collageImages, puzzle: puzzle, social: social, socialPost: socialPost, image: image, labelImage: labelImage,
                                   history: historyBitmap, model: model)
        let labelCount = mode == .label ? Renderer.labelEntries(label).count : 1
        let onLabels = printsOnLabels
        isRendering = true
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { Renderer.render(input) }.value
            guard !Task.isCancelled, let self else { return }
            self.preview = result
            self.previewGaps = onLabels && result != nil ? Renderer.labelGaps(count: labelCount, doc: input.label, model: input.model) : []
            self.isRendering = false
        }
    }

    // MARK: Images

    func loadImage(from url: URL) {
        guard let ns = NSImage(contentsOf: url), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            lastMessage = "No pude abrir \(url.lastPathComponent)"
            return
        }
        setImage(cg, name: url.lastPathComponent)
    }

    func loadImage(_ ns: NSImage, name: String = "Imagen pegada") {
        guard let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        setImage(cg, name: name)
    }

    /// Routes a new image to the label icon when in label mode, otherwise to photo/sticker.
    private func setImage(_ cg: CGImage, name: String) {
        if mode == .collage {
            if collageImages.count < Self.maxCollageImages { collageImages.append(cg) }
            return
        }
        if mode == .label {
            labelImage = cg
            labelImageName = name
            if label.content == .text { label.content = .iconText }
            return
        }
        imageName = name
        image = cg
        if !mode.usesImage { mode = .photo }
    }

    func pasteImage() -> Bool {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: ["public.image"]]) as? [URL],
           let url = urls.first {
            loadImage(from: url)
            return true
        }
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage], let first = images.first {
            loadImage(first)
            return true
        }
        return false
    }

    /// Called by the resource store.
    func useResource(_ image: CGImage, info: ResourceInfo, destination: ResourceDestination) {
        switch destination {
        case .photo:
            imageName = info.name
            self.image = image
            mode = .photo
        case .sticker:
            imageName = info.name
            self.image = image
            mode = .sticker
        case .label:
            labelImage = image
            labelImageName = info.name
            if label.content != .image { label.content = .iconText }
            mode = .label
        }
    }

    /// A screenshot captured in the social browser can also be used as a photo or sticker.
    func useCapturedImage(_ image: CGImage, as destination: Mode) {
        imageName = "Captura"
        self.image = image
        mode = destination
    }

    // MARK: Presets

    var presetsForMode: [Preset] { Preset.builtIns.filter { $0.mode == mode } + userPresets.filter { $0.mode == mode } }

    func apply(_ preset: Preset) {
        selectedPresetID = preset.id
        settings = preset.settings
        switch preset.mode {
        case .photo: if let d = preset.photo { photo = keepingContent(d, from: photo) }
        case .sticker: if let d = preset.sticker { sticker = d }
        case .label: if let d = preset.label { label = keepingLines(d, from: label, builtIn: preset.builtIn) }
        case .text: if let d = preset.text { text = d }
        case .banner: if let d = preset.banner { banner = keepingText(d, from: banner, builtIn: preset.builtIn) }
        case .qr: if let d = preset.qr { qr = d }
        case .collage, .social, .games, .history: break
        }
    }

    /// Built-in photo presets shouldn't wipe a caption the user already typed.
    private func keepingContent(_ d: PhotoDoc, from current: PhotoDoc) -> PhotoDoc {
        var d = d
        if d.caption.isEmpty { d.caption = current.caption }
        return d
    }

    private func keepingText(_ d: BannerDoc, from current: BannerDoc, builtIn: Bool) -> BannerDoc {
        var d = d
        if builtIn { d.text = current.text }
        return d
    }

    /// Built-in label styles keep the user's roll geometry.
    private func keepingLines(_ d: LabelDoc, from current: LabelDoc, builtIn: Bool) -> LabelDoc {
        guard builtIn else { return d }
        var d = d
        d.heightMM = current.heightMM
        d.gapMM = current.gapMM
        d.adjustMM = current.adjustMM
        return d
    }

    func saveCurrentAsPreset(named name: String) {
        var p = Preset(name: name, mode: mode, settings: settings)
        switch mode {
        case .photo: p.photo = photo
        case .sticker: p.sticker = sticker
        case .label: p.label = label
        case .text: p.text = text
        case .banner: p.banner = banner
        case .qr: p.qr = qr
        case .collage, .social, .games, .history: return
        }
        userPresets.append(p)
        selectedPresetID = p.id
        PresetStore.save(userPresets)
    }

    func deletePreset(_ preset: Preset) {
        userPresets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id { selectedPresetID = nil }
        PresetStore.save(userPresets)
    }

    // MARK: History

    private func loadSelectedHistory() {
        historyBitmap = history.first { $0.id == selectedHistoryID }.flatMap(HistoryStore.bitmap(for:))
    }

    func deleteHistory(_ entry: HistoryEntry) {
        HistoryStore.delete(entry)
        history = HistoryStore.load()
        if selectedHistoryID == entry.id { selectedHistoryID = nil }
    }

    func clearHistory() {
        HistoryStore.clear()
        history = []
        selectedHistoryID = nil
    }

    private var historyTitle: String {
        switch mode {
        case .photo, .sticker: "\(mode.title) · \(imageName ?? "imagen")"
        case .collage: "Collage · \(collageImages.count) fotos"
        case .label: "Etiquetas · \(Renderer.labelEntries(label).prefix(3).joined(separator: ", "))"
        case .text: "Texto · \(text.title.isEmpty ? String(text.body.prefix(40)) : text.title)"
        case .banner: "Banner · \(banner.text)"
        case .qr: "QR · \(qr.kind == .wifi ? qr.wifiSSID : qr.content)"
        case .social: "Redes · \(socialPost.map { $0.handle.isEmpty ? $0.platform.rawValue : "@\($0.handle)" } ?? "")"
        case .games: "Juego · \(puzzle.kind.title)"
        case .history: "Reimpresión"
        }
    }

    // MARK: Printer

    func refreshPairedPrinters() {
        guard bluetoothReady else { return }
        pairedPrinters = BluetoothDirectory.pairedPrinters()
        if let address = selectedAddress, let name = UserDefaults.standard.string(forKey: Keys.name),
           !pairedPrinters.contains(where: { $0.address.caseInsensitiveCompare(address) == .orderedSame }) {
            pairedPrinters.insert(BluetoothDeviceInfo(address: address, name: name), at: 0)
        }
        if selectedAddress == nil { selectedAddress = pairedPrinters.first?.address }
        scheduleRender()
    }

    func select(_ device: BluetoothDeviceInfo) {
        if device.address != selectedAddress { disconnect() }
        selectedAddress = device.address
        UserDefaults.standard.set(device.name, forKey: Keys.name)
        if !pairedPrinters.contains(where: { $0.address == device.address }) { pairedPrinters.append(device) }
        scheduleRender()
    }

    /// `quietly` is used for the automatic connection at launch: a printer that is off is not an error.
    func connect(quietly: Bool = false) async {
        if !bluetoothReady { await startBluetooth() }
        guard bluetoothReady else {
            connection = .failed(bluetoothProblem ?? "Bluetooth no disponible")
            return
        }
        guard let address = selectedAddress else {
            connection = .failed("Elegí una impresora")
            return
        }
        if printer?.isConnected == true || connection == .connecting { return }
        connection = .connecting
        do {
            let name = pairedPrinters.first { $0.address == address }?.name
            let p = try PeriPagePrinter(address: address, name: name,
                                        model: PrinterModel.detect(bluetoothName: name ?? "") == nil ? fallbackModel : nil)
            p.onLog = { [weak self] line in self?.appendLog(line) }
            p.onEvent = { [weak self] event in self?.handle(event) }
            p.onDisconnect = { [weak self] in self?.handleDisconnect() }
            try await p.connect(attempts: quietly ? 1 : 2)
            if releaseRequested && quietly {
                releaseRequested = false
                p.disconnect()
                connection = .disconnected
                appendLog("Otra app pidió la impresora; la dejo libre")
                return
            }
            releaseRequested = false
            printer = p
            connection = .connected
            scheduleRender()
            await refreshInfo()
            startBatteryPolling()
        } catch {
            connection = quietly ? .disconnected : .failed(error.localizedDescription)
            appendLog("Error: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        batteryTask?.cancel()
        printer?.disconnect()
        printer = nil
        connection = .disconnected
        battery = nil
        status = nil
    }

    func refreshInfo() async {
        guard let printer, !isPrinting else { return }
        battery = try? await printer.batteryPercent()
        status = try? await printer.status()
        if firmware == nil { firmware = try? await printer.firmwareVersion() }
    }

    private func startBatteryPolling() {
        batteryTask?.cancel()
        batteryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, self.connection == .connected else { return }
                await self.refreshInfo()
            }
        }
    }

    private func handle(_ event: PrinterEvent) {
        appendLog("Evento: \(event.message)")
        if event.isProblem { lastMessage = event.message }
        if event == .lowBattery { battery = min(battery ?? 100, 15) }
    }

    private func handleDisconnect() {
        printer = nil
        connection = .disconnected
        battery = nil
        status = nil
    }

    private func appendLog(_ line: String) {
        log.append("\(Formatters.time.string(from: .now))  \(line)")
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    func print() async {
        guard let bitmap = preview, bitmap.height > 0 else {
            lastMessage = mode.usesImage && image == nil ? "Primero elegí una imagen" : "No hay nada para imprimir"
            return
        }
        let options: PrintJobOptions
        if printsOnLabels {
            // Copies are already laid out on the strip; the feed leaves the tear point just inside the next gap.
            options = PrintJobOptions(copies: 1, trailingFeedDots: Renderer.LabelGeometry.trailingFeed(model: model))
        } else {
            options = PrintJobOptions(
                copies: settings.copies,
                trailingFeedDots: model.feedDots(bottomMarginMM: settings.bottomMarginMM),
                gapBetweenCopiesDots: model.dots(forMM: settings.gapBetweenCopiesMM),
                advanceToNextLabel: settings.paper != .continuous
            )
        }
        if await send(bitmap, options: options), mode != .history,
           let entry = HistoryStore.add(bitmap, title: historyTitle) {
            history.insert(entry, at: 0)
        }
    }

    func printPuzzleSolution() async {
        guard let solution = PuzzleRenderer.renderSolution(puzzle, widthDots: model.widthDots) else {
            lastMessage = "Este juego no tiene solución para imprimir"
            return
        }
        await send(solution, options: PrintJobOptions(trailingFeedDots: model.feedDots(bottomMarginMM: settings.bottomMarginMM)))
    }

    /// Connects if needed and prints. Returns true when the printer confirmed the job.
    @discardableResult
    func send(_ bitmap: MonoBitmap, options: PrintJobOptions) async -> Bool {
        if printer?.isConnected != true { await connect() }
        guard let printer, printer.isConnected else { return false }
        guard bitmap.width == printer.model.widthDots else {
            scheduleRender()
            lastMessage = "Ajusté la vista previa al ancho de la impresora; probá de nuevo"
            return false
        }
        isPrinting = true
        printProgress = 0
        defer { isPrinting = false }
        do {
            if let s = try? await printer.status(), s.raw & 0x04 != 0 {
                lastMessage = "La impresora no tiene papel"
                return false
            }
            try await printer.setDensity(settings.density)
            if settings.paper != .continuous && !printsOnLabels { try await printer.setPaperType(settings.paper) }
            try await printer.print(bitmap, options: options) { [weak self] p in self?.printProgress = p }
            printProgress = 1
            appendLog("Impresión terminada")
            battery = (try? await printer.batteryPercent()) ?? battery
            return true
        } catch {
            lastMessage = error.localizedDescription
            appendLog("Error al imprimir: \(error.localizedDescription)")
            return false
        }
    }

    func feedPaper(mm: Double = 10) async {
        if printer?.isConnected != true { await connect() }
        guard let printer else { return }
        let bytes = PeriPageCommand.startJob + PeriPageCommand.feed(dots: printer.model.dots(forMM: mm)) + PeriPageCommand.endJob
        do { try await printer.send(bytes) } catch { lastMessage = error.localizedDescription }
    }

    /// Prints two empty frames on consecutive labels so the position adjustment can be checked by eye.
    func printLabelCalibration() async {
        let H = model.dots(forMM: label.heightMM)
        var item = MonoBitmap(width: model.widthDots, height: H)
        item.strokeRect(x: 0, y: 0, width: item.width, height: H, thickness: 2)
        let mark = TextRenderer.render("↑ borde · ajuste \(String(format: "%+.1f", label.adjustMM)) mm",
                                       font: TextRenderer.font(family: "Helvetica Neue", size: 15, bold: true), align: .center,
                                       width: model.widthDots - 16)
        item.blit(mark, x: 8, y: (H - mark.height) / 2)
        let strip = Renderer.placeOnLabels([item, item], doc: label, model: model)
        await send(strip, options: PrintJobOptions(trailingFeedDots: Renderer.LabelGeometry.trailingFeed(model: model)))
    }

    /// Experimental: some PeriPage models stop at the next label gap with `GS FF` when set to gap paper.
    func testGapSensor() async {
        if printer?.isConnected != true { await connect() }
        guard let printer else { return }
        do {
            try await printer.setPaperType(.gapLabel)
            try await printer.send(PeriPageCommand.startJob + PeriPageCommand.nextLabel + PeriPageCommand.endJob)
            try await Task.sleep(for: .seconds(3))
            try await printer.setPaperType(.continuous)
            lastMessage = "Listo. Si la impresora avanzó justo hasta la próxima separación, tu A6 tiene sensor de etiquetas. Si avanzó apenas o nada, no lo tiene y la app usa el cálculo por distancia."
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    // MARK: Persistence

    private struct SavedState: Codable {
        var mode: Mode
        var photo: PhotoDoc
        var sticker: StickerDoc
        var label: LabelDoc
        var collage: CollageDoc?
        var text: TextDoc
        var banner: BannerDoc
        var qr: QRDoc
        var puzzle: PuzzleDoc
        var social: SocialDoc
        var settings: PrintSettings
    }

    private func persist() {
        guard !restoring else { return }
        let state = SavedState(mode: mode, photo: photo, sticker: sticker, label: label, collage: collage, text: text, banner: banner, qr: qr,
                               puzzle: puzzle, social: social, settings: settings)
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: Keys.state) }
    }

    /// Each document is decoded on its own and merged over its defaults, so new or removed fields
    /// in a later version never wipe the rest of the saved state.
    private func restoreState() {
        guard let data = UserDefaults.standard.data(forKey: Keys.state),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        mode = LenientJSON.decode(Mode.self, from: dict["mode"], default: .photo)
        photo = LenientJSON.decode(PhotoDoc.self, from: dict["photo"], default: PhotoDoc())
        sticker = LenientJSON.decode(StickerDoc.self, from: dict["sticker"], default: StickerDoc())
        label = LenientJSON.decode(LabelDoc.self, from: dict["label"], default: LabelDoc())
        collage = LenientJSON.decode(CollageDoc.self, from: dict["collage"], default: CollageDoc())
        text = LenientJSON.decode(TextDoc.self, from: dict["text"], default: TextDoc())
        banner = LenientJSON.decode(BannerDoc.self, from: dict["banner"], default: BannerDoc())
        qr = LenientJSON.decode(QRDoc.self, from: dict["qr"], default: QRDoc())
        puzzle = LenientJSON.decode(PuzzleDoc.self, from: dict["puzzle"], default: PuzzleDoc())
        social = LenientJSON.decode(SocialDoc.self, from: dict["social"], default: SocialDoc())
        settings = LenientJSON.decode(PrintSettings.self, from: dict["settings"], default: PrintSettings())
        if [.social, .history].contains(mode) { mode = .photo }
        // v2: defaults chosen from print tests (Stucki + tone #6, high density).
        if UserDefaults.standard.integer(forKey: Keys.defaultsVersion) < 2 {
            photo.pipeline = ImagePipeline(adjustments: .recommendedPhoto, algorithm: .stucki, transform: photo.pipeline.transform)
            sticker.pipeline = ImagePipeline(adjustments: .recommendedPhoto, algorithm: .stucki, transform: sticker.pipeline.transform)
            settings.density = .high
        }
    }
}

/// Decodes JSON merged over the encoded default value: missing keys keep their defaults.
enum LenientJSON {
    static func decode<T: Codable>(_ type: T.Type, from object: Any?, default value: T) -> T {
        guard let object,
              let defaultData = try? JSONEncoder().encode(value),
              let defaultObject = try? JSONSerialization.jsonObject(with: defaultData, options: .fragmentsAllowed),
              let data = try? JSONSerialization.data(withJSONObject: merge(defaultObject, object), options: .fragmentsAllowed),
              let result = try? JSONDecoder().decode(T.self, from: data) else { return value }
        return result
    }

    static func merge(_ base: Any, _ override: Any) -> Any {
        guard let b = base as? [String: Any], let o = override as? [String: Any] else { return override }
        var out = b
        for (key, value) in o { out[key] = b[key].map { merge($0, value) } ?? value }
        return out
    }
}

extension Formatters {
    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

enum PresetStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PeriPrint", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("presets.json")
    }

    /// Lenient per preset: one preset from an older version can't break the others.
    static func load() -> [Preset] {
        guard let data = try? Data(contentsOf: url),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        let docDefaults: [String: any Codable] = [
            "photo": PhotoDoc(), "sticker": StickerDoc(), "label": LabelDoc(), "text": TextDoc(), "banner": BannerDoc(), "qr": QRDoc(),
        ]
        return array.compactMap { item -> Preset? in
            var item = item
            for (key, value) in docDefaults {
                guard let stored = item[key], let defData = try? JSONEncoder().encode(value),
                      let defObject = try? JSONSerialization.jsonObject(with: defData) else { continue }
                item[key] = LenientJSON.merge(defObject, stored)
            }
            guard let data = try? JSONSerialization.data(withJSONObject: item) else { return nil }
            return try? JSONDecoder().decode(Preset.self, from: data)
        }
    }

    static func save(_ presets: [Preset]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(presets) { try? data.write(to: url, options: .atomic) }
    }
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var title: String
    var width: Int
    var height: Int
}

/// Last printed bitmaps (PNG) for one-click reprints.
enum HistoryStore {
    static let limit = 60

    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PeriPrint/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var indexURL: URL { directory.appendingPathComponent("index.json") }
    static func imageURL(for entry: HistoryEntry) -> URL { directory.appendingPathComponent("\(entry.id.uuidString).png") }

    static func load() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private static func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) { try? data.write(to: indexURL, options: .atomic) }
    }

    static func add(_ bitmap: MonoBitmap, title: String) -> HistoryEntry? {
        guard let cg = bitmap.cgImage(),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return nil }
        let entry = HistoryEntry(title: title, width: bitmap.width, height: bitmap.height)
        do { try png.write(to: imageURL(for: entry)) } catch { return nil }
        var entries = load()
        entries.insert(entry, at: 0)
        for old in entries.dropFirst(limit) { try? FileManager.default.removeItem(at: imageURL(for: old)) }
        save(Array(entries.prefix(limit)))
        return entry
    }

    static func bitmap(for entry: HistoryEntry) -> MonoBitmap? {
        guard let ns = NSImage(contentsOf: imageURL(for: entry)),
              let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let gray = GrayImage(cgImage: cg, width: entry.width) else { return nil }
        return ImageProcessor.dither(gray, algorithm: .threshold, threshold: 0.5)
    }

    static func delete(_ entry: HistoryEntry) {
        try? FileManager.default.removeItem(at: imageURL(for: entry))
        save(load().filter { $0.id != entry.id })
    }

    static func clear() {
        for entry in load() { try? FileManager.default.removeItem(at: imageURL(for: entry)) }
        save([])
    }
}
