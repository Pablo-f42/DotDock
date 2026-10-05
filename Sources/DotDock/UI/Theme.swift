import SwiftUI

/// Tokens visuales compartidos.
///
/// Todo el panel se dibuja sobre negro puro — obligatorio para fundirse con la muesca de
/// hardware — así que la jerarquía se construye únicamente con opacidades de blanco.
/// Tenerlas aquí y no repartidas por las vistas es lo que evita que cada módulo acabe
/// con su propio gris ligeramente distinto.
enum Theme {

    enum Ink {
        static let primary = Color.white.opacity(0.94)
        static let secondary = Color.white.opacity(0.58)
        static let tertiary = Color.white.opacity(0.34)
        static let faint = Color.white.opacity(0.20)
    }

    enum Fill {
        static let raised = Color.white.opacity(0.06)
        static let hover = Color.white.opacity(0.11)
        static let selected = Color.white.opacity(0.16)
    }

    enum Line {
        static let hairline = Color.white.opacity(0.09)
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 9
        static let large: CGFloat = 13
    }

    enum Typo {
        static let title = Font.system(size: 11.5, weight: .semibold)
        static let body = Font.system(size: 11)
        static let caption = Font.system(size: 9.5)

        /// Cifras grandes: redondeada y con ancho fijo para que no bailen al contar.
        static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }
    }
}

/// Encabezado común a todos los módulos, para que el ojo encuentre siempre el mismo
/// ancla al cambiar de herramienta.
struct SectionHeader<Trailing: View>: View {

    let title: String
    let symbol: String
    var hint: String?

    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Ink.secondary)

            Text(title)
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.Ink.primary)

            if let hint {
                Text(hint)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, symbol: String, hint: String? = nil) {
        self.init(title: title, symbol: symbol, hint: hint) { EmptyView() }
    }
}

/// Botón de icono con estado hover, usado en todos los módulos.
struct IconButton: View {

    let symbol: String
    var size: CGFloat = 11
    var help: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isHovering ? Theme.Ink.primary : Theme.Ink.secondary)
                .frame(width: size + 15, height: size + 15)
                .background(
                    Circle().fill(isHovering ? Theme.Fill.hover : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help ?? "")
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
