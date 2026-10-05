import AppKit
import SwiftUI

/// Proporciones de la gotita, en puntos.
struct BlobProportions: Codable, Equatable {
    var bodyWidth: CGFloat = 42
    var height: CGFloat = 27

    /// Radio de los filetes cóncavos que la unen al borde de la muesca. Son los que la
    /// hacen parecer del mismo material y no una pieza pegada debajo.
    var fillet: CGFloat = 16

    var eyeWidth: CGFloat = 4
    var eyeHeight: CGFloat = 9.5
    var eyeSpacing: CGFloat = 8.5

    /// Altura de los ojos dentro del cuerpo: 0 arriba, 1 abajo.
    var eyeLevel: CGFloat = 0.15

    var frameWidth: CGFloat { bodyWidth + fillet * 2 }
    var eyeSize: CGSize { CGSize(width: eyeWidth, height: eyeHeight) }
}

/// Proporciones vigentes, editables en vivo desde el panel provisional de diseño.
final class BlobDesign: ObservableObject {

    static let shared = BlobDesign()

    private static let key = "blob.proportions"

    @Published var proportions: BlobProportions {
        didSet {
            guard let data = try? JSONEncoder().encode(proportions) else { return }
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        proportions = data.flatMap { try? JSONDecoder().decode(BlobProportions.self, from: $0) }
            ?? BlobProportions()
    }
}

// MARK: - Panel provisional

/// Ventana con deslizadores para afinar la gotita mirándola en pantalla. Es una
/// herramienta de diseño, no un ajuste para siempre: cuando las medidas estén
/// decididas se pasan a los valores por defecto de `BlobProportions`.
@MainActor
final class BlobDesignWindow {

    private var window: NSPanel?

    func show(blob: BlobModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 360, height: 500),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Diseñar gotita"
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: BlobDesignView(design: .shared, blob: blob))
        panel.center()

        // Al cerrar el panel la gotita vuelve a lo suyo.
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { blob.setDesignHold(false) }
        }

        window = panel
        blob.setDesignHold(true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct BlobDesignView: View {

    @ObservedObject var design: BlobDesign
    let blob: BlobModel

    @State private var mood: BlobMood = .normal
    @State private var copied = false

    var body: some View {
        Form {
            Section("Cuerpo") {
                slider("Ancho", \.bodyWidth, 16...70)
                slider("Alto", \.height, 10...44)
                slider("Unión con la muesca", \.fillet, 0...16)
            }

            Section("Ojos") {
                slider("Ancho", \.eyeWidth, 2...12, step: 0.5)
                slider("Alto", \.eyeHeight, 2...16, step: 0.5)
                slider("Separación", \.eyeSpacing, 0...24, step: 0.5)
                slider("Altura", \.eyeLevel, 0.1...0.9, step: 0.05)

                Picker("Ánimo", selection: $mood) {
                    Text("Normal").tag(BlobMood.normal)
                    Text("Feliz").tag(BlobMood.happy)
                    Text("Dormida").tag(BlobMood.sleepy)
                    Text("Preocupada").tag(BlobMood.worried)
                    Text("Música").tag(BlobMood.music)
                }
                .onChange(of: mood) { _, mood in blob.preview(mood: mood) }
            }

            Section {
                HStack {
                    Button("Repetir salida") { blob.replayForDesign(mood: mood) }
                    Spacer()
                    Button("Restablecer") { design.proportions = BlobProportions() }
                    Button(copied ? "Copiado" : "Copiar") { copyValues() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 500)
    }

    private func slider(
        _ title: String,
        _ keyPath: WritableKeyPath<BlobProportions, CGFloat>,
        _ range: ClosedRange<CGFloat>,
        step: CGFloat = 1
    ) -> some View {
        let value = design.proportions[keyPath: keyPath]

        return LabeledContent {
            HStack {
                Slider(
                    // Se redondea a mano en vez de pasar `step`: con paso, el
                    // deslizador dibuja una marca por valor y se llena de puntos.
                    value: Binding(
                        get: { design.proportions[keyPath: keyPath] },
                        set: { design.proportions[keyPath: keyPath] = ($0 / step).rounded() * step }
                    ),
                    in: range
                )
                Text(Double(value).formatted(.number.precision(.fractionLength(0...2))))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }

    /// Las medidas en texto, listas para pegarlas en el chat o en el código.
    private func copyValues() {
        let p = design.proportions
        let text = """
        bodyWidth: \(p.bodyWidth), height: \(p.height), fillet: \(p.fillet), \
        eyeWidth: \(p.eyeWidth), eyeHeight: \(p.eyeHeight), eyeSpacing: \(p.eyeSpacing), \
        eyeLevel: \(p.eyeLevel)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }
}
