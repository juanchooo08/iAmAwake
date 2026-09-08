import AppKit
import AwakeCore
import Notifier
import Overlay
import UserNotifications

// App de barra de menu: `.accessory` la deja sin icono en el Dock y sin menu de
// ventana. No hay NIB ni storyboard, asi que el ciclo de vida se arma a mano.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// `--demo-overlay [closing|opening]` dibuja la animacion y sale.
//
// Existe porque la animacion de cierre es casi imposible de ver en su momento
// real: el backlight se apaga a los ~0.2 s de que el sistema detecta la tapa.
// Sin esto, la unica forma de mirarla seria cerrar la tapa y confiar.
// `--check-notifications` diagnostica el permiso: dice el bundle id, que contesta
// el sistema al pedir autorizacion, en que estado quedo, y manda una de prueba.
let diagnosticaNotificaciones = CommandLine.arguments.contains("--check-notifications")

if let index = CommandLine.arguments.firstIndex(of: "--demo-overlay") {
    let which = CommandLine.arguments.indices.contains(index + 1)
        ? CommandLine.arguments[index + 1]
        : "opening"

    let demo = DemoDelegate(
        transition: which == "closing"
            ? LidTransition(to: .closed, wasArmed: true)
            : LidTransition(to: .open, wasArmed: true, closedFor: 47 * 60)
    )
    application.delegate = demo
    application.run()
} else if diagnosticaNotificaciones {
    let diag = NotificationDiagnosticDelegate()
    application.delegate = diag
    application.run()
} else {
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}

@MainActor
final class DemoDelegate: NSObject, NSApplicationDelegate {
    private let overlay = CurtainOverlayController()
    private let transition: LidTransition

    init(transition: LidTransition) {
        self.transition = transition
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        overlay.play(transition)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            NSApp.terminate(nil)
        }
    }
}


/// Diagnostico de notificaciones.
///
/// Corre dentro de `applicationDidFinishLaunching` a proposito. Pedido desde el
/// codigo de nivel superior de `main.swift` se cuelga para siempre: ahi el hilo
/// principal esta ejecutando el executor de concurrencia, no el run loop de
/// AppKit, y la respuesta del sistema de notificaciones nunca se entrega.
/// Junta las lineas del diagnostico desde los callbacks del sistema, que llegan
/// en hilos arbitrarios.
private final class DiagnosticLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n") + "\n"
    }
}

@MainActor
final class NotificationDiagnosticDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let salida = DiagnosticLines()
        salida.append("bundle id      : \(Bundle.main.bundleIdentifier ?? "NINGUNO")")
        salida.append("bundle path    : \(Bundle.main.bundlePath)")

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            salida.append("requestAuth    : concedido = \(granted)"
                + (error.map { " error = \($0.localizedDescription)" } ?? ""))
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                salida.append("estado final   : \(settings.authorizationStatus.rawValue) (2 = autorizado, 1 = denegado, 0 = sin decidir)")
                salida.append("alertas        : \(settings.alertSetting.rawValue) (2 = habilitadas)")

                let content = UNMutableNotificationContent()
                content.title = "iAmAwake"
                content.body = "Notificacion de prueba."
                let request = UNNotificationRequest(identifier: "diag", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request) { error in
                    salida.append("envio de prueba: "
                        + (error.map { "FALLO -> \($0.localizedDescription)" } ?? "entregado al sistema"))
                    let texto = salida.text
                    FileHandle.standardError.write(Data(texto.utf8))
                    try? texto.write(toFile: "/tmp/iamawake-notificaciones.txt", atomically: true, encoding: .utf8)
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                }
            }
        }
    }
}
