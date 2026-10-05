import SwiftUI

/// Selector de módulos, al pie del panel.
///
/// Vivía arriba a la izquierda, flanqueando la muesca, pero ahí quedaba escondido y
/// además fijaba un suelo de 453 pt al ancho del panel: la muesca va centrada, así que
/// cada punto de esa franja costaba el doble. Abajo no compite con nada.
struct ModuleSwitcher: View {

    let selection: DockModule
    let onSelect: (DockModule) -> Void

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 5) {
            ForEach(DockModule.allCases) { module in
                ModuleTab(
                    module: module,
                    isSelected: module == selection,
                    indicator: indicator,
                    action: { onSelect(module) }
                )
            }
        }
    }
}

private struct ModuleTab: View {

    let module: DockModule
    let isSelected: Bool
    let indicator: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    /// Ancho natural de la etiqueta, medido una vez.
    @State private var labelWidth: CGFloat = 0

    private var height: CGFloat { 28 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: isSelected ? 6 : 0) {
                Image(systemName: module.symbol)
                    .font(.system(size: 11, weight: .semibold))

                // Sólo el activo se identifica con texto; el resto son círculos.
                //
                // La etiqueta está siempre y lo que cambia es su ancho. Si se quitara
                // y pusiera, la barra perdería un ancho de golpe antes de ganar el
                // otro, y todos los iconos darían un brinco al cambiar de módulo.
                //
                // No se recorta: el recorte y el texto se animaban por separado y se
                // veía cortado del lado equivocado. En su lugar se encoge hacia la
                // izquierda mientras se desvanece, todo como efecto de dibujo.
                Text(module.shortTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .fixedSize()
                    .background(
                        GeometryReader { proxy in
                            Color.clear.onAppear { labelWidth = proxy.size.width }
                        }
                    )
                    .scaleEffect(x: isSelected ? 1 : 0.3, anchor: .leading)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: isSelected ? labelWidth : 0, alignment: .leading)
            }
            .foregroundStyle(isSelected ? .black : Theme.Ink.secondary)
            .padding(.horizontal, isSelected ? 12 : 0)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Theme.Ink.primary)
                        .matchedGeometryEffect(id: "activeTab", in: indicator)
                } else {
                    Circle()
                        .fill(isHovering ? Theme.Fill.hover : Theme.Fill.raised)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(module.title)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
