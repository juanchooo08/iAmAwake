import Foundation
import AwakeCore

/// Decision pura del dead man's switch: "¿paso demasiado tiempo sin señales de
/// vida de la app?".
///
/// No hace I/O, no crea timers, no toca `pmset`. Solo acumula el instante de la
/// ultima actividad y responde si ya vencio. El daemon (`iamawaked`) es quien la
/// consulta periodicamente y actua; asi la logica temporal se testea con un
/// reloj falso y sin esperas reales.
///
/// Este archivo se compila en dos targets: `HelperClient` (donde vive el fuente
/// y los tests) y `iamawaked` (que lo usa de verdad). Ver los README de ambos.
public final class DeadManTimer: @unchecked Sendable {

    public enum State: Equatable, Sendable {
        /// El daemon no esta armado: no hay nada que revertir.
        case idle
        /// Armado y con actividad reciente.
        case alive
        /// Armado y sin actividad por mas de `timeout`. Hay que revertir.
        case expired
    }

    /// Silencio maximo tolerado antes de revertir.
    public let timeout: TimeInterval

    private let clock: ClockProviding
    private let lock = NSLock()
    private var lastActivity: Date?

    public init(timeout: TimeInterval = Wire.heartbeatTimeout, clock: ClockProviding = SystemClock()) {
        self.timeout = timeout
        self.clock = clock
    }

    /// Empieza a vigilar. Cuenta como actividad: armar es una señal de vida.
    public func arm() {
        lock.lock(); defer { lock.unlock() }
        lastActivity = clock.now
    }

    /// Deja de vigilar. Idempotente.
    public func disarm() {
        lock.lock(); defer { lock.unlock() }
        lastActivity = nil
    }

    public var isArmed: Bool {
        lock.lock(); defer { lock.unlock() }
        return lastActivity != nil
    }

    /// Registra una señal de vida (cualquier request del cliente). No arma:
    /// si no estaba armado, no pasa nada.
    public func noteActivity() {
        lock.lock(); defer { lock.unlock() }
        guard lastActivity != nil else { return }
        lastActivity = clock.now
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        guard let last = lastActivity else { return .idle }
        // `>=` y no `>`: con timeout exacto ya se considera vencido. Ante la duda,
        // revertir. El costo de revertir de mas es que la Mac duerma; el de
        // revertir de menos es una bateria en 0.
        return clock.now.timeIntervalSince(last) >= timeout ? .expired : .alive
    }

    public var hasExpired: Bool { state == .expired }

    /// Segundos que faltan para vencer, o `nil` si no esta armado. Para logs.
    public var timeRemaining: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        guard let last = lastActivity else { return nil }
        return max(0, timeout - clock.now.timeIntervalSince(last))
    }
}
