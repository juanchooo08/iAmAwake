import AppKit

// App de barra de menu: `.accessory` la deja sin icono en el Dock y sin menu de
// ventana. No hay NIB ni storyboard, asi que el ciclo de vida se arma a mano.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let delegate = AppDelegate()
application.delegate = delegate
application.run()
