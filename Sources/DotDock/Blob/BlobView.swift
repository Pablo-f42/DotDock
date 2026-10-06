import SwiftUI

/// La gotita colgando del borde inferior de la muesca. La vista que la contenga debe
/// alinear su borde superior con el inferior de la muesca.
struct BlobView: View {

    @ObservedObject var blob: BlobModel
    @ObservedObject var settings: AppSettings
    @ObservedObject private var design = BlobDesign.shared

    var body: some View {
        let shape = design.proportions

        if blob.isPresent {
            ZStack(alignment: .top) {
                DropletShape(reach: blob.reach, lean: blob.lean, proportions: shape).fill(.black)

                eyes(shape)
                    .frame(width: shape.frameWidth, height: frameHeight(shape), alignment: .top)
                    // Los ojos nunca se dibujan fuera del cuerpo: mientras la gota es
                    // un bulto, o al recogerse, quedarían colgando debajo de ella.
                    .mask(DropletShape(reach: blob.reach, lean: blob.lean, proportions: shape))

                if blob.mood == .music {
                    Image(systemName: "music.note")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .modifier(FloatingNote(
                            progress: blob.noteProgress,
                            side: blob.noteSide,
                            start: CGPoint(x: shape.bodyWidth / 2 + 4, y: shape.height * 0.4)
                        ))
                }
            }
            .frame(width: shape.frameWidth, height: frameHeight(shape), alignment: .top)
            .offset(x: blob.offsetX)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Margen bajo la altura nominal para el rebote del resorte.
    private func frameHeight(_ shape: BlobProportions) -> CGFloat {
        shape.height * 1.4
    }

    private func eyes(_ shape: BlobProportions) -> some View {
        let travel = BlobMetrics.gazeTravel

        return HStack(spacing: shape.eyeSpacing) {
            BlobEye(
                mood: blob.mood,
                openness: blob.isWinking ? 0 : blob.eyeOpenness,
                size: shape.eyeSize,
                color: settings.blobEyeColor.color,
                isLeft: true
            )
            BlobEye(
                mood: blob.mood,
                openness: blob.eyeOpenness,
                size: shape.eyeSize,
                color: settings.blobEyeColor.color,
                isLeft: false
            )
        }
        .offset(
            x: blob.gaze.width * travel.width
                + DropletShape.leanShift(blob.lean, proportions: shape) * 0.5,
            y: DropletShape.eyeCenterY(reach: blob.reach, proportions: shape)
                - shape.eyeHeight / 2
                + blob.gaze.height * travel.height
        )
    }
}

/// Ojo simple: un óvalo blanco que se recorta desde arriba para parpadear o dar
/// expresión.
///
/// Se recorta con una máscara y no tapándolo con un párpado negro encima: el borde
/// suavizado del óvalo asomaba por fuera del párpado como un anillo gris.
private struct BlobEye: View {

    let mood: BlobMood
    let openness: CGFloat
    let size: CGSize
    let color: Color
    let isLeft: Bool

    var body: some View {
        if mood == .happy || mood == .music {
            // ^ ^ de alegría; ‿ ‿ de gusto, cerrados, al bailar.
            HappyArc()
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                // El alto sale del ancho y no del alto del ojo: con ojos angostos
                // el arco quedaba como una "v".
                .frame(width: size.width + 2, height: min(size.height * 0.55, (size.width + 2) * 0.45))
                .scaleEffect(x: 1, y: mood == .music ? -1 : 1)
                .scaleEffect(x: 1, y: max(openness, 0.01), anchor: .bottom)
                .opacity(openness > 0.05 ? 1 : 0)
                .frame(width: size.width, height: size.height)
        } else {
            Capsule()
                .fill(color)
                .frame(width: size.width, height: size.height)
                .mask(alignment: .top) { visibleArea }
                .scaleEffect(scale)
                .opacity(openness > 0.02 ? 1 : 0)
        }
    }

    /// Abiertos de par en par al asustarse; un poco más grandes al saludar.
    private var scale: CGFloat {
        switch mood {
        case .startled: 1.3
        case .hello: 1.12
        default: 1
        }
    }

    /// La parte del ojo que queda bajo el párpado. Inclinado hacia fuera da cara de
    /// preocupación; a media altura, de sueño.
    private var visibleArea: some View {
        let angle: Double = mood == .worried ? (isLeft ? -22 : 22) : 0
        let covered = size.height * (1 - min(max(openness, 0), 1))

        return Rectangle()
            .frame(width: size.width * 3, height: size.height * 2)
            .rotationEffect(.degrees(angle), anchor: .top)
            .offset(y: covered)
    }
}

/// Una nota que sale de un costado, sube un poco y se desvanece. Va como modificador
/// animable porque la opacidad sube y vuelve a bajar: interpolar sólo el valor final
/// no la haría aparecer nunca.
private struct FloatingNote: ViewModifier, Animatable {

    var progress: CGFloat
    let side: CGFloat
    let start: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let opacity = p < 0.15 ? p / 0.15 : (1 - p) / 0.85

        content
            .rotationEffect(.degrees(Double(side) * 12 * Double(p)))
            .offset(x: side * (start.x + 8 * p), y: start.y - 6 * p)
            .opacity(Double(opacity))
    }
}

private struct HappyArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6)
        )
        return path
    }
}

