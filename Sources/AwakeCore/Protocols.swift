import Foundation

public protocol ClockProviding: Sendable {
    var now: Date { get }
}

public struct SystemClock: ClockProviding {
    public init() {}
    public var now: Date { Date() }
}

/// Evita el sueño por inactividad (display + idle). NO cubre el cierre de tapa.
public protocol SleepInhibiting: AnyObject, Sendable {
    var isEngaged: Bool { get }
    func engage() async throws
    func disengage() async
}

/// Unica via real para el cierre de tapa. Habla con el daemon root.
public protocol LidSleepControlling: AnyObject, Sendable {
    var installState: HelperInstallState { get async }
    func setClamshellSleepDisabled(_ disabled: Bool) async throws
    func heartbeat() async throws
}

public protocol PowerSourceReading: AnyObject, Sendable {
    var snapshot: PowerSnapshot { get }
    func startMonitoring(onChange: @escaping @Sendable (PowerSnapshot) -> Void)
    func stopMonitoring()
}

public protocol ThermalReading: AnyObject, Sendable {
    var level: ThermalLevel { get }
    func startMonitoring(onChange: @escaping @Sendable (ThermalLevel) -> Void)
    func stopMonitoring()
}

public protocol Guarding: AnyObject, Sendable {
    var identifier: GuardID { get }
    func start(onVerdict: @escaping @Sendable (GuardVerdict) -> Void)
    func stop()
    func apply(_ prefs: PreferencesSnapshot)
    /// Veredicto actual sin esperar a la proxima notificacion del sistema.
    var currentVerdict: GuardVerdict { get }
}

@MainActor
public protocol StatusPresenting: AnyObject {
    func render(_ state: ArmState)
    var onToggle: (() -> Void)? { get set }
    var onOpenPreferences: (() -> Void)? { get set }
    var onQuit: (() -> Void)? { get set }
}

public protocol HotkeyRegistering: AnyObject {
    func register(_ combo: HotkeyCombo, action: @escaping @MainActor () -> Void) throws
    func unregister()
}

public protocol PreferencesStoring: AnyObject, Sendable {
    var snapshot: PreferencesSnapshot { get }
    func update(_ transform: @Sendable (inout PreferencesSnapshot) -> Void)
    var changes: AsyncStream<PreferencesSnapshot> { get }
}

public protocol Notifying: AnyObject, Sendable {
    func requestAuthorizationIfNeeded() async
    func notifyDisarmed(reason: DisarmReason) async
    func notifyFailure(_ error: AwakeError) async
}
