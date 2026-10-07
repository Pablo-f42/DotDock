import AppKit
import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case modules
    case music
    case dot
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .modules: "Módulos"
        case .music: "Música"
        case .dot: "Dot"
        case .about: "Acerca de"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .modules: "square.grid.2x2.fill"
        case .music: "music.note"
        case .dot: "face.smiling.inverse"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .modules: .blue
        case .music: .pink
        case .dot: .indigo
        case .about: .teal
        }
    }
}

/// Qué sección está a la vista. Vive fuera de la vista para poder abrir la ventana
/// directamente en una sección.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var section: SettingsSection = .general
}

/// La ventana de Ajustes. Es una ventana normal, no un panel: aquí sí queremos que la
/// app pase a primer plano y reciba el teclado mientras está abierta.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    /// La gotita se pide cada vez y no se guarda: los paneles se rehacen al cambiar
    /// las pantallas, y una referencia vieja apuntaría a una gotita sin panel.
    private var blob: () -> BlobModel? = { nil }

    func show(section: SettingsSection? = nil, stores: DockStores, blob: @escaping () -> BlobModel?) {
        if let section { navigation.section = section }
        self.blob = blob

        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Ajustes de DotDock"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(
                rootView: SettingsView(
                    navigation: navigation,
                    settings: stores.settings,
                    media: stores.media,
                    blob: { [weak self] in self?.blob() }
                )
            )
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Al cerrar, la gotita deja de posar.
    func windowWillClose(_ notification: Notification) {
        blob()?.setDesignHold(false)
    }
}
