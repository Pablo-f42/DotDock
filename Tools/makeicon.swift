// Genera Resources/AppIcon.icns: la barra superior con la gotita asomándose.
//
// Se ejecuta con `make icon`. El resultado se versiona, así que un build normal no
// necesita volver a generarlo.

import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// La silueta de la gotita, la misma que dibuja la app (`DropletShape`): filetes
/// cóncavos que salen del borde de la barra y un fondo de media elipse. Coordenadas
/// con la Y hacia abajo.
func dropletPath(top: CGFloat, midX: CGFloat, width: CGFloat, height: CGFloat, fillet: CGFloat) -> CGPath {
    let neck = min(fillet, height * 0.45)
    let radiusX = width / 2
    let radiusY = height - neck
    let left = midX - radiusX
    let right = midX + radiusX
    let waist = top + neck
    let k: CGFloat = 0.5523

    let path = CGMutablePath()
    path.move(to: CGPoint(x: left - fillet, y: top))
    path.addQuadCurve(to: CGPoint(x: left, y: waist), control: CGPoint(x: left, y: top))
    path.addCurve(
        to: CGPoint(x: midX, y: waist + radiusY),
        control1: CGPoint(x: left, y: waist + radiusY * k),
        control2: CGPoint(x: midX - radiusX * k, y: waist + radiusY)
    )
    path.addCurve(
        to: CGPoint(x: right, y: waist),
        control1: CGPoint(x: midX + radiusX * k, y: waist + radiusY),
        control2: CGPoint(x: right, y: waist + radiusY * k)
    )
    path.addQuadCurve(to: CGPoint(x: right + fillet, y: top), control: CGPoint(x: right, y: top))
    // Se mete un poco en la barra para que no quede rendija en la unión.
    path.addLine(to: CGPoint(x: right + fillet, y: top - 1))
    path.addLine(to: CGPoint(x: left - fillet, y: top - 1))
    path.closeSubpath()
    return path
}

func render(pixels: Int) -> Data? {
    let size = CGFloat(pixels)
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Y hacia abajo, como en SwiftUI: así las medidas se leen igual que en la app.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    // Placa: squircle con un degradado azul. macOS no recorta el icono por nosotros,
    // así que la forma la damos aquí.
    let inset = size * 0.055
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let platePath = CGPath(
        roundedRect: plate,
        cornerWidth: size * 0.22,
        cornerHeight: size * 0.22,
        transform: nil
    )

    context.saveGState()
    context.addPath(platePath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0.47, green: 0.68, blue: 1.00, alpha: 1),
            CGColor(srgbRed: 0.16, green: 0.29, blue: 0.93, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.midX, y: plate.minY),
        end: CGPoint(x: plate.midX, y: plate.maxY),
        options: []
    )

    // La barra superior, de lado a lado de la placa.
    let barHeight = size * 0.18
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: barHeight))

    // La gotita, con las proporciones que se eligieron para la app
    // (ancho 42, alto 27, unión 16) escaladas al icono.
    let unit = size * 0.0085
    let blobTop = plate.minY + barHeight
    let blobWidth = 42 * unit
    let blobHeight = 27 * unit
    context.addPath(dropletPath(
        top: blobTop,
        midX: plate.midX,
        width: blobWidth,
        height: blobHeight,
        fillet: 16 * unit
    ))
    context.fillPath()

    // Ojos: óvalos blancos (4 × 9,5, separados 8,5), a la altura que se eligió.
    // Por debajo de cierto tamaño se engordan para que no desaparezcan.
    let eyeWidth = max(4 * unit, 1.2)
    let eyeHeight = max(9.5 * unit, 2.2)
    let spacing = 8.5 * unit
    let neck = min(16 * unit, blobHeight * 0.45)
    let eyeCenterY = blobTop + neck + (blobHeight - neck) * 0.15
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    for side in [-1.0, 1.0] {
        let centerX = plate.midX + CGFloat(side) * (spacing / 2 + eyeWidth / 2)
        context.fillEllipse(in: CGRect(
            x: centerX - eyeWidth / 2,
            y: eyeCenterY - eyeHeight / 2,
            width: eyeWidth,
            height: eyeHeight
        ))
    }

    context.restoreGState()

    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

// Los tamaños que espera iconutil.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for variant in variants {
    guard let data = render(pixels: variant.pixels) else {
        FileHandle.standardError.write("no se pudo renderizar \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

print("iconset generado en \(iconset.path)")
