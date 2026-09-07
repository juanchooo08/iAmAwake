import Foundation

/// Lo unico que macOS reporta sobre la tapa: un booleano.
///
/// No hay angulo. El sensor de angulo existe solo en los MacBook Pro 2021+,
/// que lo publican por HID (usage page 0x20). En un MacBookAir10,1 ese sensor
/// no esta, asi que `AppleClamshellState` cambia recien cuando la tapa llega a
/// ~5 grados del cierre. Cualquier animacion de "mientras se cierra" arranca en
/// ese instante, no antes: no es una decision de diseno, es el limite del hardware.
public enum LidState: String, Equatable, Sendable, Codable {
    case open
    case closed
}

/// Transicion de tapa ya interpretada, con el contexto que la animacion necesita.
public struct LidTransition: Equatable, Sendable {
    public let to: LidState
    /// Si la app estaba armada cuando ocurrio. Sin esto la animacion no sabe
    /// si tiene algo que celebrar.
    public let wasArmed: Bool
    /// Cuanto estuvo la tapa cerrada. Solo tiene sentido en `.open`.
    public let closedFor: TimeInterval?

    public init(to: LidState, wasArmed: Bool, closedFor: TimeInterval? = nil) {
        self.to = to
        self.wasArmed = wasArmed
        self.closedFor = closedFor
    }
}

/// Frontera con el IORegistry. La implementacion real vive en `LidObserver`.
public protocol LidObserving: AnyObject, Sendable {
    var state: LidState { get }
    func startMonitoring(onChange: @escaping @Sendable (LidState) -> Void)
    func stopMonitoring()
}

/// Quien dibuja la animacion. AppKit queda del otro lado de esta linea.
@MainActor
public protocol OverlayPresenting: AnyObject {
    func play(_ transition: LidTransition)
    /// Corta cualquier animacion en curso y esconde el overlay.
    func dismiss()
}
