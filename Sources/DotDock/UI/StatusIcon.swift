import AppKit

/// Icono de la barra de menús: una barra con la gotita colgando, y los ojos huecos.
///
/// Es una imagen plantilla, así que macOS la tiñe de blanco o negro según el modo y
/// el fondo. Se dibuja con la misma silueta que la gotita de la app.
enum StatusIcon {

    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let barTop: CGFloat = 2
            let barHeight: CGFloat = 3.5
            context.setFillColor(.black)
            context.fill(CGRect(x: 1, y: barTop, width: rect.width - 2, height: barHeight))

            var shape = BlobProportions()
            shape.bodyWidth = 9
            shape.height = 8.5
            shape.fillet = 3.5
            shape.eyeLevel = 0.35

            let blobTop = barTop + barHeight
            let blobRect = CGRect(x: 0, y: blobTop, width: rect.width, height: shape.height)
            context.addPath(DropletShape(reach: 1, proportions: shape).path(in: blobRect).cgPath)
            context.fillPath()

            // Los ojos se recortan: en una plantilla, lo transparente es lo que se ve
            // del color del fondo.
            context.setBlendMode(.clear)
            let eye = CGSize(width: 1.6, height: 2.8)
            let spacing: CGFloat = 2.2
            let eyeCenterY = blobTop + DropletShape.eyeCenterY(reach: 1, proportions: shape)

            for side: CGFloat in [-1, 1] {
                let centerX = rect.midX + side * (spacing + eye.width) / 2
                context.fillEllipse(in: CGRect(
                    x: centerX - eye.width / 2,
                    y: eyeCenterY - eye.height / 2,
                    width: eye.width,
                    height: eye.height
                ))
            }

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "DotDock"
        return image
    }
}
