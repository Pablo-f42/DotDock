import AppKit
import Foundation

/// Estado del permiso de Automatización para una app concreta.
enum AutomationPermission {
    case granted
    case denied
    /// macOS todavía no ha preguntado. Consultarlo **no** dispara el diálogo.
    case notAsked
    case appNotRunning
}

enum MediaFetchResult {
    case none
    case track(NowPlaying)
    /// El usuario negó (o aún no concedió) el permiso de Automatización.
    case notAuthorized
}

/// Lee el estado de reproducción vía AppleScript.
///
/// Es la única vía sin APIs privadas: `MediaRemote` exige desde macOS 15.4 un
/// entitlement que Apple no otorga a terceros. A cambio, sólo funciona con apps que
/// publican diccionario de scripting — Music y Spotify, no navegadores.
///
/// Toda la ejecución ocurre fuera del hilo principal: `NSAppleScript` bloquea y no es
/// thread-safe, así que la confinamos a una cola serial propia.
///
/// Es `Sendable`: la fuente es inmutable y el único estado que muta —el permiso ya
/// conocido— vive tras un candado. Cada llamada crea su propio `NSAppleScript` y lo
/// descarta.
final class AppleScriptMediaProvider: Sendable {

    let source: MediaSource

    private static let separator = "|~|"
    private let permissionCache = PermissionCache()

    init(source: MediaSource) {
        self.source = source
    }

    var isRunning: Bool { source.isRunning }

    /// Consulta el permiso sin pedirlo.
    ///
    /// `askUserIfNeeded: false` es la clave: deja saber si haría falta el diálogo sin
    /// llegar a mostrarlo. Así la app no asalta al usuario nada más abrirla — pregunta
    /// sólo cuando él lo pide desde el panel.
    ///
    /// La llamada al sistema no ocurre aquí sino en `PermissionCache`, fuera de la cola
    /// que pregunta: contra Spotify no vuelve nunca mientras TCC no tenga decisión
    /// guardada, y no puede llevarse por delante el sondeo. Sin respuesta se dice
    /// `.notAsked` y la vista ofrece el botón, que sí sabe provocar el diálogo.
    var permission: AutomationPermission {
        guard isRunning else {
            // Al reabrirse la app el permiso puede ser otro; se vuelve a preguntar.
            permissionCache.forget()
            return .appNotRunning
        }

        let source = self.source
        return permissionCache.resolve { Self.determine(for: source, askUser: false) }
    }

    /// Provoca el diálogo del sistema. Sólo se llama desde una acción del usuario.
    ///
    /// Manda el AppleScript de verdad en vez de `AEDeterminePermissionToAutomateTarget`
    /// con `askUserIfNeeded: true`. Esa llamada **no vuelve nunca** contra Spotify
    /// mientras TCC no tenga una decisión guardada: comprobado con una app de
    /// diagnóstico recién firmada y sin historial —Finder contesta en 0,04 s, Spotify
    /// se queda colgado indefinidamente—, así que el botón no llegaba a mostrar nada.
    /// Enviar el evento real sí hace que macOS pregunte, que es como funcionaba esto
    /// antes de que existiera el chequeo previo.
    ///
    /// Bloquea mientras el diálogo está en pantalla, así que el llamante tiene que
    /// estar en un hilo que se pueda permitir esa espera — nunca la cola de sondeo.
    @discardableResult
    func requestPermission() -> AutomationPermission {
        guard isRunning else { return .appNotRunning }

        let result: AutomationPermission
        switch run(stateScript) {
        case .text: result = .granted
        case .notAuthorized: result = .denied
        // Ni respuesta ni negativa: la app se cerró o falló por otra causa. No se
        // guarda nada, para que el siguiente intento vuelva a preguntar.
        case nil: return permissionCache.value
        }

        permissionCache.set(result)
        return result
    }

