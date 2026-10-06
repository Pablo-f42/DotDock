import AppKit
import SwiftUI

// MARK: - Opciones

enum OpenTrigger: String, CaseIterable, Identifiable {
    /// Se despliega al dejar el cursor encima.
    case hover
    /// El cursor sólo lo agranda un poco; se despliega con un clic.
    case click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hover: "Al pasar el cursor"
        case .click: "Con un clic"
        }
    }
}

enum HoverSpeed: String, CaseIterable, Identifiable {
    case fast
    case normal
    case slow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: "Rápido"
        case .normal: "Normal"
        case .slow: "Lento"
        }
    }

    /// Cuánto hay que sostener el cursor encima antes de desplegar. Lento sirve a quien
    /// cruza a menudo por arriba camino a la barra de menús.
    var delay: TimeInterval {
        switch self {
        case .fast: 0.05
        case .normal: 0.15
        case .slow: 0.4
        }
    }
}

enum ScreenPolicy: String, CaseIterable, Identifiable {
    case all
    case cutoutOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "En todas las pantallas"
        case .cutoutOnly: "Sólo en la pantalla con muesca"
        }
    }
}

enum VisualizerTint: String, CaseIterable, Identifiable {
    case white
    /// El color dominante de la carátula: cambia con cada canción.
    case artwork
    case spotify
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: "Blanco"
        case .artwork: "De la carátula"
        case .spotify: "Verde Spotify"
        case .custom: "Personalizado"
        }
    }
}

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case bars
    case wave
    case dots

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: "Barras"
        case .wave: "Onda"
        case .dots: "Puntos"
        }
    }
}

enum BlobTrigger: Equatable {
    /// A ratos al azar, sólo con el panel cerrado y sin nada sonando.
    case resting
    /// Cada tantos minutos, suene algo o no.
    case every(minutes: Int)
}

enum BlobPersonality: String, CaseIterable, Identifiable {
    case calm
    case normal
    case curious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "Tranquila"
        case .normal: "Normal"
        case .curious: "Curiosa"
        }
    }

    var detail: String {
        switch self {
        case .calm: "Se asoma cada 5 a 10 minutos"
        case .normal: "Se asoma cada 2 a 5 minutos"
        case .curious: "Se asoma cada 1 a 2 minutos"
        }
    }

    /// Espera entre asomadas en reposo, en segundos.
    var restingDelay: ClosedRange<TimeInterval> {
        switch self {
        case .calm: 300...600
        case .normal: 120...300
        case .curious: 50...120
        }
    }
}

/// Lo que hace salir a la gotita fuera de su horario.
enum BlobReaction: String, CaseIterable, Identifiable {
    case music
    case pomodoro
    case copy
    case shelf
    case claude
    case welcome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "Empieza a sonar música"
        case .pomodoro: "Terminas un pomodoro"
        case .copy: "Copias algo"
        case .shelf: "Sueltas un archivo en la bandeja"
        case .claude: "Claude pasa del 80 %"
        case .welcome: "Vuelves tras un rato fuera"
        }
    }

    var detail: String {
        switch self {
        case .music: "Sale a bailar"
        case .pomodoro: "Lo celebra"
        case .copy: "Te guiña un ojo"
        case .shelf: "Se lo traga"
        case .claude: "Se preocupa"
        case .welcome: "Te saluda"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .pomodoro: "timer"
        case .copy: "doc.on.clipboard"
        case .shelf: "tray.full"
        case .claude: "sparkles"
        case .welcome: "hand.wave"
        }
    }
}

enum EyeColor: String, CaseIterable, Identifiable {
    case white
    case cyan
    case pink
    case yellow
    case green

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: "Blanco"
        case .cyan: "Cian"
        case .pink: "Rosa"
        case .yellow: "Amarillo"
        case .green: "Verde"
        }
    }

    var color: Color {
        switch self {
        case .white: .white
        case .cyan: Color(red: 0.45, green: 0.9, blue: 1)
        case .pink: Color(red: 1, green: 0.55, blue: 0.8)
        case .yellow: Color(red: 1, green: 0.88, blue: 0.35)
        case .green: Color(red: 0.45, green: 0.95, blue: 0.55)
        }
    }
}

// MARK: - Ajustes

/// Todas las preferencias de la app, guardadas en `UserDefaults`. Las comparten todas
/// las pantallas: viven en `DockStores`.
@MainActor
final class AppSettings: ObservableObject {

