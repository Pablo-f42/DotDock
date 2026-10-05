import AppKit
import Combine
import SwiftUI

/// La ventana del panel.
///
/// Es un `NSPanel` no activante que flota por encima de la barra de menús, en todos
/// los espacios, y que nunca roba el foco a la app en primer plano.
final class DockPanel: NSPanel {

    private let model: DockModel
    private var cancellable: AnyCancellable?
    private var relinquishWork: DispatchWorkItem?

    init(model: DockModel) {
        self.model = model
        let frame = Self.frame(for: model.geometry)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .init(Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false

        // Sin esto, cualquier clic en el panel lo vuelve ventana clave — y al cerrarse
        // había que soltar el teclado sacando la ventana, lo que se comía la animación
        // de recogida. Así sólo toma el foco un control que lo necesite de verdad.
        becomesKeyOnlyIfNeeded = true

        // Sin esto el panel aparece en el conmutador de ventanas y en Exposé.
        isExcludedFromWindowsMenu = true

        // macOS anima con un fundido el sacar y volver a poner la ventana. Soltar el
        // teclado hace justo eso, y con el pomodoro o la música en el panel cerrado
        // se veía desaparecer y volver medio segundo después de minimizar.
        animationBehavior = .none

        let host = DockHostingView(model: model)
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host

        setFrame(frame, display: false)
        orderFrontRegardless()

        // `objectWillChange` se emite *antes* de aplicar el cambio, así que hay que
        // diferir un ciclo para leer el estado ya actualizado.
        cancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.syncKeyboardFocus() }
    }

    /// Sólo tomamos el teclado cuando el módulo abierto lo necesita, y lo devolvemos en
    /// cuanto deja de hacer falta: un panel que se queda con el foco deja a la app en
    /// primer plano sin poder escribir.
    private func syncKeyboardFocus() {
        let isOpen = model.state == .open
        let wantsKeyboard = isOpen && model.module.needsKeyboard

        if wantsKeyboard {
            relinquishWork?.cancel()
            relinquishWork = nil
            if !isKeyWindow { makeKey() }
            return
        }

        guard isKeyWindow else { return }

        if isOpen {
            // Cambiando de módulo con el panel abierto basta con soltar el campo de
            // texto. Sacar la ventana aquí era lo que hacía parpadear el panel entero
            // al cambiar de herramienta.
            makeFirstResponder(nil)
        } else {
            scheduleRelinquishKey()
        }
    }

    /// AppKit no expone "renuncia a ser key": hay que sacar la ventana y volverla a
    /// poner. Como eso la hace desaparecer de golpe, se espera a que termine la
    /// animación de recogida — si no, el panel se esfuma en vez de encogerse.
    private func scheduleRelinquishKey() {
        guard relinquishWork == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.relinquishWork = nil

            // El panel pudo reabrirse mientras esperábamos.
            guard self.model.state != .open, self.isKeyWindow else { return }

            self.orderOut(nil)
            self.orderFrontRegardless()
        }

        relinquishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// El panel no debe volverse key salvo que el contenido lo pida (campos de texto).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func reposition(for geometry: DockGeometry) {
        setFrame(Self.frame(for: geometry), display: true)
    }

    /// La ventana es siempre del tamaño máximo desplegado más un margen; el contenido
    /// crece dentro. Así evitamos animar el frame de la ventana, que se ve entrecortado.
    static func frame(for geometry: DockGeometry) -> CGRect {
        let pad = DockMetrics.windowPadding
        let width = DockMetrics.maxOpenSize.width + pad * 2
        let height = DockMetrics.maxOpenSize.height + pad

        return CGRect(
            x: geometry.cutoutRect.midX - width / 2,
            y: geometry.screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}
