// Genera Resources/AppIcon.icns.
//
// El icono se dibuja por codigo y no se guarda como fuente aparte para que sea
// reproducible: no hay un .sketch ni un .psd que se pierda. Correr:
//     swift Scripts/make-icon.swift
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let oneX: Set<Int> = [16, 32, 128, 256, 512]
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// Un ojo abierto sobre fondo de noche: la app se llama iAmAwake y el simbolo
/// tiene que leerse a 16 px, donde cualquier detalle desaparece.
func draw(_ s: CGFloat, into ctx: CGContext) {
    // Fondo: rectangulo redondeado a sangre, como cualquier icono de macOS.
    let radius = s * 0.2237
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                    cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg)
    ctx.clip()

    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.16, green: 0.18, blue: 0.36, alpha: 1),
        CGColor(red: 0.04, green: 0.05, blue: 0.11, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: 0, y: 0), options: [])

    // Ojo: dos arcos simetricos. El ancho manda; la altura da la almendra.
    let cx = s * 0.5, cy = s * 0.5
    let w = s * 0.60, h = s * 0.34
    let eye = CGMutablePath()
    eye.move(to: CGPoint(x: cx - w / 2, y: cy))
    eye.addQuadCurve(to: CGPoint(x: cx + w / 2, y: cy),
                     control: CGPoint(x: cx, y: cy + h))
    eye.addQuadCurve(to: CGPoint(x: cx - w / 2, y: cy),
                     control: CGPoint(x: cx, y: cy - h))

    ctx.addPath(eye)
    ctx.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 1, alpha: 1))
    ctx.fillPath()

    // Iris ambar: da el unico acento de color y marca que esta despierto.
    ctx.saveGState()
    ctx.addPath(eye)
    ctx.clip()
    let iris = s * 0.130
    ctx.setFillColor(CGColor(red: 1, green: 0.76, blue: 0.30, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - iris, y: cy - iris, width: iris * 2, height: iris * 2))
    let pupil = s * 0.062
    ctx.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.12, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: cx - pupil, y: cy - pupil, width: pupil * 2, height: pupil * 2))
    ctx.restoreGState()

    ctx.restoreGState()
}

for size in sizes {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    draw(s, into: ctx)

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let png = rep.representation(using: .png, properties: [:])!

    // Cada tamano vive dos veces: como 1x y como el @2x del que mide la mitad.
    // 64 solo existe como 32@2x: `icon_64x64.png` no es un nombre que iconutil
    // reconozca y ensucia el iconset.
    if oneX.contains(size) {
        try png.write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    }
    let half = size / 2
    if oneX.contains(half) {
        try png.write(to: out.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
    }
}
print("iconset en \(out.path)")
