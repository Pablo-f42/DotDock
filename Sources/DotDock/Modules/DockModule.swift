import SwiftUI

/// Los paneles que puede mostrar el panel desplegado.
/// Una pestaña, una herramienta. La bandeja vivía además dentro de "Inicio", donde
/// duplicaba su propia pestaña y le comía la mitad del ancho al reproductor.
enum DockModule: String, CaseIterable, Identifiable {
    case player
    case shelf
    case clipboard
    case claude
    case pomodoro
    case calculator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .player: "Reproductor"
        case .shelf: "Bandeja"
        case .clipboard: "Portapapeles"
        case .claude: "Uso de Claude"
        case .pomodoro: "Pomodoro"
        case .calculator: "Calculadora"
        }
    }

    /// Etiqueta de la pestaña activa. Va corta porque el espacio a la izquierda de
    /// la muesca es estrecho y "Calculadora" no cabe.
    var shortTitle: String {
        switch self {
        case .player: "Música"
        case .shelf: "Bandeja"
        case .clipboard: "Copias"
        case .claude: "Claude"
        case .pomodoro: "Foco"
        case .calculator: "Cálculo"
        }
    }

    var symbol: String {
        switch self {
        case .player: "music.note"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .claude: "sparkles"
        case .pomodoro: "timer"
        case .calculator: "function"
        }
    }

    /// La calculadora necesita que el panel se vuelva ventana clave para recibir
    /// teclas. El resto de módulos no debe robarle el teclado a la app en primer plano.
    var needsKeyboard: Bool { self == .calculator }

    /// Sólo la altura sale de aquí. El ancho lo decide el contenido ya dispuesto —
    /// `DockModel.measuredContentWidth` — y estos valores actúan de reserva para el
    /// primer fotograma, antes de que llegue la medida.
    var openSize: CGSize {
        switch self {
        case .player: CGSize(width: 580, height: 192)
        case .shelf: CGSize(width: 560, height: 186)
        case .clipboard: CGSize(width: 560, height: 222)
        case .claude: CGSize(width: 560, height: 200)
        case .pomodoro: CGSize(width: 500, height: 188)
        case .calculator: CGSize(width: 470, height: 250)
        }
    }
}
