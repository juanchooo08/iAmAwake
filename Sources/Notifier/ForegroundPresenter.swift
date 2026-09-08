import UserNotifications
import os

/// Sin delegado, macOS descarta el banner de cualquier notificacion que llegue
/// mientras la app que la manda es la activa. iAmAwake vive en la barra de menu,
/// asi que se vuelve la app activa cada vez que abris su menu: justo el momento
/// en que arma y desarma. El aviso quedaba en el centro de notificaciones pero
/// nunca aparecia en pantalla.
@MainActor
public final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    private static let shared = ForegroundNotificationPresenter()

    /// Se llama una sola vez, al arrancar. Sin esto el resto del modulo entrega
    /// notificaciones que el usuario no ve.
    public static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    /// Deja en el log los ajustes que el sistema le aplica a la app. Sin esto,
    /// "se entrego pero no se vio" no se puede distinguir de un ajuste de
    /// Configuracion del Sistema o de un Focus activo.
    ///
    /// Vive aca y no en el notifier porque toca `UNUserNotificationCenter`
    /// directo, y eso solo es seguro dentro de un bundle real.
    public static func logSettings() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        log.notice("""
            ajustes -> permiso=\(s.authorizationStatus.rawValue, privacy: .public) \
            alertas=\(s.alertSetting.rawValue, privacy: .public) \
            estilo=\(s.alertStyle.rawValue, privacy: .public) \
            centro=\(s.notificationCenterSetting.rawValue, privacy: .public) \
            pantallaBloqueo=\(s.lockScreenSetting.rawValue, privacy: .public) \
            previews=\(s.showPreviewsSetting.rawValue, privacy: .public) \
            sonido=\(s.soundSetting.rawValue, privacy: .public)
            """)
    }

    nonisolated private static let log = Logger(subsystem: "dev.local.iamawake", category: "notificaciones")

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Self.log.notice("banner pedido al sistema: \(notification.request.identifier, privacy: .public)")
        completionHandler([.banner, .list, .sound])
    }
}