    /// La llamada cruda. Bloqueante y sin plazo: la API no ofrece ninguno.
    private static func determine(for source: MediaSource, askUser: Bool) -> AutomationPermission {
        var target = AEAddressDesc()
        let identifier = source.bundleID as NSString
        guard let raw = identifier.utf8String else { return .notAsked }

        AECreateDesc(typeApplicationBundleID, raw, strlen(raw), &target)
        defer { AEDisposeDesc(&target) }

        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, askUser) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        default: return .notAsked
        }
    }

    // MARK: - Lectura

    func fetch() -> MediaFetchResult {
        // Nunca dirigirse a la app si no corre: `tell application` la lanzaría.
        guard isRunning else { return .none }

        // Sin permiso concedido no se lanza el AppleScript: hacerlo mostraría el
        // diálogo del sistema por sorpresa, sin que el usuario haya pedido nada.
        switch permission {
        case .granted: break
        case .denied: return .notAuthorized
        case .notAsked, .appNotRunning: return .none
        }

        guard let output = run(stateScript) else { return .none }

        switch output {
        case .notAuthorized:
            return .notAuthorized
        case .text(let raw):
            return parse(raw).map(MediaFetchResult.track) ?? .none
        }
    }

    private func parse(_ raw: String) -> NowPlaying? {
        let fields = raw.components(separatedBy: Self.separator)
        guard fields.count >= 7, let state = PlaybackState(rawValue: fields[0]) else { return nil }

        let rawDuration = Self.number(fields[4])
        let duration = source.durationIsMilliseconds ? rawDuration / 1000 : rawDuration

        return NowPlaying(
            source: source,
            title: fields[1],
            artist: fields[2],
            album: fields[3],
            state: state,
            duration: duration,
            position: Self.number(fields[5]),
            artworkKey: fields[6]
        )
    }

    /// AppleScript formatea los números según la configuración regional, así que un
    /// `1,5` en locale español es perfectamente posible.
    private static func number(_ text: String) -> Double {
        Double(text) ?? Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: - Control

    func send(_ command: MediaCommand) {
        guard isRunning else { return }
        _ = run("tell application id \"\(source.bundleID)\" to \(command.appleScript)")
    }

    /// Vuelca la carátula de Music a un archivo. Spotify no la necesita: expone una URL.
    ///
    /// `raw data` puede venir en TIFF o JPEG según el álbum; `NSImage` detecta el
    /// formato por contenido, así que la extensión del archivo da igual.
    func exportArtwork(to path: String) -> Bool {
        guard source == .music, isRunning else { return false }

        let script = """
        tell application id "\(source.bundleID)"
            set theData to (get raw data of artwork 1 of current track)
        end tell

        set theFile to open for access (POSIX file "\(path)") with write permission
        try
            set eof theFile to 0
            write theData to theFile
            close access theFile
        on error
            close access theFile
            return "error"
        end try
        return "ok"
        """

        if case .text(let value) = run(script) { return value == "ok" }
        return false
    }

    func seek(to seconds: TimeInterval) {
        guard isRunning else { return }
        let value = String(format: "%.0f", seconds)
        _ = run("tell application id \"\(source.bundleID)\" to set player position to \(value)")
    }

    // MARK: - AppleScript

    private enum ScriptOutput {
        case text(String)
        case notAuthorized
    }

    private func run(_ source: String) -> ScriptOutput? {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&error)

        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: el usuario no ha autorizado la Automatización para esta app.
            // -600 / -609: la app dejó de correr entre el chequeo y la ejecución.
            if code == -1743 { return .notAuthorized }
            return nil
        }

        guard let value = result?.stringValue else { return nil }
        return .text(value)
    }

    /// Devuelve `estado|~|título|~|artista|~|álbum|~|duración|~|posición|~|clave`.
    ///
    /// Detalles que verifiqué con `osascript` contra Spotify real:
    /// - `st` y `key` son palabras reservadas de AppleScript (`st` por los ordinales
    ///   tipo "1st"); usarlas como variable es error de sintaxis, no de ejecución.
    /// - `round` falla sobre la duración de Spotify, que ya es un entero en ms y no se
    ///   deja coercer a real. `div 1` trunca y funciona en ambas apps.
    /// - Truncar en AppleScript evita de paso el separador decimal del locale.
    private var stateScript: String {
        let artworkExpression = source == .spotify
            ? "set artKey to (artwork url of theTrack)"
            : "set artKey to (persistent ID of theTrack)"

        return """
        set sep to "\(Self.separator)"
        tell application id "\(source.bundleID)"
            set theState to "stopped"
            if player state is playing then set theState to "playing"
            if player state is paused then set theState to "paused"
            if theState is "stopped" then return "stopped"

            set theTrack to current track
            set artKey to ""
            try
                \(artworkExpression)
            end try

            return theState & sep & (name of theTrack) & sep & (artist of theTrack) & sep & ¬
                (album of theTrack) & sep & (((duration of theTrack) div 1) as text) & sep & ¬
                (((player position) div 1) as text) & sep & artKey
        end tell
        """
    }
}

/// Guarda el permiso ya averiguado y hace la consulta al sistema donde no estorbe.
///
/// `AEDeterminePermissionToAutomateTarget` no admite plazo y puede no retornar jamás:
/// basta que TCC no tenga registro de la app. Le pasó a este proyecto — la primera
/// consulta del arranque dejó clavada la cola de sondeo, con lo que el reproductor no
/// se actualizó ni una vez en toda la sesión y la vista anunciaba "sin reproducción"
/// con Spotify sonando.
///
/// Por eso la consulta va en un hilo desechable y se espera un plazo corto. Sólo hay
/// una viva a la vez y sólo se repite mientras no haya respuesta: si el sistema no
/// contesta nunca, lo que se pierde es un hilo, no el módulo.
private final class PermissionCache: @unchecked Sendable {

    private let lock = NSLock()
    private var known: AutomationPermission?
    private var isProbing = false

    /// Con registro en TCC la respuesta llega en microsegundos. El margen está para no
    /// depender de que siempre sea así.
    private static let deadline: TimeInterval = 1.5

    /// Lo que se sabe ahora mismo. Mientras no haya respuesta se dice `.notAsked`, que
    /// es lo honesto: no consta permiso, y la vista ofrece el botón para pedirlo.
    var value: AutomationPermission {
        lock.withLock { known ?? .notAsked }
    }

    func set(_ permission: AutomationPermission) {
        lock.withLock { known = permission }
    }

    func forget() {
        lock.withLock { known = nil }
    }

    /// Devuelve el permiso, preguntándolo al sistema si aún no consta. Nunca retiene al
    /// llamante más allá del plazo.
    func resolve(_ probe: @escaping () -> AutomationPermission) -> AutomationPermission {
        let shouldProbe: Bool = lock.withLock {
            guard known == nil, !isProbing else { return false }
            isProbing = true
            return true
        }

        guard shouldProbe else { return value }

        let answered = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { [self] in
            let result = probe()
            lock.withLock {
                known = result
                isProbing = false
            }
            answered.signal()
        }

        _ = answered.wait(timeout: .now() + Self.deadline)
        return value
    }
}
