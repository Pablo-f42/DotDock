import AppKit

/// Medidas de la muesca de la pantalla para una pantalla concreta.
///
/// En pantallas sin muesca usamos un "pill" sintético del mismo tamaño pegado al
/// borde superior, para que el resto de la app no tenga que saber la diferencia.
struct DockGeometry {

    /// Tamaño del pill sintético en pantallas sin muesca.
    static let fallbackSize = CGSize(width: 200, height: 32)

    let screen: NSScreen
    let hasHardwareCutout: Bool

    /// Rect de la muesca en coordenadas globales de AppKit (origen abajo-izquierda).
    let cutoutRect: CGRect

    init(screen: NSScreen) {
        self.screen = screen

        let inset = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let hardwareWidth = screen.frame.width - left - right

        // safeAreaInsets.top también es > 0 por la barra de menús en pantallas sin
        // muesca, así que exigimos además que existan las áreas auxiliares.
        let hasCutout = inset > 0 && left > 0 && right > 0 && hardwareWidth > 0
        self.hasHardwareCutout = hasCutout

        let size = hasCutout
            ? CGSize(width: hardwareWidth, height: inset)
            : Self.fallbackSize

        self.cutoutRect = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Pantalla donde debe vivir el panel: la que tiene muesca, o la principal.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { DockGeometry(screen: $0).hasHardwareCutout }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
