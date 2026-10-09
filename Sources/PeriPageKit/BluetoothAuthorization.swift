import CoreBluetooth
import Foundation

/// IOBluetooth blocks the calling thread while Bluetooth permission is undetermined (it waits on CoreBluetooth),
/// which deadlocks the main thread. Ask through CoreBluetooth first and only touch IOBluetooth once allowed.
@MainActor
public final class BluetoothAuthorization: NSObject, CBCentralManagerDelegate {
    public enum Result: Sendable { case allowed, denied, poweredOff, unsupported }

    private var manager: CBCentralManager?
    private var continuation: CheckedContinuation<Result, Never>?

    public override init() { super.init() }

    public static var isDetermined: Bool { CBManager.authorization != .notDetermined }

    public func request() async -> Result {
        switch CBManager.authorization {
        case .denied, .restricted: return .denied
        default: break
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        MainActor.assumeIsolated {
            let result: Result
            switch state {
            case .poweredOn: result = .allowed
            case .poweredOff, .resetting: result = .poweredOff
            case .unauthorized: result = .denied
            case .unsupported: result = .unsupported
            case .unknown: return
            @unknown default: return
            }
            continuation?.resume(returning: result)
            continuation = nil
            manager = nil
        }
    }
}
