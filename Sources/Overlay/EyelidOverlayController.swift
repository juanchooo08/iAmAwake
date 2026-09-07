import AppKit
import AwakeCore
import QuartzCore

/// La animacion: dos parpados barren hacia el centro y se frenan antes de
/// tocarse. El ojo queda abierto. Esa es toda la metafora.
///
/// La ventana ignora el mouse y se va sola. Nunca se queda atravesada entre vos
/// y lo que estabas haciendo.
@MainActor
public final class EyelidOverlayController: OverlayPresenting {

    /// Cuanto de la pantalla tapa cada parpado. 0.42 + 0.42 deja una franja del
    /// 16 % en el medio: el ojo abierto.
    private static let lidFraction: CGFloat = 0.42
    private static let holdAfterClosing: TimeInterval = 1.2
    private static let holdAfterOpening: TimeInterval = 2.0

    private var window: NSWindow?
    private var topLid: CALayer?
    private var bottomLid: CALayer?
    private let headline = EyelidOverlayController.makeLabel(size: 34, weight: .semibold, alpha: 0.95)
    private let detail = EyelidOverlayController.makeLabel(size: 16, weight: .regular, alpha: 0.65)
    private var pendingDismiss: DispatchWorkItem?

    public init() {}

    // MARK: - OverlayPresenting

    public func play(_ transition: LidTransition) {
        guard let copy = OverlayCopy.forTransition(transition) else { return }
        guard let screen = NSScreen.main else { return }

        pendingDismiss?.cancel()
        let window = ensureWindow(on: screen)
        layout(in: window, copy: copy)

        switch copy.motion {
        case .closing:
            // Arranca con los parpados fuera de cuadro y los cierra.
            setLids(open: true, animated: false)
            setLids(open: false, animated: !reduceMotion, duration: 0.38,
                    timing: CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1))
            fadeText(to: 1, after: 0.10)
            scheduleDismiss(in: Self.holdAfterClosing)

        case .opening:
            // La tapa estuvo cerrada: los parpados ya estaban abajo. Se retiran.
            setLids(open: false, animated: false)
            fadeText(to: 1, after: 0)
            setLids(open: true, animated: !reduceMotion, duration: 0.55,
                    timing: CAMediaTimingFunction(name: .easeInEaseOut))
            scheduleDismiss(in: Self.holdAfterOpening)
        }
    }

    public func dismiss() {
        pendingDismiss?.cancel()
        pendingDismiss = nil
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.35
            window.animator().alphaValue = 0
        } completionHandler: { [weak window] in
            // El completion de NSAnimationContext corre en main, pero el compilador
            // no lo sabe: sin esto no puede tocar la ventana.
            MainActor.assumeIsolated { window?.orderOut(nil) }
        }
    }

    // MARK: - Ventana

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func ensureWindow(on screen: NSScreen) -> NSWindow {
        if let window {
            window.setFrame(screen.frame, display: false)
            window.alphaValue = 1
            window.orderFrontRegardless()
            return window
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Ignora el mouse: los clicks pasan de largo hacia la app de abajo.
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let content = NSView(frame: screen.frame)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = content

        let top = Self.makeLid(edge: .top)
        let bottom = Self.makeLid(edge: .bottom)
        content.layer?.addSublayer(top)
        content.layer?.addSublayer(bottom)
        topLid = top
        bottomLid = bottom

        content.addSubview(headline)
        content.addSubview(detail)

        self.window = window
        window.alphaValue = 1
        window.orderFrontRegardless()
        return window
    }

    private func layout(in window: NSWindow, copy: OverlayCopy) {
        guard let content = window.contentView else { return }
        let size = content.bounds.size
        let lidHeight = (size.height * Self.lidFraction).rounded()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topLid?.frame = CGRect(x: 0, y: size.height - lidHeight, width: size.width, height: lidHeight)
        bottomLid?.frame = CGRect(x: 0, y: 0, width: size.width, height: lidHeight)
        Self.layoutEdgeGlow(topLid, atTop: false)
        Self.layoutEdgeGlow(bottomLid, atTop: true)
        CATransaction.commit()

        headline.stringValue = copy.headline
        detail.stringValue = copy.detail
        headline.alphaValue = 0
        detail.alphaValue = 0
        headline.sizeToFit()
        detail.sizeToFit()

        let center = size.height / 2
        headline.setFrameOrigin(NSPoint(
            x: ((size.width - headline.frame.width) / 2).rounded(),
            y: (center + 4).rounded()
        ))
        detail.setFrameOrigin(NSPoint(
            x: ((size.width - detail.frame.width) / 2).rounded(),
            y: (center - detail.frame.height - 10).rounded()
        ))
    }

    // MARK: - Animacion

    /// `open == true` significa parpados fuera de cuadro.
    private func setLids(
        open: Bool,
        animated: Bool,
        duration: CFTimeInterval = 0,
        timing: CAMediaTimingFunction? = nil
    ) {
        guard let topLid, let bottomLid else { return }
        let travel = topLid.bounds.height

        let topTransform = open ? CATransform3DMakeTranslation(0, travel, 0) : CATransform3DIdentity
        let bottomTransform = open ? CATransform3DMakeTranslation(0, -travel, 0) : CATransform3DIdentity

        apply(topTransform, to: topLid, animated: animated, duration: duration, timing: timing)
        apply(bottomTransform, to: bottomLid, animated: animated, duration: duration, timing: timing)
    }

    private func apply(
        _ transform: CATransform3D,
        to layer: CALayer,
        animated: Bool,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunction?
    ) {
        // Arrancar desde `presentation()` evita el salto si llega una transicion
        // nueva con la anterior a mitad de camino.
        let from = layer.presentation()?.transform ?? layer.transform
        layer.removeAnimation(forKey: "lid")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()

        guard animated, duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: transform)
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "lid")
    }

    private func fadeText(to alpha: CGFloat, after delay: TimeInterval) {
        guard delay > 0 else { return applyTextAlpha(alpha) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.applyTextAlpha(alpha)
        }
    }

    private func applyTextAlpha(_ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0 : 0.25
            headline.animator().alphaValue = alpha
            detail.animator().alphaValue = alpha * 0.7
        }
    }

    private func scheduleDismiss(in seconds: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        pendingDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Construccion de capas

    private enum Edge { case top, bottom }

    private static func makeLid(edge: Edge) -> CALayer {
        let lid = CALayer()
        lid.backgroundColor = NSColor.black.withAlphaComponent(0.94).cgColor
        lid.masksToBounds = false

        // Filito luminoso en el borde interno: es lo que lo hace leer como parpado
        // y no como una barra negra.
        let glow = CAGradientLayer()
        glow.name = "glow"
        glow.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.28).cgColor,
        ]
        glow.startPoint = CGPoint(x: 0.5, y: edge == .top ? 1 : 0)
        glow.endPoint = CGPoint(x: 0.5, y: edge == .top ? 0 : 1)
        lid.addSublayer(glow)
        return lid
    }

    private static func layoutEdgeGlow(_ lid: CALayer?, atTop: Bool) {
        guard let lid, let glow = lid.sublayers?.first(where: { $0.name == "glow" }) else { return }
        let thickness: CGFloat = 3
        glow.frame = CGRect(
            x: 0,
            y: atTop ? lid.bounds.height - thickness : 0,
            width: lid.bounds.width,
            height: thickness
        )
    }

    private static func makeLabel(size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = NSColor.white.withAlphaComponent(alpha)
        label.alignment = .center
        label.alphaValue = 0
        label.isBezeled = false
        label.drawsBackground = false
        return label
    }
}
