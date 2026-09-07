import AwakeCore
import Foundation

/// Lleva la cuenta de cuanto estuvo cerrada la tapa.
///
/// Vive aca y no en el `AppDelegate` porque es logica con un caso borde real: si
/// se limpia `closedAt` antes de leerlo, la duracion se pierde y el resumen sale
/// vacio. Eso se testea; en el AppDelegate no se testearia.
@MainActor
public final class LidSessionTracker {
    private let clock: ClockProviding
    private var closedAt: Date?

    public init(clock: ClockProviding = SystemClock()) {
        self.clock = clock
    }

    /// Registra el cambio y devuelve la transicion lista para animar.
    public func transition(to state: LidState, armed: Bool) -> LidTransition {
        switch state {
        case .closed:
            closedAt = clock.now
            return LidTransition(to: .closed, wasArmed: armed)

        case .open:
            // Leer ANTES de limpiar. Al reves la duracion se pierde siempre.
            let closedFor = closedAt.map { clock.now.timeIntervalSince($0) }
            closedAt = nil
            return LidTransition(to: .open, wasArmed: armed, closedFor: closedFor)
        }
    }
}
