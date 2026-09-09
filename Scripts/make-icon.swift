// Genera Resources/AppIcon.icns a partir de Resources/icon-source.png.
//
// La fuente la dibujo un modelo de imagenes; lo que hace este script es todo lo
// que el modelo no sabe hacer: recortar para que el simbolo llene el cuadro
// (si no, a 16 px es un punto), escalar a cada tamano y aplicar la esquina
// redondeada de macOS. Correr:
//     swift Scripts/make-icon.swift
import AppKit

let pkg = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = pkg.appendingPathComponent("Resources/icon-source.png")
let out = pkg.appendingPathComponent("Resources/AppIcon.iconset")

guard let src = NSImage(contentsOf: source),
      let srcCG = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("no pude leer \(source.path)\n".utf8))
    exit(1)
}
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// Cuanto del original se conserva. El modelo deja mucho aire alrededor y los
/// iconos de macOS quieren el simbolo casi a sangre.
let keep: CGFloat = 0.74

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let oneX: Set<Int> = [16, 32, 128, 256, 512]

for size in sizes {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high

    // Esquina redondeada a sangre, como cualquier icono de macOS.
    let radius = s * 0.2237
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // Recorte centrado del original, estirado a todo el lienzo.
    let w = CGFloat(srcCG.width), h = CGFloat(srcCG.height)
    let side = min(w, h) * keep
    let crop = CGRect(x: (w - side) / 2, y: (h - side) / 2, width: side, height: side)
    if let cropped = srcCG.cropping(to: crop) {
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: s, height: s))
    }

    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        .representation(using: .png, properties: [:])!
    if oneX.contains(size) {
        try png.write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    }
    let half = size / 2
    if oneX.contains(half) {
        try png.write(to: out.appendingPathComponent("icon_\(half)x\(half)@2x.png"))
    }
}
print("iconset en \(out.path)")
