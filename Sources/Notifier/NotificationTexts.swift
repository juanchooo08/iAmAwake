import Foundation
import AwakeCore

/// Todos los textos viven aca, puros y sin efectos: se testean sin tocar
/// `UNUserNotificationCenter`.
public enum NotificationTexts {

    public static let disarmTitle = "iAmAwake se desarmó"
    public static let failureTitle = "iAmAwake tuvo un problema"

    /// - Returns: `nil` cuando el motivo no amerita notificar.
    ///   `.user` y `.appTerminating` son acciones del propio usuario: ya lo sabe.
    public static func disarmed(_ reason: DisarmReason) -> NotificationPayload? {
        switch reason {
        case .user, .appTerminating:
            return nil

        case .lowBattery(let percent):
            return NotificationPayload(
                identifier: "disarm.lowBattery",
                title: disarmTitle,
                body: "iAmAwake se desarmó — batería en \(percent)%. Tu Mac va a poder dormir para no quedarse sin carga."
            )

        case .thermal(let level):
            return NotificationPayload(
                identifier: "disarm.thermal",
                title: disarmTitle,
                body: "iAmAwake se desarmó — temperatura alta (\(name(of: level))). Con la tapa cerrada el calor no se disipa."
            )

        case .assertionFailure(let error):
            return NotificationPayload(
                identifier: "disarm.assertionFailure",
                title: disarmTitle,
                body: "iAmAwake se desarmó — \(describe(error))"
            )
        }
    }

    public static func failure(_ error: AwakeError) -> NotificationPayload {
        NotificationPayload(
            identifier: "failure." + shortName(error),
            title: failureTitle,
            body: describe(error)
        )
    }

    // MARK: - Textos por error

    public static func describe(_ error: AwakeError) -> String {
        switch error {
        case .assertionFailed(let code):
            return "No se pudo bloquear el sueño del sistema: IOKit devolvió el código \(code). "
                + "Probá desarmar y volver a armar; si sigue fallando, reiniciá la Mac."

        case .helperUnavailable:
            return "El daemon iamawaked no está instalado o no está corriendo. Sin él NO se cubre el cierre de tapa: "
                + "al cerrar la tapa tu Mac va a dormir igual, que es justamente lo que querés evitar. "
                + "Instalalo una vez con sudo Scripts/install-helper.sh."

        case .helperRefused(let message):
            return "El daemon iamawaked rechazó la orden: \(message). "
                + "Revisá el log del daemon con log show --predicate 'process == \"iamawaked\"'."

        case .helperVersionMismatch(let expected, let got):
            return "El daemon iamawaked habla la versión \(got) del protocolo y la app espera la \(expected). "
                + "Reinstalá el daemon con sudo Scripts/install-helper.sh para que coincidan."

        case .hotkeyRegistrationFailed(let status):
            return "No se pudo registrar el atajo de teclado (código \(status)). "
                + "Probablemente otra app ya lo tiene tomado: elegí otra combinación en Preferencias."

        case .notificationPermissionDenied:
            return "Las notificaciones de iAmAwake están desactivadas, así que no vas a enterarte cuando se desarme solo. "
                + "Podés habilitarlas en Ajustes del Sistema › Notificaciones › iAmAwake."
        }
    }

    public static func name(of level: ThermalLevel) -> String {
        switch level {
        case .nominal: return "normal"
        case .fair: return "moderada"
        case .serious: return "alta"
        case .critical: return "crítica"
        }
    }

    private static func shortName(_ error: AwakeError) -> String {
        switch error {
        case .assertionFailed: return "assertionFailed"
        case .helperUnavailable: return "helperUnavailable"
        case .helperRefused: return "helperRefused"
        case .helperVersionMismatch: return "helperVersionMismatch"
        case .hotkeyRegistrationFailed: return "hotkeyRegistrationFailed"
        case .notificationPermissionDenied: return "notificationPermissionDenied"
        }
    }
}
