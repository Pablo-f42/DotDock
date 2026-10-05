import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Bandeja de archivos: sueltas algo sobre el panel y queda ahí para arrastrarlo a
/// otra app. Sólo guardamos referencias, nunca copiamos el archivo.
@MainActor
final class ShelfStore: ObservableObject {

    @Published private(set) var items: [ShelfItem] = []
    @Published var isTargeted = false

    private static let defaultsKey = "shelf.items"

    private var hasValidated = false

    init() {
        // Restaurar sin tocar el disco. Comprobar la existencia aquí significaba hacer
        // `stat` sobre rutas que pueden estar en Descargas, Documentos o Escritorio —
        // carpetas protegidas — y macOS responde a eso con un diálogo de permiso nada
        // más arrancar, sin que el usuario haya abierto siquiera el panel.
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        items = paths.map { ShelfItem(url: URL(fileURLWithPath: $0)) }
    }

    /// Descarta lo que ya no existe. Se llama al abrir la bandeja: para entonces el
    /// acceso al disco es consecuencia de algo que el usuario pidió.
    func validate() {
        guard !hasValidated else { return }
        hasValidated = true

        let alive = items.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard alive.count != items.count else { return }

        items = alive
        save()
    }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        withAnimation(DockMetrics.openAnimation) {
            items.append(ShelfItem(url: url))
        }
        save()
    }

    func remove(_ item: ShelfItem) {
        withAnimation(DockMetrics.closeAnimation) {
            items.removeAll { $0.id == item.id }
        }
        save()
    }

    func removeAll() {
        withAnimation(DockMetrics.closeAnimation) { items.removeAll() }
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: Self.defaultsKey)
    }
}
