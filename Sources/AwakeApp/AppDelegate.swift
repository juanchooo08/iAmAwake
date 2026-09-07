import AppKit
import Combine
import Foundation
import Guards
import HelperClient
import Hotkey
import LidObserver
import MenuBar
import Notifier
import Overlay
import PowerAssertion
import Preferences
import AwakeCore

/// Unico lugar del proyecto que conoce implementaciones concretas.
///
/// Construye el grafo (una implementacion por protocolo), se lo pasa a un unico
/// `PowerState`, y cablea las cuatro direcciones de trafico:
///
/// - `PowerState.status` → `StatusPresenting.render`
/// - menu / hotkey → `PowerState.toggle()`
/// - guardas → `PowerState.report(_:from:)`
/// - preferencias → `PowerState.applyPreferences(_:)` (+ re-registro del hotkey)
///
/// Nada de logica de negocio vive aca: si algo decide *cuando* armar o desarmar,
/// va en `PowerState`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Grafo concreto

    private let preferencesStore: UserDefaultsPreferencesStore
    private let inhibitor: PowerAssertionInhibitor
    private let lid: SocketLidController
    private let notificationCenter: UNCenterAdapter
    private let notifier: UserNotificationsNotifier
    private let hotkeys: CarbonHotkeyRegistrar
    private let guardList: [Guarding]
    private let powerState: PowerState
    private let lidObserver: LidObserver
    private let overlay: CurtainOverlayController

    /// Se crea en `applicationDidFinishLaunching`: `NSStatusBar.system` no tiene
    /// sentido antes de que la app exista.
    private var presenter: StatusItemController?

    // MARK: - Estado del cableado

    private var statusSubscription: AnyCancellable?
    private var preferencesTask: Task<Void, Never>?
    private var heartbeatTimer: Timer?
    private var preferencesWindow: PreferencesWindowController?
    private var registeredHotkey: HotkeyCombo?

    /// Cuenta cuanto estuvo cerrada la tapa. Ver `LidSessionTracker`.
    private let lidSessions = LidSessionTracker()

    /// Tope para el desarme sincrono de `applicationWillTerminate`.
    private static let terminationTimeout: TimeInterval = 2.0

    override init() {
        let store = UserDefaultsPreferencesStore()
        let prefs = store.snapshot.clamped()

        let center = UNCenterAdapter()
        let notifier = UserNotificationsNotifier(center: center)
        let inhibitor = PowerAssertionInhibitor()
        let lid = SocketLidController()
        let guards: [Guarding] = [
            BatteryGuard(reader: IOPowerSourcesReader(), preferences: prefs),
            ThermalGuard(reader: ProcessInfoThermalReader(), preferences: prefs),
        ]

        self.preferencesStore = store
        self.notificationCenter = center
        self.notifier = notifier
        self.inhibitor = inhibitor
        self.lid = lid
        self.hotkeys = CarbonHotkeyRegistrar()
        self.guardList = guards
        self.lidObserver = LidObserver(source: IORegistryClamshellSource())
        self.overlay = CurtainOverlayController()
        self.powerState = PowerState(
            inhibitor: inhibitor,
            lid: lid,
            guards: guards,
            preferences: store,
            notifier: notifier
        )

        super.init()
    }

    // MARK: - Ciclo de vida

    func applicationDidFinishLaunching(_ notification: Notification) {
        let presenter = StatusItemController()
        self.presenter = presenter

        wireMenu(presenter)
        observeStatus(presenter)
        startGuards()
        observeLid()
        observePreferences()
        registerHotkey(preferencesStore.snapshot.hotkey)

        // Render inicial: el sink de Combine solo dispara ante cambios.
        presenter.render(powerState.status)

        Task { [notifier, lid] in
            await notifier.requestAuthorizationIfNeeded()
            if await lid.installState == .notInstalled {
                await self.warnHelperMissing()
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// # Por que hay un semaforo aca
    ///
    /// Con `disablesleep=1` la Mac no duerme nunca. Si el proceso muere sin
    /// revertir, la bateria se drena hasta 0 con la tapa cerrada. El dead man's
    /// switch del daemon es la segunda linea de defensa, no la primera: hay que
    /// revertir *antes* de morir.
    ///
    /// `applicationWillTerminate` es sincrono y el revert es `async`, asi que hay
    /// que bloquear el hilo principal hasta que termine. Dos detalles que hacen
    /// que esto no se cuelgue:
    ///
    /// 1. El trabajo va en `Task.detached`. Un `Task {}` comun heredaria el
    ///    MainActor, que es justo el hilo que estamos bloqueando: deadlock seguro.
    ///    Por el mismo motivo NO se usa `PowerState.requestDisarm(.appTerminating)`,
    ///    que es `@MainActor`; se llama directo a las dos dependencias, que son
    ///    `Sendable` y hacen su trabajo fuera del hilo principal.
    /// 2. La espera tiene tope (`terminationTimeout`). Si el daemon no responde,
    ///    preferimos perder el revert a colgar el logout del usuario; ahi si entra
    ///    el dead man's switch, que revierte por timeout de heartbeat.
    func applicationWillTerminate(_ notification: Notification) {
        stopHeartbeat()
        preferencesTask?.cancel()
        preferencesTask = nil
        statusSubscription = nil
        hotkeys.unregister()
        lidObserver.stopMonitoring()
        overlay.dismiss()
        for guardImpl in guardList { guardImpl.stop() }

        guard powerState.status.isArmed || inhibitor.isEngaged else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let inhibitor = self.inhibitor
        let lid = self.lid
        Task.detached(priority: .userInitiated) {
            await inhibitor.disengage()
            try? await lid.setClamshellSleepDisabled(false)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + Self.terminationTimeout)
    }

    // MARK: - Cableado

    private func wireMenu(_ presenter: StatusItemController) {
        presenter.onToggle = { [powerState] in
            Task { @MainActor in await powerState.toggle() }
        }
        presenter.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }
        presenter.onQuit = {
            NSApp.terminate(nil)
        }
    }

    /// Se suscribe al `@Published` y renderiza **el valor que llega por parametro**.
    /// `@Published` publica en `willSet`, asi que `powerState.status` todavia tiene
    /// el valor viejo cuando corre este closure: leerlo de ahi renderizaria un
    /// estado atrasado.
    private func observeStatus(_ presenter: StatusItemController) {
        statusSubscription = powerState.$status.sink { [weak self] state in
            MainActor.assumeIsolated {
                presenter.render(state)
                self?.syncHeartbeat(for: state)
            }
        }
    }

    /// La tapa no decide nada: solo dispara la animacion. Si esto fallara, iAmAwake
    /// sigue manteniendo la Mac despierta igual — es decoracion, no mecanismo.
    ///
    /// El callback llega por el dispatch queue main (lo fija
    /// `IORegistryClamshellSource`), asi que se puede entrar al MainActor sin
    /// saltar de turno: en el cierre cada milisegundo cuenta, el backlight se
    /// apaga a los ~0.2 s.
    private func observeLid() {
        lidObserver.startMonitoring { [weak self] state in
            MainActor.assumeIsolated { self?.handleLid(state) }
        }
    }

    private func handleLid(_ state: LidState) {
        // El tracker se actualiza siempre, aunque las animaciones esten apagadas:
        // si no, prenderlas a mitad de una tapa cerrada daria una duracion falsa.
        let transition = lidSessions.transition(to: state, armed: powerState.status.isArmed)
        guard preferencesStore.snapshot.animationsEnabled else { return }
        overlay.play(transition)
    }

    private func startGuards() {
        let state = powerState
        for guardImpl in guardList {
            let id = guardImpl.identifier
            guardImpl.start { verdict in
                Task { @MainActor in await state.report(verdict, from: id) }
            }
        }
    }

    private func observePreferences() {
        preferencesTask = Task { [weak self, preferencesStore, powerState] in
            for await snapshot in preferencesStore.changes {
                if Task.isCancelled { return }
                await powerState.applyPreferences(snapshot)
                self?.registerHotkey(snapshot.hotkey)
            }
        }
    }

    // MARK: - Hotkey

    /// Re-registra solo si la combinacion cambio: `register` desregistra la
    /// anterior, y repetirlo en cada cambio de preferencia (volumen de batería,
    /// techo termico) seria trabajo inutil sobre Carbon.
    private func registerHotkey(_ combo: HotkeyCombo) {
        guard registeredHotkey != combo else { return }
        let state = powerState
        do {
            try hotkeys.register(combo) {
                Task { @MainActor in await state.toggle() }
            }
            registeredHotkey = combo
        } catch let error as AwakeError {
            registeredHotkey = nil
            Task { [notifier] in await notifier.notifyFailure(error) }
        } catch {
            registeredHotkey = nil
        }
    }

    // MARK: - Heartbeat

    /// El daemon revierte solo si deja de recibir heartbeats, asi que el timer
    /// solo hace falta mientras estamos armados.
    private func syncHeartbeat(for state: ArmState) {
        if state.isArmed {
            startHeartbeat()
        } else {
            stopHeartbeat()
        }
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        let state = powerState
        let timer = Timer.scheduledTimer(
            withTimeInterval: Wire.heartbeatInterval,
            repeats: true
        ) { _ in
            Task { @MainActor in await state.heartbeatTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Preferencias

    private func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(store: preferencesStore)
        }
        preferencesWindow?.present()
    }

    // MARK: - Daemon ausente

    /// Sin el daemon las power assertions cubren display + idle, pero el cierre de
    /// tapa NO. El usuario tiene que enterarse al arrancar, no cuando se le
    /// duerma la Mac con la tapa cerrada. No instalamos nada por nuestra cuenta:
    /// requiere root y esa es una decision del usuario.
    private func warnHelperMissing() async {
        await notificationCenter.deliver(
            NotificationPayload(
                identifier: "dev.local.iamawake.helper-missing",
                title: "iAmAwake: falta el componente con privilegios",
                body: """
                Sin él, cerrar la tapa duerme la Mac igual. Las demás protecciones \
                (pantalla e inactividad) siguen funcionando. Para instalarlo, corré \
                una vez: sudo Scripts/install-helper.sh
                """
            )
        )
    }
}
