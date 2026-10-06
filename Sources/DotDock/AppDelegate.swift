import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let stores = DockStores()

    /// Un modelo y un panel por pantalla conectada. Los datos son compartidos; lo que
    /// se duplica es la geometría y el estado abierto/cerrado.
    private var screens: [(model: DockModel, panel: DockPanel)] = []
    private var tracker: MouseTracker!
    private var statusItem: NSStatusItem?
    private let settingsWindow = SettingsWindow()
    private var cancellables = Set<AnyCancellable>()

    /// Mantiene viva la exclusión de App Nap mientras la app exista.
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !NSScreen.screens.isEmpty else {
            NSLog("DotDock: no hay pantallas disponibles")
            NSApp.terminate(nil)
            return
        }

        // macOS aplica App Nap a las apps accesorias sin ventanas visibles: estrangula
        // sus temporizadores hasta dejarlos casi parados. Para una app que vive de
        // sondear, eso equivale a congelarse a los pocos minutos.
        //
        // `allowingIdleSystemSleep` es deliberado: queremos seguir despiertos, pero sin
        // impedir que el Mac se duerma.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "DotDock mantiene indicadores en vivo en la muesca"
        )

        rebuildScreens()
        stores.start()
        installEditMenu()
        observeSettings()

        // El monitor es único y global: reparte la posición a todas las pantallas, y
        // cada una decide si el cursor cae sobre su panel.
        tracker = MouseTracker { [weak self] point in
            self?.screens.forEach { $0.model.handleMouseMoved(to: point) }
        }

        applyDebugMode()

        // Conectar o desconectar un monitor rehace los paneles.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildScreens() }
        }
    }

    /// Reconstruye la lista de paneles para las pantallas actuales.
    ///
    /// Se rehace entero en vez de intentar emparejar pantallas viejas con nuevas: los
    /// identificadores de pantalla cambian al reconectar, y un panel huérfano se queda
    /// flotando sobre una pantalla que ya no existe.
    private func rebuildScreens() {
        screens.forEach {
            $0.model.blob.stop()
            $0.panel.orderOut(nil)
        }
        screens = screensToUse().map { screen in
            let model = DockModel(geometry: DockGeometry(screen: screen), stores: stores)
            model.showSettings = { [weak self] in self?.presentSettingsMenu() }
            return (model, DockPanel(model: model))
        }

        // Un solo reloj para la gotita, aunque haya varios monitores: si no, saldrían
        // varias a la vez. Cuando toca, se asoma en la pantalla donde está el cursor,
        // que es la que estás mirando.
        blobHost?.blob.target = { [weak self] in self?.blobUnderCursor() }
        blobHost?.blob.start()
    }

    /// Las pantallas donde va un panel según los ajustes. Si se pide sólo la de la
    /// muesca y no hay ninguna, se usa la principal: DotDock no puede desaparecer.
    private func screensToUse() -> [NSScreen] {
        guard stores.settings.screenPolicy == .cutoutOnly else { return NSScreen.screens }

        let withCutout = NSScreen.screens.filter { DockGeometry(screen: $0).hasHardwareCutout }
        if !withCutout.isEmpty { return withCutout }
        return [DockGeometry.preferredScreen()].compactMap { $0 }
    }

    private func observeSettings() {
        let settings = stores.settings

        settings.$showsMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] shows in self?.setStatusItemVisible(shows) }
            .store(in: &cancellables)

        settings.$screenPolicy
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildScreens() }
            .store(in: &cancellables)
    }

    private func blobUnderCursor() -> BlobModel? {
        let cursor = NSEvent.mouseLocation
        return screens.first { $0.model.geometry.screen.frame.contains(cursor) }?.model.blob
    }

    /// El panel donde vive la gotita: el de la pantalla con muesca si la hay.
    private var blobHost: DockModel? {
        let preferred = DockGeometry.preferredScreen()
        return screens.first { $0.model.geometry.screen == preferred }?.model ?? screens.first?.model
    }

    /// Modos de inspección, siempre sobre la pantalla con muesca.
    ///   DOTDOCK_DEBUG_OPEN=player|shelf|clipboard|pomodoro|calculator|live
    ///   DOTDOCK_DEBUG_EXPR="2+3*4"      siembra la calculadora
    ///   DOTDOCK_DEBUG_THEN=player       cambia de módulo a los 2,5 s
    ///   DOTDOCK_DEBUG_CLOSE=4           cierra el panel a los 4 s
    ///   DOTDOCK_DEBUG_BLOB=normal|happy|sleepy|worried|music|wink|gulp|hello
    ///                                   la gotita se asoma ya con ese ánimo
    ///   DOTDOCK_DEBUG_SETTINGS=general|modules|music|dot|about   abre Ajustes ahí
    ///   DOTDOCK_DEBUG_TRACK="Título"    finge una canción sonando
    private func applyDebugMode() {
        let env = ProcessInfo.processInfo.environment

        if let title = env["DOTDOCK_DEBUG_TRACK"] {
            stores.media.debugFakeTrack(title: title)
        }

        if let mood = env["DOTDOCK_DEBUG_BLOB"] {
            blobHost?.blob.debugPeek(mood: mood)
        }

        if let raw = env["DOTDOCK_DEBUG_SETTINGS"] {
            showSettings(SettingsSection(rawValue: raw))
        }

        guard let value = env["DOTDOCK_DEBUG_OPEN"] else {
            tracker.start()
            return
        }

        // El tracker se queda parado a propósito: si no, el primer movimiento del
        // cursor en cualquier punto de la pantalla cierra el panel al instante.
        // La de la muesca, como la gotita: `NSScreen.main` es la de la ventana
        // activa, y con un monitor externo el panel se abría donde no se le veía.
        guard let main = blobHost else { return }

        if value == "live" {
            main.enableDebugLiveActivity()
            if let raw = env["DOTDOCK_DEBUG_POMODORO"], let fraction = Double(raw) {
                stores.pomodoro.debugStart(remainingFraction: fraction)
            }
            return
        }

        if let expression = env["DOTDOCK_DEBUG_EXPR"] {
            stores.calculatorInput = expression
        }
        main.open(DockModule(rawValue: value) ?? .player)

        if let next = env["DOTDOCK_DEBUG_THEN"], let module = DockModule(rawValue: next) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                MainActor.assumeIsolated { main.select(module) }
            }
        }

        if let raw = env["DOTDOCK_DEBUG_CLOSE"], let delay = Double(raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { main.close() }
            }
        }
    }

    // MARK: - Barra de menús

    /// El icono es opcional: el engrane del panel ofrece lo mismo.
    private func setStatusItemVisible(_ visible: Bool) {
        guard visible else {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil
            return
        }
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = StatusIcon.make()

        let menu = NSMenu()
        menu.addItem(withTitle: "Abrir DotDock", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de DotDock", action: #selector(quit), keyEquivalent: "q").target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func openPanel() {
        let cursor = NSEvent.mouseLocation
        let target = screens.first { $0.model.geometry.screen.frame.contains(cursor) }
            ?? screens.first
        target?.model.open()
    }

    /// Sin menú principal, macOS no enruta ⌘V, ⌘C ni ⌘A a los campos de texto: los
    /// atajos de edición **los despacha el menú Edición**, no el campo. Una app
    /// `LSUIElement` no tiene menú por defecto, así que hay que instalarlo a mano o
    /// pegar simplemente no funciona.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edición")

        // `undo:` y `redo:` no tienen declaración pública que referenciar con
        // `#selector`; se construyen por nombre.
        let items: [(title: String, action: Selector, key: String)?] = [
            ("Deshacer", Selector(("undo:")), "z"),
            ("Rehacer", Selector(("redo:")), "Z"),
            nil,
            ("Cortar", #selector(NSText.cut(_:)), "x"),
            ("Copiar", #selector(NSText.copy(_:)), "c"),
            ("Pegar", #selector(NSText.paste(_:)), "v"),
            ("Seleccionar todo", #selector(NSText.selectAll(_:)), "a")
        ]

        for item in items {
            guard let item else {
                edit.addItem(.separator())
                continue
            }

            // Sin `target`: el mensaje viaja por la cadena de respondedores hasta el
            // campo que tenga el foco.
            edit.addItem(withTitle: item.title, action: item.action, keyEquivalent: item.key)
        }

        let editItem = NSMenuItem()
        editItem.submenu = edit

        let main = NSMenu()
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Menú del engrane del panel: corto a propósito, la configuración vive en la
    /// ventana de Ajustes.
    private func presentSettingsMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de DotDock", action: #selector(quit), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func openSettings() {
        showSettings(nil)
    }

    private func showSettings(_ section: SettingsSection?) {
        // El panel se cierra: la ventana de Ajustes aparece en el centro y el panel
        // abierto quedaría tapando la parte de arriba.
        screens.forEach { $0.model.close() }
        settingsWindow.show(section: section, stores: stores, blob: blobHost?.blob)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
