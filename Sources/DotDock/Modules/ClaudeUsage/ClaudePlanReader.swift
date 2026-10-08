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
    /// El CLI arrancó y terminó con error sin llegar a responder. El caso típico es
    /// una instalación con npm cuyo `node` no se encuentra. Lleva el mensaje real.
    case cannotRun(String)
    /// El CLI pide iniciar sesión.
    case loggedOut
    /// El CLI respondió pero sin el informe de uso. Lleva la primera línea de lo que
    /// dijo, para no tener que adivinar.
    case unreadable(String)
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

    /// Rutas donde suelen dejarlo los distintos instaladores. Una app lanzada desde
    /// el Finder no hereda el `PATH` de la terminal, así que buscarlo a mano es
    /// obligatorio.
    private static var candidates: [String] {
        let home = NSHomeDirectory()
        let fixed = [
            "\(home)/.local/bin/claude",           // instalador nativo
            "\(home)/.claude/local/claude",        // instalación local antigua
            "/opt/homebrew/bin/claude",            // Homebrew, o npm con Node de Homebrew
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.volta/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/Library/pnpm/claude",
            "\(home)/.local/share/pnpm/claude",
            "\(home)/.asdf/shims/claude",
            "\(home)/.local/share/mise/shims/claude"
        ]

        // nvm guarda una carpeta por versión de Node: se prueba de la más nueva a la
        // más vieja.
        let nvm = "\(home)/.nvm/versions/node"
        let versions = (try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []
        let nvmBins = versions
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "\(nvm)/\($0)/bin/claude" }

        return fixed + nvmBins
    }

    /// Primero lo que diga la shell del usuario, que conoce su instalación exacta;
    /// si no responde, las rutas habituales.
    static var executable: URL? {
        let fromShell = LoginShell.lookup.claude.map { [$0] } ?? []
        return (fromShell + candidates)
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

        // Errores y salida van juntos: si el CLI no llega a arrancar, el motivo sale
        // por stderr y sin él sólo se vería un silencio.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
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
        if let status = parse(output) { return .ok(status) }
        return diagnose(output, exitCode: process.terminationStatus)
    }

    /// Explica por qué no hubo informe, a partir de lo que dijo el CLI.
    private static func diagnose(_ output: String, exitCode: Int32) -> PlanRead {
        let lines = output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let firstLine = String((lines.first ?? "Sin respuesta").prefix(140))
        let lowered = output.lowercased()

        if lowered.contains("/login") || lowered.contains("not logged in")
            || lowered.contains("please log in") || lowered.contains("invalid api key") {
            return .loggedOut
        }

        // 126/127: el sistema no pudo ejecutarlo, típicamente `env: node: No such
        // file or directory` en instalaciones con npm.
        if exitCode == 126 || exitCode == 127 || lowered.contains("no such file") {
            return .cannotRun(firstLine)
        }

        return .unreadable(firstLine)
    }

    /// El CLI necesita `USER`: sin esa variable no imprime el informe de uso, imprime
    /// el pie de coste — el mismo síntoma que tener la sesión cerrada. Comprobado
    /// bisecando el entorno con `env -i`. Una app lanzada desde el Finder hoy la
    /// hereda, pero no depende de nosotros que siga siendo así.
    ///
    /// El `PATH` sale de la shell del usuario. Con el de una app del Finder
    /// (`/usr/bin:/bin:…`) un `claude` instalado con npm no encuentra `node`, termina
    /// con `env: node: No such file or directory` y parecía una sesión cerrada.
    private static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["USER"] == nil { env["USER"] = NSUserName() }
        if env["HOME"] == nil { env["HOME"] = NSHomeDirectory() }

        var directories: [String] = []

        // La carpeta del propio `claude` (y la real, si es un enlace) va primero: con
        // nvm, `node` vive justo al lado.
        if let executable {
            directories.append(executable.deletingLastPathComponent().path)
            directories.append(executable.resolvingSymlinksInPath().deletingLastPathComponent().path)
        }

        let shellPath = LoginShell.lookup.path ?? env["PATH"] ?? ""
        directories += shellPath.split(separator: ":").map(String.init)
        directories += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

        var seen = Set<String>()
        env["PATH"] = directories.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        return env
    }

    // MARK: - La shell del usuario

    /// Lo que sabe la shell de inicio del usuario: su `PATH` completo y dónde está
    /// `claude`. Se pregunta una sola vez, porque abrir una shell interactiva cuesta.
    private enum LoginShell {

        static let lookup: (path: String?, claude: String?) = ask()

        private static func ask() -> (path: String?, claude: String?) {
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let marker = "__DOTDOCK__"

            // Interactiva y de inicio, para que cargue lo mismo que la Terminal (nvm
            // suele configurarse en `.zshrc`). Las marcas aíslan la respuesta de lo
            // que impriman los archivos de configuración.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            process.arguments = [
                "-ilc",
                "printf '\(marker)%s\(marker)%s\(marker)' \"$PATH\" \"$(command -v claude)\""
            ]
            process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return (nil, nil)
            }

            let watchdog = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()

            let parts = (String(data: data, encoding: .utf8) ?? "").components(separatedBy: marker)
            guard parts.count >= 4 else { return (nil, nil) }

            let path = parts[1].isEmpty ? nil : parts[1]
            // `command -v` devuelve la definición si `claude` es un alias o una
            // función; sólo sirve si es una ruta.
            let claude = parts[2].hasPrefix("/") ? parts[2] : nil
            return (path, claude)
        }
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
