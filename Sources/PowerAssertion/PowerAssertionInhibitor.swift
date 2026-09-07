import Foundation
import IOKit.pwr_mgt
import StillOnCore

/// Impide el sueño por inactividad creando dos power assertions de IOKit:
/// `NoDisplaySleep` (pantalla) y `PreventUserIdleSystemSleep` (sistema por idle).
///
/// # LIMITE MEDIDO — NO cubre el cierre de tapa
///
/// Estas assertions **no** evitan que la Mac duerma al cerrar la tapa. Medido en
/// este hardware (MacBookAir10,1 / M1 / macOS 26.6.2): durmio a los **22 segundos**
/// con las tres assertions activas (`NoDisplaySleep` + `PreventUserIdleSystemSleep`
/// + `PreventSystemSleep`). No es un bug de este modulo ni algo que se arregle
/// agregando una cuarta assertion: el clamshell sleep lo decide `IOPMrootDomain`
/// por otra via.
///
/// El cierre de tapa es responsabilidad de `LidSleepControlling` (daemon root que
/// escribe `DisableClamshellSleep`). Las dos se arman juntas; este modulo por si
/// solo solo cubre display + idle.
///
/// # Fallback
///
/// Si IOKit falla, se intenta `/usr/bin/caffeinate -dis` como proceso hijo, que se
/// mata en `disengage()`. Solo si el fallback tambien falla se lanza
/// `StillOnError.assertionFailed`.
public final class PowerAssertionInhibitor: SleepInhibiting, @unchecked Sendable {

    /// Los tipos de assertion que se crean, en orden.
    static let assertionTypes: [String] = [
        kIOPMAssertionTypeNoDisplaySleep,
        kIOPMAssertionTypePreventUserIdleSystemSleep,
    ]

    static let assertionName = "StillOn: keeping this Mac awake"
    static let caffeinatePath = "/usr/bin/caffeinate"
    static let caffeinateArguments = ["-dis"]

    private let assertions: AssertionCreating
    private let spawner: ProcessSpawning

    private let lock = NSLock()
    private var activeIDs: [IOPMAssertionID] = []
    private var fallbackProcess: SpawnedProcess?

    public convenience init() {
        self.init(assertions: IOKitAssertionCreator(), spawner: FoundationProcessSpawner())
    }

    init(assertions: AssertionCreating, spawner: ProcessSpawning) {
        self.assertions = assertions
        self.spawner = spawner
    }

    public var isEngaged: Bool {
        lock.lock(); defer { lock.unlock() }
        return !activeIDs.isEmpty || fallbackProcess != nil
    }

    /// True si la inhibicion activa viene del fallback `caffeinate` y no de IOKit.
    /// Expuesto para que la UI pueda advertir que se esta en modo degradado.
    public var isUsingFallback: Bool {
        lock.lock(); defer { lock.unlock() }
        return fallbackProcess != nil
    }

    public func engage() async throws {
        try performEngage()
    }

    public func disengage() async {
        performDisengage()
    }

    // Los cuerpos reales son sincronos: `NSLock` no se puede tomar directamente
    // desde un contexto async, y aca no hay ningun `await` que suspenda.

    private func performEngage() throws {
        lock.lock()
        defer { lock.unlock() }

        // Idempotente: engage doble no duplica assertions.
        guard activeIDs.isEmpty, fallbackProcess == nil else { return }

        var created: [IOPMAssertionID] = []
        for type in Self.assertionTypes {
            let result = assertions.create(type: type, name: Self.assertionName)
            guard result.status == kIOReturnSuccess else {
                // Nada de fallos a medias: se libera lo que si se creo antes de
                // intentar el fallback.
                for id in created { _ = assertions.release(id) }
                try engageFallbackLocked(afterFailure: result.status)
                return
            }
            created.append(result.id)
        }

        activeIDs = created
    }

    private func performDisengage() {
        lock.lock()
        defer { lock.unlock() }

        for id in activeIDs { _ = assertions.release(id) }
        activeIDs = []

        fallbackProcess?.terminateAndWait()
        fallbackProcess = nil
    }

    /// Requiere `lock` tomado.
    private func engageFallbackLocked(afterFailure status: kern_return_t) throws {
        do {
            fallbackProcess = try spawner.spawn(
                path: Self.caffeinatePath,
                arguments: Self.caffeinateArguments
            )
        } catch {
            fallbackProcess = nil
            throw StillOnError.assertionFailed(status)
        }
    }
}
