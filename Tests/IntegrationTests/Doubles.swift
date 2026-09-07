import Foundation
import Notifier
import AwakeCore

/// Bitacora ordenada de efectos observables. Es lo que permite verificar el
/// ORDEN de las llamadas y no solo que ocurrieron: revertir el interruptor de
/// tapa despues de notificar, por ejemplo, seria un bug que "todas las llamadas
/// ocurrieron" no atrapa.
///
/// `NSLock` porque los dobles los tocan las guardas, que emiten en el hilo que
/// les toque, y el MainActor.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    /// Descarta lo registrado hasta ahora, para poder afirmar sobre el ORDEN de
    /// los efectos de un solo paso sin arrastrar los del arranque.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    func count(of entry: String) -> Int {
        all.filter { $0 == entry }.count
    }

    func reset() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

enum Effect {
    static let engage = "inhibitor.engage"
    static let disengage = "inhibitor.disengage"
    static let lidOn = "lid.set(true)"
    static let lidOff = "lid.set(false)"
    static let heartbeat = "lid.heartbeat"
    static func notify(_ identifier: String) -> String { "notify.\(identifier)" }
}

/// `SleepInhibiting` sin IOKit. `failure` simula que `IOPMAssertionCreateWithName`
/// fallo y que el fallback a `caffeinate` tampoco pudo.
final class SpyInhibitor: SleepInhibiting, @unchecked Sendable {
    private let lock = NSLock()
    private let log: CallLog
    private var _engaged = false
    private var _failure: AwakeError?

    init(log: CallLog, failure: AwakeError? = nil) {
        self.log = log
        self._failure = failure
    }

    var isEngaged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _engaged
    }

    func setFailure(_ error: AwakeError?) {
        lock.lock()
        _failure = error
        lock.unlock()
    }

    // Los cuerpos con lock viven en metodos sincronos: Swift 6 prohibe
    // NSLock.lock() dentro de una funcion async.
    private func markEngaged() -> AwakeError? {
        lock.lock()
        defer { lock.unlock() }
        if _failure == nil { _engaged = true }
        return _failure
    }

    private func markDisengaged() {
        lock.lock()
        defer { lock.unlock() }
        _engaged = false
    }

    func engage() async throws {
        log.record(Effect.engage)
        if let failure = markEngaged() { throw failure }
    }

    func disengage() async {
        log.record(Effect.disengage)
        markDisengaged()
    }
}

/// `LidSleepControlling` sin daemon ni socket. `failure` simula el daemon
/// ausente: toda operacion de cable falla.
final class SpyLid: LidSleepControlling, @unchecked Sendable {
    private let lock = NSLock()
    private let log: CallLog
    private var _clamshellSleepDisabled = false
    private var _installState: HelperInstallState
    private var _failure: AwakeError?
    private var _heartbeats = 0

    init(
        log: CallLog,
        installState: HelperInstallState = .ready(protocolVersion: Wire.protocolVersion),
        failure: AwakeError? = nil
    ) {
        self.log = log
        self._installState = installState
        self._failure = failure
    }

    private var installStateLocked: HelperInstallState {
        lock.lock()
        defer { lock.unlock() }
        return _installState
    }

    var installState: HelperInstallState {
        get async { installStateLocked }
    }

    var clamshellSleepDisabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _clamshellSleepDisabled
    }

    var heartbeats: Int {
        lock.lock()
        defer { lock.unlock() }
        return _heartbeats
    }

    func setFailure(_ error: AwakeError?) {
        lock.lock()
        _failure = error
        lock.unlock()
    }

    private func applyClamshell(_ disabled: Bool) -> AwakeError? {
        lock.lock()
        defer { lock.unlock() }
        if _failure == nil { _clamshellSleepDisabled = disabled }
        return _failure
    }

    func setClamshellSleepDisabled(_ disabled: Bool) async throws {
        log.record("lid.set(\(disabled))")
        if let failure = applyClamshell(disabled) { throw failure }
    }

    private func countHeartbeat() -> AwakeError? {
        lock.lock()
        defer { lock.unlock() }
        if _failure == nil { _heartbeats += 1 }
        return _failure
    }

    func heartbeat() async throws {
        log.record(Effect.heartbeat)
        if let failure = countHeartbeat() { throw failure }
    }
}

