import Foundation
import AwakeCore

/// Mock de `PowerSourceReading`. Los tests de guards NUNCA tocan IOKit.
final class MockPowerSource: PowerSourceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshot: PowerSnapshot
    private var onChange: (@Sendable (PowerSnapshot) -> Void)?
    private var _stopCount = 0

    init(_ snapshot: PowerSnapshot) { _snapshot = snapshot }

    var snapshot: PowerSnapshot {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
    }

    var isMonitoring: Bool {
        lock.lock(); defer { lock.unlock() }
        return onChange != nil
    }

    var stopCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _stopCount
    }

    func startMonitoring(onChange: @escaping @Sendable (PowerSnapshot) -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.onChange = onChange
    }

    func stopMonitoring() {
        lock.lock(); defer { lock.unlock() }
        onChange = nil
        _stopCount += 1
    }

    /// Simula que el sistema publico una fuente distinta.
    func emit(_ snapshot: PowerSnapshot) {
        lock.lock()
        _snapshot = snapshot
        let callback = onChange
        lock.unlock()
        callback?(snapshot)
    }
}

final class MockThermal: ThermalReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _level: ThermalLevel
    private var onChange: (@Sendable (ThermalLevel) -> Void)?
    private var _stopCount = 0

    init(_ level: ThermalLevel) { _level = level }

    var level: ThermalLevel {
        lock.lock(); defer { lock.unlock() }
        return _level
    }

    var isMonitoring: Bool {
        lock.lock(); defer { lock.unlock() }
        return onChange != nil
    }

    var stopCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _stopCount
    }

    func startMonitoring(onChange: @escaping @Sendable (ThermalLevel) -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.onChange = onChange
    }

    func stopMonitoring() {
        lock.lock(); defer { lock.unlock() }
        onChange = nil
        _stopCount += 1
    }

    func emit(_ level: ThermalLevel) {
        lock.lock()
        _level = level
        let callback = onChange
        lock.unlock()
        callback?(level)
    }
}

/// Acumulador de veredictos, seguro para llamadas desde cualquier hilo.
final class VerdictRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _verdicts: [GuardVerdict] = []

    var verdicts: [GuardVerdict] {
        lock.lock(); defer { lock.unlock() }
        return _verdicts
    }

    var count: Int { verdicts.count }
    var last: GuardVerdict? { verdicts.last }

    var sink: @Sendable (GuardVerdict) -> Void {
        { [self] verdict in
            lock.lock()
            _verdicts.append(verdict)
            lock.unlock()
        }
    }
}

extension PowerSnapshot {
    static func onBattery(_ percent: Int) -> PowerSnapshot {
        PowerSnapshot(percent: percent, isOnAC: false, isCharging: false)
    }
    static func onAC(_ percent: Int, charging: Bool = true) -> PowerSnapshot {
        PowerSnapshot(percent: percent, isOnAC: true, isCharging: charging)
    }
}

extension PreferencesSnapshot {
    static func batteryPrefs(threshold: Int, enabled: Bool = true) -> PreferencesSnapshot {
        PreferencesSnapshot(batteryThreshold: threshold, batteryGuardEnabled: enabled)
    }
    static func thermalPrefs(ceiling: ThermalLevel, enabled: Bool = true) -> PreferencesSnapshot {
        PreferencesSnapshot(thermalCeiling: ceiling, thermalGuardEnabled: enabled)
    }
}