    private enum Key {
        static let menuBarIcon = "general.menuBarIcon"
        static let openTrigger = "general.openTrigger"
        static let hoverSpeed = "general.hoverSpeed"
        static let screens = "general.screens"

        static let moduleOrder = "modules.order"
        static let disabledModules = "modules.disabled"
        static let startModule = "modules.start"
        static let focusMinutes = "pomodoro.focusMinutes"
        static let shortBreakMinutes = "pomodoro.shortBreakMinutes"
        static let longBreakMinutes = "pomodoro.longBreakMinutes"
        static let pomodoroSound = "pomodoro.sound"
        static let clipboardCapacity = "clipboard.capacity"

        static let liveActivity = "music.liveActivity"
        static let visualizerTint = "music.visualizerTint"
        static let customTint = "music.customTint"
        static let visualizerStyle = "music.visualizerStyle"

        // Las de la gotita conservan sus claves de antes para no perder lo guardado.
        static let blobEnabled = "blob.enabled"
        static let blobInterval = "blob.intervalMinutes"
        static let blobPersonality = "blob.personality"
        static let blobReactions = "blob.reactions"
        static let blobFollowsCursor = "blob.followsCursor"
        static let blobShy = "blob.shy"
        static let blobEyeColor = "blob.eyeColor"
    }

    static let blobIntervalChoices = [1, 3, 5, 10, 15, 30]
    static let clipboardCapacityChoices = [5, 10, 20]

    private let defaults = UserDefaults.standard

    // MARK: General

    @Published var showsMenuBarIcon: Bool { didSet { defaults.set(showsMenuBarIcon, forKey: Key.menuBarIcon) } }
    @Published var openTrigger: OpenTrigger { didSet { save(openTrigger, Key.openTrigger) } }
    @Published var hoverSpeed: HoverSpeed { didSet { save(hoverSpeed, Key.hoverSpeed) } }
    @Published var screenPolicy: ScreenPolicy { didSet { save(screenPolicy, Key.screens) } }

    // MARK: Módulos

    /// Todos los módulos, en el orden de la barra de pestañas.
    @Published var moduleOrder: [DockModule] {
        didSet { defaults.set(moduleOrder.map(\.rawValue), forKey: Key.moduleOrder) }
    }

    @Published var disabledModules: Set<DockModule> {
        didSet { defaults.set(disabledModules.map(\.rawValue), forKey: Key.disabledModules) }
    }

