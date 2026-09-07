import AwakeCore
import Foundation

/// Cuanto tiempo aguanto, en castellano y sin decimales.
public enum AwakeTally {
    public static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        guard total >= 60 else { return "\(max(total, 0)) s" }

        let minutes = total / 60
        guard minutes >= 60 else { return "\(minutes) min" }

        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// Que dice la animacion. Separado del dibujo para poder testear las reglas sin
/// abrir una ventana.
public struct OverlayCopy: Equatable, Sendable {
    public enum Motion: Equatable, Sendable {
        /// Los parpados barren hacia el centro y se frenan. El ojo queda abierto.
        case closing
        /// Los parpados se retiran y aparece el resumen.
        case opening
    }

    public let motion: Motion
    public let headline: String
    public let detail: String

    public init(motion: Motion, headline: String, detail: String) {
        self.motion = motion
        self.headline = headline
        self.detail = detail
    }

    /// `nil` cuando no hay nada que mostrar.
    ///
    /// Si la app no estaba armada, la tapa cerrandose es una noche normal: la Mac
    /// se duerme y una animacion ahi solo estorba. La animacion es la prueba de
    /// que iAmAwake esta haciendo algo, asi que solo aparece cuando lo hace.
    public static func forTransition(_ transition: LidTransition) -> OverlayCopy? {
        guard transition.wasArmed else { return nil }

        switch transition.to {
        case .closed:
            return OverlayCopy(
                motion: .closing,
                headline: "iAmAwake",
                detail: "seguí trabajando, no me duermo"
            )

        case .open:
            guard let closedFor = transition.closedFor, closedFor >= 1 else {
                // Abrir y cerrar de golpe no merece un resumen con "0 s".
                return OverlayCopy(motion: .opening, headline: "Acá estoy", detail: "seguí despierto")
            }
            return OverlayCopy(
                motion: .opening,
                headline: "Seguí despierto",
                detail: "\(AwakeTally.duration(closedFor)) con la tapa cerrada"
            )
        }
    }
}
