import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Hosting view de SwiftUI que sólo captura eventos dentro del panel visible, y que
/// hace de destino de arrastre para la bandeja.
///
/// La ventana ocupa siempre el tamaño máximo desplegado, así que sin el hit-test el
/// panel se tragaría todos los clics de la parte superior de la pantalla.
final class DockHostingView: NSHostingView<DockRootView> {

    private let model: DockModel

    private static let readingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    init(model: DockModel) {
        self.model = model
        super.init(rootView: DockRootView(model: model))

        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init(rootView: DockRootView) { fatalError("use init(model:)") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window else { return nil }

        // `point` llega en coordenadas de la superview, no de esta vista.
        let local = convert(point, from: superview)
        let global = window.convertPoint(toScreen: convert(local, to: nil))
        guard model.interactiveRect.contains(global) else { return nil }

        return super.hitTest(point)
    }

    // MARK: - Destino de arrastre
    //
    // El arrastre se maneja aquí y no con `.onDrop` de SwiftUI porque durante una
    // sesión de arrastre el sistema no entrega eventos de ratón a las otras apps: el
    // `MouseTracker` no ve nada, el panel nunca se abre por hover y el área de drop
    // se queda del tamaño cerrado. Al abrirlo desde `draggingEntered`, el
    // `interactiveRect` crece y el resto del panel pasa a aceptar el soltado.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender) else { return [] }

        model.open(.shelf)
        model.stores.shelf.isTargeted = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        model.stores.shelf.isTargeted = false
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAccept(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model.stores.shelf.isTargeted = false

        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: Self.readingOptions
        )

        guard let urls = objects as? [URL], !urls.isEmpty else { return false }

        urls.forEach(model.stores.shelf.add)
        return true
    }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: Self.readingOptions
        )
    }
}
