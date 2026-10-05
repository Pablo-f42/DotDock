import AppKit
import Combine
import SwiftUI

enum DockState: Equatable {
    /// Tapando exactamente la muesca de la pantalla. Invisible.
    case closed
    /// El cursor está encima: crece un poco para invitar al clic.
    case peek
    /// Desplegado, mostrando un módulo.
    case open
}

/// Todas las medidas de la ventana y de la forma, en un solo lugar.
enum DockMetrics {
    /// Cuánto crece el panel (ancho total extra) al hacer hover.
    static let peekWidthGrowth: CGFloat = 24
    static let peekHeightGrowth: CGFloat = 4

    /// Cota superior de todos los módulos. La ventana se dimensiona con esto una sola
    /// vez; el contenido crece y encoge dentro. Redimensionar la ventana en cada cambio
    /// de módulo se vería entrecortado.
    ///
    /// El margen extra sobre el módulo más ancho deja sitio a que el suelo medido de la
    /// barra de pestañas empuje el panel sin que se salga de la ventana.
    static let maxOpenSize = CGSize(
        width: (DockModule.allCases.map(\.openSize.width).max() ?? 560) + 120,
        height: (DockModule.allCases.map(\.openSize.height).max() ?? 250) + 80
    )

    /// Margen lateral del contenido del panel.
    static let horizontalPadding: CGFloat = 14

    /// Aire mínimo entre lo que haya en la franja lateral y el borde de la muesca.
    static let tabBarClearance: CGFloat = 10

    /// Huella del botón de ajustes, que es lo único que queda junto a la muesca.
    static let gearWidth: CGFloat = 26

    static let contentSpacing: CGFloat = 8
    static let switcherHeight: CGFloat = 28
    static let bottomPadding: CGFloat = 14

    /// Ancho de cada ala del panel cerrado cuando hay reproducción: carátula a la
    /// izquierda, visualizador a la derecha. La altura no cambia, para que siga
    /// fundiéndose con la muesca de la pantalla.
    static let liveActivitySideWidth: CGFloat = 34

    /// La ventana es siempre de este tamaño; el contenido crece dentro.
    /// El margen extra deja espacio para la sombra y las esquinas cóncavas.
    static let windowPadding = CGFloat(60)

    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 12
    static let openTopRadius: CGFloat = 10
    static let openBottomRadius: CGFloat = 26

    /// Cuánto margen alrededor del panel sigue contando como "hover", para que no
    /// se cierre por un pixel de temblor del cursor.
    static let hoverSlop: CGFloat = 4
    static let openHoverSlop: CGFloat = 60

    /// Cuánto hay que sostener el cursor sobre el panel antes de que se despliegue.
    /// Suficiente para no dispararse de paso camino a la barra de menús.
    static let hoverOpenDelay: TimeInterval = 0.15

    /// Margen de gracia al salir. Sin esto, rozar el borde un instante mientras vas a
    /// pulsar un botón cierra el panel en la cara del usuario.
    static let closeGraceDelay: TimeInterval = 0.35

    static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.76)
    static let closeAnimation = Animation.spring(response: 0.36, dampingFraction: 0.88)

    /// Cambio de módulo. Ahora el panel también cambia de ancho, así que un spring muy
    /// amortiguado sienta mejor que una curva lineal: acompaña el cambio de forma sin
    /// llegar a rebotar.
    static let moduleAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

@MainActor
final class DockModel: ObservableObject {

    @Published private(set) var state: DockState = .closed
    @Published private(set) var geometry: DockGeometry

    /// Módulo visible cuando el panel está abierto.
    @Published var module: DockModule = .player

    /// Datos compartidos entre todas las pantallas.
    let stores: DockStores

    /// Ancho real de la barra de pestañas, medido por la vista. Alimenta el suelo del
    /// ancho del panel.
    @Published var tabBarWidth: CGFloat = 0

    /// Tamaño que pide el módulo visible, medido de su contenido ya dispuesto.
    ///
    /// No hay bucle de realimentación porque el contenido no es elástico: no depende
    /// del panel, y el panel nunca lo comprime por debajo de lo que pidió.
    @Published var measuredContentSize: CGSize = .zero

    /// El panel en reposo muestra carátula y visualizador sólo mientras algo suena de
    /// verdad. Atado a "hay pista cargada" se quedaría ancho para siempre con Spotify
    /// abierto en pausa.
    @Published private(set) var showsLiveActivity = false

    /// Fuerza el live activity aunque no suene nada, para poder inspeccionarlo con una
    /// captura sin tener que darle a play. Ver `DOTDOCK_DEBUG_OPEN=live`.
    private(set) var isDebugLiveActivity = false

    /// Lo instala el `AppDelegate`. El menú se construye en AppKit y no con `Menu` de
    /// SwiftUI porque en un panel no activante los menús de SwiftUI no siempre abren.
    var showSettings: (() -> Void)?

    /// La gotita que se asoma bajo este panel. Sólo se arranca en una pantalla.
    private(set) lazy var blob = BlobModel(dock: self)

    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(geometry: DockGeometry, stores: DockStores) {
        self.geometry = geometry
        self.stores = stores

        // `contentSize` depende del estado de reproducción, que vive en otro
        // ObservableObject: sin republicarlo aquí, la ventana no cambiaría de tamaño.
        stores.media.$nowPlaying
            .map { $0?.isPlaying == true }
            .combineLatest(stores.pomodoro.$isRunning)
            .map { $0 || $1 }
            .removeDuplicates()
            .sink { [weak self] isActive in
                guard let self else { return }
                withAnimation(DockMetrics.openAnimation) {
                    self.showsLiveActivity = isActive
                }
            }
            .store(in: &cancellables)
    }

