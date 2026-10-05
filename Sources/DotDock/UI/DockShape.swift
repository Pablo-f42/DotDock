import SwiftUI

/// La silueta del panel: esquinas superiores **cóncavas** (se funden con la barra de
/// menús) y esquinas inferiores convexas.
///
/// Las curvas superiores se dibujan *fuera* del rect, así que la vista que la use
/// necesita margen horizontal o quedarán recortadas.
struct DockShape: Shape {

    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// Permite que SwiftUI interpole los radios durante la animación de apertura.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = max(0, topRadius)
        let bottom = max(0, min(bottomRadius, rect.height / 2, rect.width / 2))

        // Arranca a la izquierda del rect, al ras del borde superior de la pantalla.
        path.move(to: CGPoint(x: rect.minX - top, y: rect.minY))

        // Esquina superior izquierda, cóncava.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + top),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))

        // Esquina inferior izquierda, convexa.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - bottom, y: rect.maxY))

        // Esquina inferior derecha, convexa.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))

        // Esquina superior derecha, cóncava.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX + top, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