/// Silueta de gota: filetes cóncavos que salen del borde de la muesca y un fondo de
/// media elipse. Con `reach` en 0 es una línea; al crecer, primero es un bulto y
/// luego una gota.
struct DropletShape: Shape {

    var reach: CGFloat
    var lean: CGFloat = 0
    var proportions: BlobProportions

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(reach, lean) }
        set {
            reach = newValue.first
            lean = newValue.second
        }
    }

    /// Cuánto se corre la panza al balancearse.
    static func leanShift(_ lean: CGFloat, proportions: BlobProportions) -> CGFloat {
        lean * proportions.bodyWidth * 0.09
    }

    /// Alto del cuello: donde terminan los filetes y empieza el cuerpo.
    private static func neck(reach: CGFloat, proportions: BlobProportions) -> CGFloat {
        let p = max(reach, 0)
        return min(proportions.fillet * min(p, 1), proportions.height * p * 0.45)
    }

    /// Centro vertical de los ojos dentro del cuerpo.
    static func eyeCenterY(reach: CGFloat, proportions: BlobProportions) -> CGFloat {
        let neck = neck(reach: reach, proportions: proportions)
        let body = max(proportions.height * max(reach, 0) - neck, 0)
        return neck + body * proportions.eyeLevel
    }

    func path(in rect: CGRect) -> Path {
        let p = max(reach, 0)
        let fillet = proportions.fillet * min(p, 1)
        let neck = Self.neck(reach: reach, proportions: proportions)
        let radiusY = max(proportions.height * p - neck, 0)
        let radiusX = proportions.bodyWidth / 2

        let top = rect.minY
        let midX = rect.midX
        let left = midX - radiusX
        let right = midX + radiusX
        let waist = top + neck
        // El fondo se corre con el balanceo; los costados y los filetes no se mueven,
        // así que la unión con la muesca sigue intacta.
        let bottomX = midX + Self.leanShift(lean, proportions: proportions)

        // Aproximación de un cuarto de elipse con una cúbica.
        let k: CGFloat = 0.5523

        var path = Path()
        path.move(to: CGPoint(x: left - fillet, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: waist), control: CGPoint(x: left, y: top))
        path.addCurve(
            to: CGPoint(x: bottomX, y: waist + radiusY),
            control1: CGPoint(x: left, y: waist + radiusY * k),
            control2: CGPoint(x: bottomX - radiusX * k, y: waist + radiusY)
        )
        path.addCurve(
            to: CGPoint(x: right, y: waist),
            control1: CGPoint(x: bottomX + radiusX * k, y: waist + radiusY),
            control2: CGPoint(x: right, y: waist + radiusY * k)
        )
        path.addQuadCurve(to: CGPoint(x: right + fillet, y: top), control: CGPoint(x: right, y: top))

        // Sube un punto por dentro de la muesca para que no quede una rendija en la unión.
        path.addLine(to: CGPoint(x: right + fillet, y: top - 1))
        path.addLine(to: CGPoint(x: left - fillet, y: top - 1))
        path.closeSubpath()

        return path
    }
}
