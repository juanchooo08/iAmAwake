import AppKit
import AwakeCore
import QuartzCore

/// Implementacion de `StatusPresenting` sobre `NSStatusItem`.
///
/// No conoce `PowerState` ni ninguna otra implementacion: su unica salida son
/// los tres closures (`onToggle`, `onOpenPreferences`, `onQuit`).
@MainActor
public final class StatusItemController: NSObject, StatusPresenting {
    public var onToggle: (() -> Void)?
    public var onOpenPreferences: (() -> Void)?
    public var onQuit: (() -> Void)?

    private let statusBar: NSStatusBar
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let toggleItem = NSMenuItem()
    private let statusLineItem = NSMenuItem()

    /// Ultima presentacion renderizada. Expuesta para inspeccion y debugging.
    public private(set) var presentation: StatusPresentation

    public init(statusBar: NSStatusBar = .system) {
        self.statusBar = statusBar
        self.statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.presentation = StatusPresentation(state: .disarmed)
        super.init()
        buildMenu()
        apply(presentation)
    }

    // MARK: - StatusPresenting

    public func render(_ state: ArmState) {
        apply(StatusPresentation(state: state))
    }

    // MARK: - Privado

    private func buildMenu() {
        // Sin auto-enable: la linea de estado tiene que quedarse deshabilitada.
        menu.autoenablesItems = false

        toggleItem.target = self
        toggleItem.action = #selector(handleToggle)
        toggleItem.isEnabled = true
        menu.addItem(toggleItem)

        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)

        menu.addItem(.separator())

        let prefsItem = NSMenuItem(
            title: "Preferencias…",
            action: #selector(handleOpenPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        prefsItem.isEnabled = true
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Salir", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func apply(_ next: StatusPresentation) {
        presentation = next

        let image = NSImage(
            systemSymbolName: next.symbolName,
            accessibilityDescription: next.accessibilityDescription
        )
        image?.isTemplate = true

        if let button = statusItem.button {
            button.image = image
            button.toolTip = next.tooltip
            button.setAccessibilityLabel(next.accessibilityDescription)
        }

        toggleItem.title = next.toggleTitle
        statusLineItem.title = next.statusLine
        syncPulse(next.pulses)
    }

    /// Latido lento del icono mientras esta armado. Es el unico feedback que se
    /// ve sin cerrar la tapa ni abrir el menu.
    private func syncPulse(_ pulses: Bool) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        layer.removeAnimation(forKey: "pulse")
        // Respeta "Reducir movimiento" del sistema: ahi el icono se queda quieto.
        guard pulses, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: "pulse")
    }

    @objc private func handleToggle() { onToggle?() }
    @objc private func handleOpenPreferences() { onOpenPreferences?() }
    @objc private func handleQuit() { onQuit?() }
}