    func updateGeometry(_ geometry: DockGeometry) {
        self.geometry = geometry
    }

    // MARK: - Tamaño del contenido según el estado

    /// Tamaño en reposo. Crece para hacer sitio al live activity cuando algo suena.
    private var closedSize: CGSize {
        let cutout = geometry.cutoutRect.size
        guard showsLiveActivity else { return cutout }

        return CGSize(
            width: cutout.width + DockMetrics.liveActivitySideWidth * 2,
            height: cutout.height
        )
    }

    /// Ancho mínimo del panel abierto. Dos restricciones a la vez:
    ///
    /// 1. El engrane debe caber **a la derecha de la muesca**. Como la muesca va centrada,
    ///    esa franja cuenta dos veces. Con la barra de pestañas aquí el suelo era de
    ///    453 pt y aplanaba a todos los módulos; sólo con el engrane baja a ~289.
    /// 2. La barra de pestañas del pie debe caber a lo ancho.
    private var minimumOpenWidth: CGFloat {
        let gearFlank = DockMetrics.horizontalPadding
            + DockMetrics.gearWidth
            + DockMetrics.tabBarClearance

        return max(
            geometry.cutoutRect.width + gearFlank * 2,
            tabBarWidth + DockMetrics.horizontalPadding * 2
        )
    }

    var contentSize: CGSize {
        switch state {
        case .closed:
            return closedSize
        case .peek:
            return CGSize(
                width: closedSize.width + DockMetrics.peekWidthGrowth,
                height: closedSize.height + DockMetrics.peekHeightGrowth
            )
        case .open:
            guard measuredContentSize.width > 0 else { return module.openSize }

            let width = measuredContentSize.width + DockMetrics.horizontalPadding * 2

            // La franja de la muesca no puede mostrar contenido, así que el alto útil
            // empieza debajo de ella y termina bajo la barra de módulos.
            let height = geometry.cutoutRect.height
                + DockMetrics.contentSpacing * 2
                + measuredContentSize.height
                + DockMetrics.switcherHeight
                + DockMetrics.bottomPadding

            return CGSize(
                width: min(max(width, minimumOpenWidth), DockMetrics.maxOpenSize.width),
                height: min(height, DockMetrics.maxOpenSize.height)
            )
        }
    }

    var topRadius: CGFloat {
        state == .open ? DockMetrics.openTopRadius : DockMetrics.closedTopRadius
    }

    var bottomRadius: CGFloat {
        state == .open ? DockMetrics.openBottomRadius : DockMetrics.closedBottomRadius
    }

    /// Rect interactivo en coordenadas globales, usado por el hit-test de la ventana
    /// para dejar pasar los clics fuera del panel.
    var interactiveRect: CGRect {
        let size = contentSize
        return CGRect(
            x: geometry.cutoutRect.midX - size.width / 2,
            y: geometry.cutoutRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Transiciones

    func handleMouseMoved(to point: CGPoint) {
        blob.cursorMoved(to: point)

        // Abierto se tolera mucho más movimiento antes de cerrar: si no, el panel se
        // cierra en cuanto el cursor roza el borde mientras interactúas.
        let slop = state == .open ? DockMetrics.openHoverSlop : DockMetrics.hoverSlop
        let hot = interactiveRect.insetBy(dx: -slop, dy: -slop)

        if hot.contains(point) {
            pendingClose?.cancel()
            pendingClose = nil

            if state == .closed { setState(.peek) }
            if state == .peek { scheduleOpen() }
        } else {
            pendingOpen?.cancel()
            pendingOpen = nil

            if state != .closed { scheduleClose() }
        }
    }

    func select(_ module: DockModule) {
        guard module != self.module else { return }
        withAnimation(DockMetrics.moduleAnimation) { self.module = module }
    }

    func toggleOpen() {
        setState(state == .open ? .closed : .open)
    }

    func open(_ module: DockModule = .player) {
        self.module = module
        cancelPending()
        setState(.open)
        stores.refreshOnOpen()
    }

    func close() {
        cancelPending()
        setState(.closed)
    }

    func enableDebugLiveActivity() {
        isDebugLiveActivity = true
        showsLiveActivity = true
    }

    // MARK: - Retardos

    private func scheduleOpen() {
        guard pendingOpen == nil else { return }
        pendingOpen = schedule(after: DockMetrics.hoverOpenDelay) { [weak self] in
            guard let self else { return }
            self.pendingOpen = nil
            guard self.state == .peek else { return }
            self.setState(.open)
        }
    }

    private func scheduleClose() {
        guard pendingClose == nil else { return }
        pendingClose = schedule(after: DockMetrics.closeGraceDelay) { [weak self] in
            guard let self else { return }
            self.pendingClose = nil
            self.setState(.closed)
        }
    }

    private func cancelPending() {
        pendingOpen?.cancel()
        pendingClose?.cancel()
        pendingOpen = nil
        pendingClose = nil
    }

    private func schedule(after delay: TimeInterval, action: @escaping () -> Void) -> DispatchWorkItem {
        let work = DispatchWorkItem { MainActor.assumeIsolated(action) }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return work
    }

    private func setState(_ new: DockState) {
        guard new != state else { return }
        if new == .open { stores.refreshOnOpen() }
        if new != .closed { blob.hideNow() }
        let animation = new == .closed ? DockMetrics.closeAnimation : DockMetrics.openAnimation
        withAnimation(animation) { state = new }
    }
}
