import Combine
import Foundation
import Guards
import MenuBar
import Notifier
import Preferences
import StillOnCore

/// Presentador de mentira: usa el `StatusPresentation` real de `MenuBar` (los
/// iconos y textos que veria el usuario) sin instanciar un `NSStatusItem`.
@MainActor
final class FakePresenter: StatusPresenting {
    var onToggle: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    private(set) var rendered: [ArmState] = []

    var presentations: [StatusPresentation] { rendered.map(StatusPresentation.init(state:)) }
    var last: ArmState? { rendered.last }

    func render(_ state: ArmState) {
        rendered.append(state)
    }
}

/// Cola de veredictos emitidos por las guardas.
///
/// Las guardas emiten sincronamente desde el hilo del sistema que las despierta;
/// `PowerState` es `@MainActor`. El `AppDelegate` salta con
/// `Task { @MainActor in ... }`, que es correcto pero no determinista en un test.
/// El harness encola y `pump()` los entrega en orden.
final class PendingVerdicts: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [(GuardID, GuardVerdict)] = []

    func push(_ id: GuardID, _ verdict: GuardVerdict) {
        lock.lock()
        queue.append((id, verdict))
        lock.unlock()
    }

    func drain() -> [(GuardID, GuardVerdict)] {
        lock.lock()
        defer { lock.unlock() }
        let out = queue
        queue.removeAll()
        return out
    }
}

/// Replica el cableado del `AppDelegate` con dobles en cada frontera de sistema.
///
/// Tipos reales donde se puede: `PowerState`, `BatteryGuard`, `ThermalGuard`,
/// `UserNotificationsNotifier` (con sus textos de produccion),
/// `UserDefaultsPreferencesStore` sobre una suite efimera, y `StatusPresentation`.
/// Dobles solo donde hay IOKit, pmset, el daemon o la barra de menu de por medio.
@MainActor
final class Harness {
    let log = CallLog()
    let inhibitor: SpyInhibitor
    let lid: SpyLid
    let deliverer: SpyDeliverer
    let notifier: UserNotificationsNotifier
    let preferences: UserDefaultsPreferencesStore
    let batterySource: FakePowerSource
    let thermalSource: FakeThermal
    let guards: [Guarding]
    let state: PowerState
    let presenter = FakePresenter()

    /// Espeja el timer de heartbeat del `AppDelegate`: solo corre mientras
    /// estamos armados.
    private(set) var heartbeatTimerRunning = false

    private let suiteName: String
    private let defaults: UserDefaults
    private let pending = PendingVerdicts()
    private let preferenceChanges: AsyncStream<PreferencesSnapshot>
    private var preferencesTask: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var appliedPreferences = 0
    private var pendingToggles = 0

    /// Lo que dispararon los otros dos items del menu.
    private(set) var quitRequested = false
    private(set) var preferencesOpened = 0

    init(
        preferences initial: PreferencesSnapshot = PreferencesSnapshot(),
        battery: PowerSnapshot = .plugged(100),
        thermal: ThermalLevel = .nominal,
        lidInstallState: HelperInstallState = .ready(protocolVersion: Wire.protocolVersion),
        lidFailure: StillOnError? = nil,
        inhibitorFailure: StillOnError? = nil,
        notificationsGranted: Bool = true
    ) {
        self.suiteName = "dev.local.stillon.integration.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!

        let store = UserDefaultsPreferencesStore(defaults: defaults)
        store.update { $0 = initial }
        let prefs = store.snapshot

        let log = self.log
        let inhibitor = SpyInhibitor(log: log, failure: inhibitorFailure)
        let lid = SpyLid(log: log, installState: lidInstallState, failure: lidFailure)
        let deliverer = SpyDeliverer(log: log, granted: notificationsGranted)
        let notifier = UserNotificationsNotifier(center: deliverer)

        let batterySource = FakePowerSource(battery)
        let thermalSource = FakeThermal(thermal)
        let guards: [Guarding] = [
            BatteryGuard(reader: batterySource, preferences: prefs),
            ThermalGuard(reader: thermalSource, preferences: prefs),
        ]

        self.inhibitor = inhibitor
        self.lid = lid
        self.deliverer = deliverer
        self.notifier = notifier
        self.preferences = store
        self.batterySource = batterySource
        self.thermalSource = thermalSource
        self.guards = guards
        // El stream se toma aca, no dentro del Task: `AsyncStream` registra su
        // continuation al construirse, y si se construyera despues del primer
        // `update()` ese evento se perderia.
        self.preferenceChanges = store.changes
        self.state = PowerState(
            inhibitor: inhibitor,
            lid: lid,
            guards: guards,
            preferences: store,
            notifier: notifier
        )
    }

