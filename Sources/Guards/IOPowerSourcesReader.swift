import Foundation
import IOKit.ps
import StillOnCore

/// Lector real de `IOPowerSources`.
///
/// No hace polling: `IOPSNotificationCreateRunLoopSource` despierta al proceso
/// cada vez que el sistema publica un cambio de fuente de energia (porcentaje,
/// enchufado/desenchufado, inicio o fin de carga).
///
/// La fuente de run loop se agrega al **run loop principal**. En la app eso es
/// el run loop de AppKit, que siempre esta corriendo. Fuera de una app con run
/// loop activo (por ejemplo un test de linea de comandos) las notificaciones no
/// llegan; por eso los tests de los guards usan mocks y nunca este tipo.
public final class IOPowerSourcesReader: PowerSourceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var runLoopSource: CFRunLoopSource?
    private var onChange: (@Sendable (PowerSnapshot) -> Void)?

    public init() {}

    deinit { teardown() }

    public var snapshot: PowerSnapshot { Self.readSnapshot() }

    public func startMonitoring(onChange: @escaping @Sendable (PowerSnapshot) -> Void) {
        lock.lock()
        guard runLoopSource == nil else {
            lock.unlock()
            return
        }
        self.onChange = onChange

        let context = Unmanaged.passRetained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(
            powerSourcesDidChange, context
        )?.takeRetainedValue() else {
            // Sin notificaciones el guard sigue sirviendo `currentVerdict` bajo
            // demanda; simplemente no avisa por su cuenta.
            self.onChange = nil
            Unmanaged<IOPowerSourcesReader>.fromOpaque(context).release()
            lock.unlock()
            return
        }
        runLoopSource = source
        lock.unlock()

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    /// Idempotente: llamarlo dos veces, o sin haber arrancado, no hace nada.
    public func stopMonitoring() { teardown() }

    private func teardown() {
        lock.lock()
        guard let source = runLoopSource else {
            lock.unlock()
            return
        }
        runLoopSource = nil
        onChange = nil
        lock.unlock()

        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        CFRunLoopSourceInvalidate(source)
        // Contrapartida del `passRetained` de `startMonitoring`.
        Unmanaged.passUnretained(self).release()
    }

    fileprivate func deliverChange() {
        lock.lock()
        let callback = onChange
        lock.unlock()
        callback?(Self.readSnapshot())
    }

    // MARK: - Lectura

    /// Devuelve la primera bateria interna que encuentre. Si la maquina no tiene
    /// bateria (o IOKit falla) se asume 100 % en AC: es el estado que nunca
    /// desarma, que es el default seguro para un guard.
    static func readSnapshot() -> PowerSnapshot {
        let fallback = PowerSnapshot(percent: 100, isOnAC: true, isCharging: false)

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return fallback }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0

            let isOnAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false

            // kIOPSTimeToEmptyKey viene en minutos; -1 = todavia calculando.
            var timeToEmpty: TimeInterval?
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes >= 0 {
                timeToEmpty = TimeInterval(minutes * 60)
            }

            return PowerSnapshot(
                percent: percent,
                isOnAC: isOnAC,
                isCharging: isCharging,
                timeToEmpty: timeToEmpty
            )
        }
        return fallback
    }
}

private func powerSourcesDidChange(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<IOPowerSourcesReader>.fromOpaque(context)
        .takeUnretainedValue()
        .deliverChange()
}