/// Doble del centro de notificaciones. Se usa con el `UserNotificationsNotifier`
/// real para que los textos que se verifican sean los de produccion.
final class SpyDeliverer: NotificationDelivering, @unchecked Sendable {
    private let lock = NSLock()
    private let log: CallLog
    private let granted: Bool
    private var _payloads: [NotificationPayload] = []
    private var _authorizationRequests = 0

    init(log: CallLog, granted: Bool = true) {
        self.log = log
        self.granted = granted
    }

    var payloads: [NotificationPayload] {
        lock.lock()
        defer { lock.unlock() }
        return _payloads
    }

    /// Fuera de `CallLog` a proposito: el pedido de permiso ocurre en el arranque
    /// y ensuciaria las secuencias de efectos que verifican los tests.
    var authorizationRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return _authorizationRequests
    }

    private func countRequest() {
        lock.lock()
        defer { lock.unlock() }
        _authorizationRequests += 1
    }

    private func record(_ payload: NotificationPayload) {
        lock.lock()
        defer { lock.unlock() }
        _payloads.append(payload)
    }

    func requestAuthorization() async -> Bool {
        countRequest()
        return granted
    }

    func deliver(_ payload: NotificationPayload) async {
        log.record(Effect.notify(payload.identifier))
        record(payload)
    }
}

/// `PowerSourceReading` de mentira. Ni IOKit ni `IOPSCopyPowerSourcesInfo`.
final class FakePowerSource: PowerSourceReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _snapshot: PowerSnapshot
    private var onChange: (@Sendable (PowerSnapshot) -> Void)?

    init(_ snapshot: PowerSnapshot) { _snapshot = snapshot }

    var snapshot: PowerSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return _snapshot
    }

    var isMonitoring: Bool {
        lock.lock()
        defer { lock.unlock() }
        return onChange != nil
    }

    func startMonitoring(onChange: @escaping @Sendable (PowerSnapshot) -> Void) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()
    }

    func stopMonitoring() {
        lock.lock()
        onChange = nil
        lock.unlock()
    }

    func emit(_ snapshot: PowerSnapshot) {
        lock.lock()
        _snapshot = snapshot
        let callback = onChange
        lock.unlock()
        callback?(snapshot)
    }
}

/// `ThermalReading` de mentira. Sin `ProcessInfo.thermalState`.
final class FakeThermal: ThermalReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _level: ThermalLevel
    private var onChange: (@Sendable (ThermalLevel) -> Void)?

    init(_ level: ThermalLevel) { _level = level }

    var level: ThermalLevel {
        lock.lock()
        defer { lock.unlock() }
        return _level
    }

    var isMonitoring: Bool {
        lock.lock()
        defer { lock.unlock() }
        return onChange != nil
    }

    func startMonitoring(onChange: @escaping @Sendable (ThermalLevel) -> Void) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()
    }

    func stopMonitoring() {
        lock.lock()
        onChange = nil
        lock.unlock()
    }

    func emit(_ level: ThermalLevel) {
        lock.lock()
        _level = level
        let callback = onChange
        lock.unlock()
        callback?(level)
    }
}

extension PowerSnapshot {
    static func battery(_ percent: Int) -> PowerSnapshot {
        PowerSnapshot(percent: percent, isOnAC: false, isCharging: false)
    }
    static func plugged(_ percent: Int) -> PowerSnapshot {
        PowerSnapshot(percent: percent, isOnAC: true, isCharging: true)
    }
}
