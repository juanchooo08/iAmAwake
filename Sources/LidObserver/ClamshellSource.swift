import AwakeCore
import Foundation

/// Frontera con el IORegistry, aislada para poder testear la logica de dedupe
/// sin abrir la tapa de una Mac real.
///
/// `subscribe` no dice QUE cambio: `IOServiceAddInterestNotification` sobre
/// `IOPMrootDomain` dispara ante cualquier propiedad. Quien la use tiene que
/// releer y comparar.
public protocol ClamshellSource: AnyObject, Sendable {
    /// `nil` si el IORegistry no publica la propiedad (Mac de escritorio, por ejemplo).
    func read() -> LidState?
    func subscribe(_ onAnyChange: @escaping @Sendable () -> Void)
    func unsubscribe()
}
