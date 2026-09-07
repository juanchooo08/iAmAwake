import AppKit
import AwakeCore
import QuartzCore

/// Una cortina.
///
/// Al cerrar la tapa baja desde arriba y tapa la pantalla entera. Al abrirla se
/// levanta, asi que la pantalla se destapa de abajo hacia arriba.
///
/// El texto viaja pegado a la cortina: entra con ella y se va con ella. Por eso
/// es una capa hija y no una vista aparte.
@MainActor
public final class CurtainOverlayController: OverlayPresenting {

    private static let slideDown: CFTimeInterval = 0.45
    private static let slideUp: CFTimeInterval = 0.70
    /// Cuanto se queda la cortina abajo antes de levantarse al abrir la tapa.
    /// Es el unico momento en que el texto se lee de verdad.
    private static let holdBeforeLift: TimeInterval = 1.6
    private static let holdAfterClosing: TimeInterval = 1.2

    private var window: NSWindow?
    private var curtain: CALayer?
    private var headline: CATextLayer?
    private var detail: CATextLayer?
    private var pendingWork: [DispatchWorkItem] = []

    public init() {}

    // MARK: - OverlayPresenting

    public func play(_ transition: LidTransition) {
        guard let copy = OverlayCopy.forTransition(transition) else { return }
        guard let screen = NSScreen.main else { return }

        cancelPending()
        let window = ensureWindow(on: screen)
        layout(in: window, copy: copy, scale: screen.backingScaleFactor)

        switch copy.motion {
        case .closing:
            setCurtain(down: false, animated: false)
            setCurtain(down: true, animated: !reduceMotion, duration: Self.slideDown,
                       timing: CAMediaTimingFunction(name: .easeOut))
            schedule(after: Self.holdAfterClosing) { $0.dismiss() }

        case .opening:
            // La tapa estuvo cerrada: la cortina ya estaba abajo. Se lee el texto
            // y recien despues se levanta.
            setCurtain(down: true, animated: false)
            schedule(after: Self.holdBeforeLift) { controller in
                controller.setCurtain(down: false, animated: !controller.reduceMotion,
                                      duration: Self.slideUp,
                                      timing: CAMediaTimingFunction(name: .easeInEaseOut))
                controller.schedule(after: Self.slideUp) { $0.hideImmediately() }
            }
        }
    }

    public func dismiss() {
        cancelPending()
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

    // MARK: - Privado

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// La cortina ya salio sola de cuadro: esconder la ventana sin desvanecerla,
    /// o se veria un flash gris sobre la pantalla ya destapada.
    private func hideImmediately() {
        cancelPending()
        window?.orderOut(nil)
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

        let curtain = Self.makeCurtain()
        let headline = Self.makeText(size: 36, weight: .semibold, alpha: 0.95)
        let detail = Self.makeText(size: 17, weight: .regular, alpha: 0.6)
        curtain.addSublayer(headline)
        curtain.addSublayer(detail)
        content.layer?.addSublayer(curtain)

        self.curtain = curtain
        self.headline = headline
        self.detail = detail
        self.window = window

        window.alphaValue = 1
        window.orderFrontRegardless()
        return window
    }

    private func layout(in window: NSWindow, copy: OverlayCopy, scale: CGFloat) {
        guard let content = window.contentView, let curtain else { return }
        let size = content.bounds.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        curtain.frame = CGRect(origin: .zero, size: size)
        Self.layoutHem(curtain)

        let center = size.height / 2
        headline?.contentsScale = scale
        detail?.contentsScale = scale
        headline?.string = copy.headline
        detail?.string = copy.detail
        headline?.frame = CGRect(x: 0, y: center - 4, width: size.width, height: 48)
        detail?.frame = CGRect(x: 0, y: center - 40, width: size.width, height: 26)

        CATransaction.commit()
    }

    /// `down == true` significa cortina tapando la pantalla.
    private func setCurtain(
        down: Bool,
        animated: Bool,
        duration: CFTimeInterval = 0,
        timing: CAMediaTimingFunction? = nil
    ) {
        guard let curtain else { return }
        let transform = down
            ? CATransform3DIdentity
            : CATransform3DMakeTranslation(0, curtain.bounds.height, 0)

        // Arrancar desde `presentation()` evita el salto si llega otra transicion
        // con la anterior a mitad de camino.
        let from = curtain.presentation()?.transform ?? curtain.transform
        curtain.removeAnimation(forKey: "slide")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        curtain.transform = transform
        CATransaction.commit()

        guard animated, duration > 0 else { return }
        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = NSValue(caTransform3D: from)
        slide.toValue = NSValue(caTransform3D: transform)
        slide.duration = duration
        slide.timingFunction = timing
        curtain.add(slide, forKey: "slide")
    }

    private func schedule(after seconds: TimeInterval, _ body: @escaping (CurtainOverlayController) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated { body(self) }
        }
        pendingWork.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelPending() {
        for work in pendingWork { work.cancel() }
        pendingWork.removeAll()
    }

    // MARK: - Construccion de capas

    private static func makeCurtain() -> CALayer {
        let curtain = CALayer()
        curtain.backgroundColor = NSColor.black.withAlphaComponent(0.96).cgColor
        curtain.masksToBounds = false
        return curtain
    }

    /// El dobladillo: una linea de luz en el borde de abajo. Es lo que hace que
    /// se lea como una cortina que baja y no como la pantalla apagandose.
    private static func layoutHem(_ curtain: CALayer) {
        let hem = curtain.sublayers?.first(where: { $0.name == "hem" }) as? CAGradientLayer ?? {
            let layer = CAGradientLayer()
            layer.name = "hem"
            layer.colors = [
                NSColor.white.withAlphaComponent(0.30).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor,
            ]
            layer.startPoint = CGPoint(x: 0.5, y: 0)
            layer.endPoint = CGPoint(x: 0.5, y: 1)
            curtain.insertSublayer(layer, at: 0)
            return layer
        }()
        hem.frame = CGRect(x: 0, y: 0, width: curtain.bounds.width, height: 14)
    }

    private static func makeText(size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) -> CATextLayer {
        let text = CATextLayer()
        text.font = NSFont.systemFont(ofSize: size, weight: weight)
        text.fontSize = size
        text.alignmentMode = .center
        text.foregroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
        text.truncationMode = .end
        return text
    }
}
