import SwiftUI

/// Porción de círculo que representa el tiempo que **queda**: empieza llena y se va
/// consumiendo, como una tarta a la que le quitan porciones.
///
/// Se lee de un vistazo sin necesidad de leer cifras, que es justo lo que se pide de un
/// indicador en el panel cerrado.
struct PieProgress: Shape {

    /// 1 = círculo completo, 0 = vacío.
    var remaining: Double

    var animatableData: Double {
        get { remaining }
        set { remaining = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let value = min(max(remaining, 0), 1)

        guard value > 0 else { return path }

        // El caso completo se dibuja como elipse: un arco de 360° deja una costura
        // visible en el punto de cierre.
        guard value < 1 else {
            path.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            return path
        }

        // Arranca arriba y consume en sentido horario, como un reloj.
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * value),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }
}

/// El indicador completo: aro tenue de fondo con la porción restante encima.
struct PomodoroPie: View {

    let remaining: Double
    let tint: Color
    var size: CGFloat = 17

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Fill.hover, lineWidth: 1.5)

            PieProgress(remaining: remaining)
                .fill(tint)
                // El margen evita que la porción toque el aro y se vea emborronada.
                .padding(2.5)
        }
        .frame(width: size, height: size)
    }
}
