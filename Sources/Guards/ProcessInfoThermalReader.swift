import Foundation
import AwakeCore

/// Lector real de temperatura, basado en `ProcessInfo.processInfo.thermalState`.
///
/// **Limite honesto, deliberado:** macOS *no* expone grados Celsius por ninguna
/// API publica. `ThermalState` da cuatro escalones (nominal / fair / serious /
/// critical) y eso es todo lo que hay sin leer el SMC con claves no
/// documentadas — que cambian entre modelos, no estan soportadas por Apple y
/// quedan explicitamente fuera de v1. El techo configurable del usuario se
/// expresa en esos cuatro niveles, no en temperatura.
///
/// No hay polling: `ProcessInfo.thermalStateDidChangeNotification` avisa.
public final class ProcessInfoThermalReader: ThermalReading, @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    public init() {}

    deinit { stopMonitoring() }

    public var level: ThermalLevel {
        Self.map(ProcessInfo.processInfo.thermalState)
    }

    public func startMonitoring(onChange: @escaping @Sendable (ThermalLevel) -> Void) {
        lock.lock()
        guard token == nil else {
            lock.unlock()
            return
        }
        let observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            // Se relee `thermalState` en vez de confiar en el userInfo de la
            // notificacion, que no trae el nivel.
            onChange(Self.map(ProcessInfo.processInfo.thermalState))
        }
        token = observer
        lock.unlock()
    }

    /// Idempotente.
    public func stopMonitoring() {
        lock.lock()
        let observer = token
        token = nil
        lock.unlock()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    static func map(_ state: ProcessInfo.ThermalState) -> ThermalLevel {
        switch state {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .critical  // Ante un nivel nuevo, el lado seguro.
        }
    }
}
