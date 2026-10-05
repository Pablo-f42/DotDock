import AppKit

/// Sigue el cursor por toda la pantalla para abrir y cerrar el panel.
///
/// Usamos monitores globales de `NSEvent` en vez de `NSTrackingArea`/`onHover` porque
/// el panel no es la ventana activa: las tracking areas de SwiftUI se pierden eventos
/// cuando el foco está en otra app. Los monitores de ratón (a diferencia de los de
/// teclado) no piden permisos de accesibilidad.
@MainActor
final class MouseTracker {

    private let onMove: (CGPoint) -> Void
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private static let events: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged
    ]

    init(onMove: @escaping (CGPoint) -> Void) {
        self.onMove = onMove
    }

    func start() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit() }
        }

        // El monitor global no ve los eventos que ocurren sobre nuestra propia ventana.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
            MainActor.assumeIsolated { self?.emit() }
            return event
        }
    }

    func stop() {
        [globalMonitor, localMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        globalMonitor = nil
        localMonitor = nil
    }

    private func emit() {
        received += 1
        onMove(NSEvent.mouseLocation)
    }

    /// Cuántos eventos han llegado. Sirve para comprobar si el sandbox corta los
    /// monitores globales: sin ellos el panel no se despliega nunca.
    private(set) var received = 0
}
