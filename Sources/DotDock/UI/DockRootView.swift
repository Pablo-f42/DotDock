import SwiftUI

/// Transporta el ancho medido de la barra de pestañas hasta el modelo.
private struct TabBarWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Transporta el ancho medido del módulo visible hasta el modelo.
private struct ContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

struct DockRootView: View {

    @ObservedObject var model: DockModel

    private var shape: DockShape {
        DockShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius)
    }

    var body: some View {
        let size = model.contentSize

        VStack(spacing: 0) {
            shape
                // Negro puro y sin filo: un borde claro, aunque tenue, delataba el
                // contorno de la muesca sobre fondos oscuros.
                .fill(.black)
                .overlay(alignment: .top) { content }
                .frame(width: size.width, height: size.height)
                // Cuelga del borde inferior: su tope se alinea con el fondo de la muesca.
                .overlay(alignment: .bottom) {
                    BlobView(blob: model.blob)
                        .alignmentGuide(.bottom) { $0[.top] }
                }
                .shadow(color: .black.opacity(model.state == .open ? 0.5 : 0), radius: 20, y: 10)
                .contentShape(shape)
                .onTapGesture {
                    // Abrir sí, cerrar no: si el toque cerrara también, fallar un botón
                    // por unos píxeles cerraría el panel.
                    if model.state != .open { model.open() }
                }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        if model.state == .open {
            VStack(spacing: DockMetrics.contentSpacing) {
                header

                moduleView
                    // Fija la altura a la ideal del módulo. Sin esto, cualquier vista
                    // con un espaciador flexible se traga el alto sobrante del panel y
                    // lo perpetúa al medirse.
                    .fixedSize(horizontal: false, vertical: true)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentSizeKey.self, value: proxy.size)
                        }
                    )
                    // El `id` fuerza a SwiftUI a tratar cada módulo como una vista
                    // distinta, que es lo que habilita el fundido al cambiar.
                    .id(model.module)
                    // El que sale se va rápido y el que entra espera un instante: si
                    // se cruzan a la vez, los dos se ven encimados mientras el panel
                    // cambia de tamaño.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)),
                        removal: .opacity.animation(.easeOut(duration: 0.08))
                    ))

                ModuleSwitcher(selection: model.module, onSelect: model.select)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: TabBarWidthKey.self, value: proxy.size.width)
                        }
                    )
            }
            .padding(.horizontal, DockMetrics.horizontalPadding)
            .padding(.bottom, DockMetrics.bottomPadding)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            .onPreferenceChange(ContentSizeKey.self) { size in
                guard size.width > 0,
                      abs(size.width - model.measuredContentSize.width) > 0.5
                        || abs(size.height - model.measuredContentSize.height) > 0.5
                else { return }

                withAnimation(DockMetrics.moduleAnimation) {
                    model.measuredContentSize = size
                }
            }
            .onPreferenceChange(TabBarWidthKey.self) { width in
                guard width > 0, abs(width - model.tabBarWidth) > 0.5 else { return }
                model.tabBarWidth = width
            }
        } else if model.showsLiveActivity {
            LiveActivityView(
                media: model.stores.media,
                pomodoro: model.stores.pomodoro,
                isPlaying: model.stores.media.nowPlaying?.isPlaying == true || model.isDebugLiveActivity,
                cutoutWidth: model.geometry.cutoutRect.width,
                height: model.geometry.cutoutRect.height
            )
        }
    }

    /// La franja de la muesca no puede mostrar contenido, pero sus lados sí. Ahí queda
    /// sólo el engrane: es estrecho, así que apenas condiciona el ancho del panel.
    private var header: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            IconButton(symbol: "gearshape.fill", size: 11, help: "Ajustes") {
                model.showSettings?()
            }
        }
        .frame(height: model.geometry.cutoutRect.height)
    }

    @ViewBuilder
    private var moduleView: some View {
        switch model.module {
        case .player:
            PlayerView(media: model.stores.media)
        case .shelf:
            ShelfView(store: model.stores.shelf)
        case .clipboard:
            ClipboardView(store: model.stores.clipboard)
        case .claude:
            ClaudeUsageView(store: model.stores.claude)
        case .pomodoro:
            PomodoroView(timer: model.stores.pomodoro)
        case .calculator:
            CalculatorView(stores: model.stores)
        }
    }
}