    /// Equivalente de `applicationDidFinishLaunching`.
    func start() async {
        let presenter = self.presenter
        subscription = state.$status.sink { [weak self] status in
            // `@Published` publica en `willSet`: hay que renderizar el valor que
            // llega por parametro, no `state.status`, que todavia es el viejo.
            MainActor.assumeIsolated {
                presenter.render(status)
                self?.heartbeatTimerRunning = status.isArmed
            }
        }

        presenter.onToggle = { [weak self] in self?.pendingToggles += 1 }
        presenter.onOpenPreferences = { [weak self] in self?.preferencesOpened += 1 }
        presenter.onQuit = { [weak self] in self?.quitRequested = true }

        let pending = self.pending
        for guardImpl in guards {
            let id = guardImpl.identifier
            guardImpl.start { verdict in pending.push(id, verdict) }
        }

        preferencesTask = Task { [weak self, preferenceChanges] in
            for await snapshot in preferenceChanges {
                guard let self else { return }
                await self.state.applyPreferences(snapshot)
                self.appliedPreferences += 1
            }
        }

        await notifier.requestAuthorizationIfNeeded()
    }

    /// Simula el click en "Armar/Desarmar" del menu (o el disparo del hotkey,
    /// que se cablea a la misma intencion): invoca el callback real del
    /// presentador y ejecuta lo que ese callback pidio.
    func tapMenuToggle() async {
        presenter.onToggle?()
        while pendingToggles > 0 {
            pendingToggles -= 1
            await state.toggle()
        }
    }

    /// Entrega a `PowerState` los veredictos que las guardas emitieron.
    func pump() async {
        for (id, verdict) in pending.drain() {
            await state.report(verdict, from: id)
        }
    }

    /// Un tick del timer de heartbeat. No hace nada si el timer no corre, igual
    /// que en la app.
    func heartbeatTick() async {
        guard heartbeatTimerRunning else { return }
        await state.heartbeatTick()
    }

    /// Cambia preferencias por la via real (`update` → `changes` → `applyPreferences`)
    /// y espera a que el consumidor las haya aplicado.
    func changePreferences(_ transform: @Sendable @escaping (inout PreferencesSnapshot) -> Void) async {
        let before = appliedPreferences
        preferences.update(transform)
        for _ in 0..<200 where appliedPreferences == before {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Equivalente de `applicationWillTerminate`, con el mismo puente sincrono
    /// (`Task.detached` + semaforo acotado) que usa el `AppDelegate`.
    func terminate() {
        heartbeatTimerRunning = false
        preferencesTask?.cancel()
        preferencesTask = nil
        subscription = nil
        for guardImpl in guards { guardImpl.stop() }

        guard state.status.isArmed || inhibitor.isEngaged else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let inhibitor = self.inhibitor
        let lid = self.lid
        Task.detached(priority: .userInitiated) {
            await inhibitor.disengage()
            try? await lid.setClamshellSleepDisabled(false)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)
    }

    /// Se llama al final de cada test: la suite efimera no debe sobrevivir.
    func tearDown() {
        preferencesTask?.cancel()
        preferencesTask = nil
        subscription = nil
        preferences.finish()
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Atajos de lectura

    /// Solo los efectos sobre el mundo exterior, en orden. Es lo que se compara
    /// para verificar secuencias.
    var effects: [String] { log.all }

    var notificationIdentifiers: [String] { deliverer.payloads.map(\.identifier) }
}
