import AppKit
import AwakeCore
import Overlay

// App de barra de menu: `.accessory` la deja sin icono en el Dock y sin menu de
// ventana. No hay NIB ni storyboard, asi que el ciclo de vida se arma a mano.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

// `--demo-overlay [closing|opening]` dibuja la animacion y sale.
//
// Existe porque la animacion de cierre es casi imposible de ver en su momento
// real: el backlight se apaga a los ~0.2 s de que el sistema detecta la tapa.
// Sin esto, la unica forma de mirarla seria cerrar la tapa y confiar.
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
