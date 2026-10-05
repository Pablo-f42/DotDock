import AppKit

/// Punto de entrada.
///
/// Va en un `@main` y no en un `main.swift` porque el código de nivel superior corre
/// en contexto no aislado, y construir el `AppDelegate` (que es `@MainActor`) desde
/// ahí es un error de aislamiento.
@main
struct DotDockApp {

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        // `.accessory`: sin icono en el Dock, pero puede mostrar ventanas y menús.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
