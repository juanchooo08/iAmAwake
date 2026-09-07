import Foundation
import AwakeCore
import UserNotifications

/// Contenido de una notificacion, ya resuelto a texto.
/// Es lo que se testea: los textos se pueden verificar sin disparar nada real.
public struct NotificationPayload: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String

    public init(identifier: String, title: String, body: String) {
        self.identifier = identifier
        self.title = title
        self.body = body
    }
}

/// Centro de notificaciones abstraido, para poder inyectar un doble en tests.
public protocol NotificationDelivering: AnyObject, Sendable {
    /// - Returns: `true` si el usuario autorizo alertas + sonido.
    func requestAuthorization() async -> Bool
    func deliver(_ payload: NotificationPayload) async
}

/// Adaptador real sobre `UNUserNotificationCenter`.
///
/// El centro se resuelve perezosamente: `UNUserNotificationCenter.current()` explota
/// si el proceso no tiene bundle identifier (por ejemplo, el binario suelto de SPM).
public final class UNCenterAdapter: NotificationDelivering, @unchecked Sendable {

    private let center: () -> UNUserNotificationCenter?

    public init(center: @escaping () -> UNUserNotificationCenter? = { UNUserNotificationCenter.current() }) {
        self.center = center
    }

    public func requestAuthorization() async -> Bool {
        guard let center = center() else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            NSLog("[iAmAwake] no se pudo pedir permiso de notificaciones: \(error.localizedDescription)")
            return false
        }
    }

    public func deliver(_ payload: NotificationPayload) async {
        guard let center = center() else { return }
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: payload.identifier + "-" + UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            NSLog("[iAmAwake] no se pudo entregar la notificacion: \(error.localizedDescription)")
        }
    }
}
