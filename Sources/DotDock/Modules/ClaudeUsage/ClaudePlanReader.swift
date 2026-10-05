import Foundation

/// Lo que informa el propio Claude Code sobre los límites del plan.
struct PlanStatus: Equatable {
    var sessionPercent: Int
    var sessionReset: Date?
    var sessionResetText: String

    var weekPercent: Int
    var weekReset: Date?
    var weekResetText: String
}

/// Por qué no hay porcentajes. Cada caso pide una acción distinta del usuario, así
/// que la vista necesita distinguirlos en vez de enseñar un mensaje único y falso.
enum PlanRead {
    case ok(PlanStatus)
    /// No existe el ejecutable `claude` en ninguna ruta conocida.
    case notInstalled
    /// El CLI respondió pero sin el informe de uso. En la práctica significa que la
    /// sesión de Claude Code está cerrada: al no estar autenticado imprime el pie de
    /// coste en vez de los límites del plan.
    case unreadable
    /// No se pudo lanzar el proceso, o se colgó y lo mató el vigilante.
    case failed
}

/// Lee los límites reales ejecutando `claude -p "/usage"`.
///
/// Es el equivalente del diccionario de AppleScript de Spotify: una interfaz local y
/// soportada del propio programa, en vez de leer credenciales del llavero o golpear
/// endpoints no documentados. Los porcentajes vienen del servidor de Anthropic, así
/// que son los mismos que muestra `/usage` — no una estimación nuestra.
///
/// Comprobado antes de construir sobre ello: la consulta tarda ~2 s y **no** aumenta
/// el contador de peticiones, así que sondear no consume la cuota del usuario.
enum ClaudePlanReader {

    /// Rutas donde suele quedar el ejecutable. Una app lanzada desde el Finder no
    /// hereda el `PATH` de la terminal, así que buscarlo a mano es obligatorio.
    private static let candidates = [
        "\(NSHomeDirectory())/.local/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        "\(NSHomeDirectory())/.claude/local/claude"
    ]

    static var executable: URL? {
        candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map(URL.init(fileURLWithPath:))
    }

    /// Directorio de trabajo del subproceso.
    ///
    /// Cada `claude -p` deja un transcript en `~/.claude/projects/<cwd con las barras
    /// convertidas en guiones>`. Heredando el directorio del Finder —que es `/`— esos
    /// ficheros caían en la misma carpeta que las sesiones reales del usuario, y el
    /// escaneo de este módulo acababa releyendo su propia basura: 4.300 transcripts de
    /// sondeo en nueve días, y subiendo. Con un directorio propio quedan agrupados,
    /// se ignoran al escanear y se pueden podar.
    static let workingDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/DotDock/usage", isDirectory: true)

    /// Carpeta donde Claude Code deja los transcripts de nuestros sondeos.
    static var transcriptDirectory: URL {
        let encoded = workingDirectory.path.replacingOccurrences(of: "/", with: "-")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/\(encoded)", isDirectory: true)
    }

    /// Borra los transcripts que dejaron los sondeos anteriores.
    ///
    /// Sólo toca la carpeta que genera este módulo, y sólo lo ya asentado: el del
    /// sondeo en curso queda fuera por edad.
    static func pruneTranscripts(olderThan age: TimeInterval = 3600) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: transcriptDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-age)

        for file in files where file.pathExtension == "jsonl" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantFuture
            guard modified < cutoff else { continue }
            try? manager.removeItem(at: file)
        }
    }

    /// Ejecuta la consulta. Bloquea: llamar fuera del hilo principal.
    static func read(timeout: TimeInterval = 20) -> PlanRead {
        guard let executable else { return .notInstalled }

        try? FileManager.default.createDirectory(
            at: workingDirectory, withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-p", "/usage"]
        process.environment = environment
        process.currentDirectoryURL = workingDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        // Sin esto el CLI espera datos por la entrada estándar y pierde 3 segundos.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failed
        }

        // `readDataToEndOfFile` no admite plazo: si el CLI se cuelga, esta llamada se
        // queda bloqueada para siempre. El vigilante lo mata, con lo que se cierra el
        // pipe y la lectura retorna.
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Leer antes de esperar: si la salida llena el pipe, el proceso se bloquea.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()

        guard let output = String(data: data, encoding: .utf8) else { return .failed }
        guard let status = parse(output) else { return .unreadable }
        return .ok(status)
    }

    /// El CLI necesita `USER`: sin esa variable no imprime el informe de uso, imprime
    /// el pie de coste — el mismo síntoma que tener la sesión cerrada. Comprobado
    /// bisecando el entorno con `env -i`. Una app lanzada desde el Finder hoy la
    /// hereda, pero no depende de nosotros que siga siendo así.
    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["USER"] == nil { env["USER"] = NSUserName() }
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }
        if env["PATH"] == nil { env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin" }
        return env
    }

    // MARK: - Análisis de la salida

    /// Formato esperado:
    ///
    ///     Current session: 81% used · resets Aug 11 at 3:09pm (America/Monterrey)
    ///     Current week (all models): 65% used · resets Aug 16 at 1:59am (America/Monterrey)
    static func parse(_ output: String) -> PlanStatus? {
        guard
            let session = match(output, prefix: "Current session"),
            let week = match(output, prefix: "Current week")
        else { return nil }

        return PlanStatus(
            sessionPercent: session.percent,
            sessionReset: session.reset,
            sessionResetText: session.resetText,
            weekPercent: week.percent,
            weekReset: week.reset,
            weekResetText: week.resetText
        )
    }

    private static func match(
        _ output: String,
        prefix: String
    ) -> (percent: Int, reset: Date?, resetText: String)? {

        guard let line = output
            .split(separator: "\n")
            .first(where: { $0.hasPrefix(prefix) })
        else { return nil }

        let text = String(line)

        guard
            let percentRange = text.range(of: #"(\d+)% used"#, options: .regularExpression),
            let percent = Int(text[percentRange].prefix { $0.isNumber })
        else { return nil }

        var resetText = ""
        var reset: Date?

        if let resetRange = text.range(of: #"resets [^(]+"#, options: .regularExpression) {
            resetText = text[resetRange]
                .replacingOccurrences(of: "resets ", with: "")
                .trimmingCharacters(in: .whitespaces)

            let zone = text.range(of: #"\(([^)]+)\)"#, options: .regularExpression)
                .map { String(text[$0].dropFirst().dropLast()) }

            reset = date(from: resetText, zone: zone)
        }

        return (percent, reset, resetText)
    }

    /// Convierte `"Aug 11 at 3:09pm"` en fecha. El CLI omite el año y a veces los
    /// minutos en punto (`"2am"`), así que hay que probar varios formatos.
    private static func date(from text: String, zone: String?) -> Date? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? .current

        for format in ["MMM d 'at' h:mma yyyy", "MMM d 'at' ha yyyy"] {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: "\(text) \(year)") {
                // Cerca de fin de año el reinicio puede caer en el siguiente.
                if parsed.timeIntervalSinceNow < -30 * 24 * 3600,
                   let next = formatter.date(from: "\(text) \(year + 1)") {
                    return next
                }
                return parsed
            }
        }

        return nil
    }
}