    /// Con qué módulo se abre el panel. `nil` es "el último que usaste".
    @Published var startModule: DockModule? {
        didSet { defaults.set(startModule?.rawValue ?? "", forKey: Key.startModule) }
    }

    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Key.focusMinutes) } }
    @Published var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: Key.shortBreakMinutes) } }
    @Published var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Key.longBreakMinutes) } }
    @Published var pomodoroSound: Bool { didSet { defaults.set(pomodoroSound, forKey: Key.pomodoroSound) } }
    @Published var clipboardCapacity: Int { didSet { defaults.set(clipboardCapacity, forKey: Key.clipboardCapacity) } }

    // MARK: Música

    /// Carátula y visualizador a los lados de la muesca mientras suena algo.
    @Published var showsLiveActivity: Bool { didSet { defaults.set(showsLiveActivity, forKey: Key.liveActivity) } }
    @Published var visualizerTint: VisualizerTint { didSet { save(visualizerTint, Key.visualizerTint) } }
    @Published var customTint: Color { didSet { defaults.set(customTint.hexString, forKey: Key.customTint) } }
    @Published var visualizerStyle: VisualizerStyle { didSet { save(visualizerStyle, Key.visualizerStyle) } }

    // MARK: Gotita

    @Published var blobEnabled: Bool { didSet { defaults.set(blobEnabled, forKey: Key.blobEnabled) } }

    @Published var blobTrigger: BlobTrigger {
        didSet {
            let minutes = if case .every(let minutes) = blobTrigger { minutes } else { 0 }
            defaults.set(minutes, forKey: Key.blobInterval)
        }
    }

    @Published var blobPersonality: BlobPersonality { didSet { save(blobPersonality, Key.blobPersonality) } }

    @Published var blobReactions: Set<BlobReaction> {
        didSet { defaults.set(blobReactions.map(\.rawValue), forKey: Key.blobReactions) }
    }

    @Published var blobFollowsCursor: Bool { didSet { defaults.set(blobFollowsCursor, forKey: Key.blobFollowsCursor) } }
    @Published var blobIsShy: Bool { didSet { defaults.set(blobIsShy, forKey: Key.blobShy) } }
    @Published var blobEyeColor: EyeColor { didSet { save(blobEyeColor, Key.blobEyeColor) } }

    init() {
        let d = UserDefaults.standard

        showsMenuBarIcon = d.bool(forKey: Key.menuBarIcon)
        openTrigger = Self.load(Key.openTrigger, .hover)
        hoverSpeed = Self.load(Key.hoverSpeed, .normal)
        screenPolicy = Self.load(Key.screens, .all)

        // Un módulo nuevo que aún no estaba en el orden guardado se añade al final.
        let savedOrder = (d.stringArray(forKey: Key.moduleOrder) ?? []).compactMap(DockModule.init(rawValue:))
        moduleOrder = savedOrder + DockModule.allCases.filter { !savedOrder.contains($0) }
        disabledModules = Set((d.stringArray(forKey: Key.disabledModules) ?? []).compactMap(DockModule.init(rawValue:)))
        startModule = d.string(forKey: Key.startModule).flatMap(DockModule.init(rawValue:))

        focusMinutes = d.object(forKey: Key.focusMinutes) as? Int ?? 25
        shortBreakMinutes = d.object(forKey: Key.shortBreakMinutes) as? Int ?? 5
        longBreakMinutes = d.object(forKey: Key.longBreakMinutes) as? Int ?? 15
        pomodoroSound = d.object(forKey: Key.pomodoroSound) as? Bool ?? true
        clipboardCapacity = d.object(forKey: Key.clipboardCapacity) as? Int ?? 5

        showsLiveActivity = d.object(forKey: Key.liveActivity) as? Bool ?? true
        visualizerTint = Self.load(Key.visualizerTint, .white)
        customTint = d.string(forKey: Key.customTint).flatMap(Color.init(hex:)) ?? Color(red: 1, green: 0.45, blue: 0.3)
        visualizerStyle = Self.load(Key.visualizerStyle, .bars)

        blobEnabled = d.object(forKey: Key.blobEnabled) as? Bool ?? true
        let minutes = d.integer(forKey: Key.blobInterval)
        blobTrigger = minutes > 0 ? .every(minutes: minutes) : .resting
        blobPersonality = Self.load(Key.blobPersonality, .normal)
        blobReactions = d.stringArray(forKey: Key.blobReactions)
            .map { Set($0.compactMap(BlobReaction.init(rawValue:))) }
            ?? Set(BlobReaction.allCases)
        blobFollowsCursor = d.object(forKey: Key.blobFollowsCursor) as? Bool ?? true
        blobIsShy = d.object(forKey: Key.blobShy) as? Bool ?? true
        blobEyeColor = Self.load(Key.blobEyeColor, .white)
    }

    // MARK: Derivados

    /// Las pestañas que se muestran, en orden. Nunca vacía: si todo estuviera
    /// apagado, el panel no tendría nada que enseñar.
    var visibleModules: [DockModule] {
        let visible = moduleOrder.filter { !disabledModules.contains($0) }
        return visible.isEmpty ? [moduleOrder.first ?? .player] : visible
    }

    func isModuleEnabled(_ module: DockModule) -> Bool {
        !disabledModules.contains(module)
    }

    func setModule(_ module: DockModule, enabled: Bool) {
        if enabled {
            disabledModules.remove(module)
        } else if visibleModules.count > 1 {
            disabledModules.insert(module)
        }
    }

    func reacts(to reaction: BlobReaction) -> Bool {
        blobEnabled && blobReactions.contains(reaction)
    }

    func setReaction(_ reaction: BlobReaction, enabled: Bool) {
        if enabled { blobReactions.insert(reaction) } else { blobReactions.remove(reaction) }
    }

    func minutes(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    // MARK: Persistencia

    private func save<T: RawRepresentable>(_ value: T, _ key: String) where T.RawValue == String {
        defaults.set(value.rawValue, forKey: key)
    }

    private static func load<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}

// MARK: - Color en texto

extension Color {

    /// `#RRGGBB` en sRGB, para guardar un color elegido por el usuario.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }

    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }

        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
