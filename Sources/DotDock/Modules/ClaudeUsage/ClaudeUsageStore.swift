import Foundation
import SwiftUI

/// Una respuesta del asistente, reducida a lo que hace falta para agregar.
struct UsageSample {
    let date: Date
    let model: String
    let tokens: Int
    let cost: Double
}

/// Una ventana de consumo con su reinicio.
struct UsageWindow {
    var tokens: Int = 0
    var cost: Double = 0
    var resetAt: Date?

    /// Reinicio informado por el plan. Manda sobre el calculado en local.
    var planReset: Date?

    /// Porcentaje real del plan, informado por `claude -p "/usage"`. `nil` si el
    /// CLI no está disponible: no se estima con datos locales.
    var percent: Double?

    /// Cuenta atrás. Para esperas largas se dice el día y la hora, que se lee mejor
    /// que "109 h 43 min".
    var resetLabel: String? {
        guard let resetAt = planReset ?? resetAt else { return nil }
        let seconds = Int(resetAt.timeIntervalSinceNow)
        guard seconds > 0 else { return nil }

        if seconds >= 24 * 3600 {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
            return formatter.string(from: resetAt)
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "en \(hours) h \(minutes) min" : "en \(minutes) min"
    }
}

/// Uso de Claude Code leído de los transcripts locales.
///
/// Combina dos fuentes:
///
/// - **Porcentajes y reinicios** salen de `claude -p "/usage"` — el dato real del
///   servidor, el mismo que ves en la sesión interactiva. Se consulta cada pocos
///   minutos porque cuesta ~2 s y no gasta cuota.
/// - **Tokens, coste y modelos** salen de los transcripts locales, que se refrescan
///   cada 20 s y dan el detalle que el CLI no reporta.
@MainActor
final class ClaudeUsageStore: ObservableObject {

    @Published private(set) var session = UsageWindow()
    @Published private(set) var week = UsageWindow()
    @Published private(set) var models: [ModelUsage] = []
    @Published private(set) var isAvailable = true

    /// `false` si no se encontró el ejecutable `claude`: se sigue mostrando el
    /// consumo local, pero sin porcentajes.
    @Published private(set) var hasPlanData = false

    /// Por qué faltan los porcentajes. `nil` mientras no haya fallado nada.
    @Published private(set) var planIssue: PlanRead?

    /// Duración de la ventana de sesión del plan.
    nonisolated static let sessionWindow: TimeInterval = 5 * 3600

    /// Día y hora en que reinicia el contador semanal (domingo a las 2:00, hora local).
    nonisolated static let weeklyResetWeekday = 1
    nonisolated static let weeklyResetHour = 2

    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    private struct FileCache {
        let modified: Date
        let horizon: String
        let samples: [UsageSample]
    }

    private var cache: [String: FileCache] = [:]
    private var timer: Timer?
    private var planTimer: Timer?
    private var plan: PlanStatus?
    private var samples: [UsageSample] = []
    private var lastPlanRead = Date.distantPast
    private var isReadingPlan = false
    private var planFailures = 0

    private static let refreshInterval: TimeInterval = 20
    private static let planInterval: TimeInterval = 180

    // MARK: - Ciclo de vida

    func start() {
        guard timer == nil else { return }

        refresh()
        refreshPlan()

        timer = Timer.repeatingOnCommonModes(every: Self.refreshInterval) { [weak self] in
            self?.refresh()
        }
        // El CLI es más caro que leer archivos, así que va en su propio ritmo.
        planTimer = Timer.repeatingOnCommonModes(every: Self.planInterval) { [weak self] in
            self?.refreshPlan()
        }
    }

    /// Consulta el plan sólo si el dato ya envejeció, para que abrir el panel muchas
    /// veces seguidas no dispare un proceso por cada apertura.
    func refreshPlanIfStale(maxAge: TimeInterval = 60) {
        guard -lastPlanRead.timeIntervalSinceNow > maxAge else { return }
        refreshPlan()
    }

    /// Consulta los porcentajes reales al CLI de Claude Code.
    func refreshPlan() {
        // Si la consulta anterior sigue viva, no encolamos otra encima: el CLI tarda
        // ~2 s pero puede atascarse, y sin esta guarda se acumularían procesos.
        guard !isReadingPlan else { return }
        isReadingPlan = true

        Task.detached(priority: .utility) {
            let result = ClaudePlanReader.read()
            ClaudePlanReader.pruneTranscripts()
            await MainActor.run { self.applyPlan(result) }
        }
    }

    private func applyPlan(_ result: PlanRead) {
        isReadingPlan = false

        // Una lectura fallida NO borra el último dato bueno. Antes sí lo hacía, y
        // bastaba un fallo puntual para dejar el panel en "—" durante tres minutos,
        // o indefinidamente si los fallos se encadenaban.
        guard case .ok(let status) = result else {
            planIssue = result
            scheduleRetry()
            return
        }

        planIssue = nil
        planFailures = 0
        lastPlanRead = Date()
        plan = status
        hasPlanData = true

        recompute()
    }

    /// Tras un fallo no se espera el ciclo completo de tres minutos: un arranque con
    /// la sesión cerrada dejaba el módulo en blanco, y al reabrir sesión el usuario
    /// seguía viendo el hueco. Reintenta pronto y va cediendo hasta el ritmo normal.
    private func scheduleRetry() {
        planFailures += 1
        let delay = min(Self.planInterval, 15 * pow(2, Double(planFailures - 1)))
        guard delay < Self.planInterval else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.refreshPlan() }
        }
    }

    /// Antigüedad del último dato bueno del plan. La vista la usa para avisar cuando
    /// lo mostrado dejó de ser fiable en vez de fingir que está al día.
    var planAge: TimeInterval? {
        hasPlanData ? -lastPlanRead.timeIntervalSinceNow : nil
    }

    func stop() {
        timer?.invalidate()
        planTimer?.invalidate()
        timer = nil
        planTimer = nil
    }

    // MARK: - Lectura

    func refresh() {
        let horizon = Self.horizonStamps()
        let root = self.root
        let cached = cache

        Task.detached(priority: .utility) {
            let result = Self.scan(root: root, horizon: horizon, cache: cached)

            await MainActor.run {
                self.cache = result.cache
                self.apply(result.samples, available: result.available)
            }
        }
    }

    private func apply(_ samples: [UsageSample], available: Bool) {
        isAvailable = available
        self.samples = samples.sorted { $0.date < $1.date }
        recompute()
    }

    /// Reparte los tokens en las ventanas **que informa el plan**.
    ///
    /// Antes cada ventana se calculaba aquí con reglas propias — bloques de 5 h
    /// alineados a la hora en punto — y el resultado no cuadraba con el porcentaje:
    /// el panel llegó a mostrar "0 %" junto a "48,2M tokens" porque el bloque local
    /// empezaba 39 minutos antes que la ventana real. El reinicio que da el CLI es
    /// el dato autoritativo, así que las ventanas se derivan de él.
    private func recompute() {
        var newSession = UsageWindow()
        var newWeek = UsageWindow()

        if let plan {
            newSession.percent = Double(plan.sessionPercent)
            newSession.planReset = plan.sessionReset
            newWeek.percent = Double(plan.weekPercent)
            newWeek.planReset = plan.weekReset

            if let reset = plan.sessionReset {
                accumulate(from: reset.addingTimeInterval(-Self.sessionWindow), into: &newSession)
            }
            if let reset = plan.weekReset {
                accumulate(from: reset.addingTimeInterval(-7 * 24 * 3600), into: &newWeek)
            }
        }

        var byModel: [String: ModelUsage] = [:]
        if let reset = plan?.sessionReset {
            let start = reset.addingTimeInterval(-Self.sessionWindow)
            for sample in samples where sample.date >= start {
                byModel[sample.model, default: ModelUsage(model: sample.model)]
                    .add(tokens: sample.tokens, cost: sample.cost)
            }
        }

        withAnimation(DockMetrics.moduleAnimation) {
            session = newSession
            week = newWeek
            models = byModel.values.sorted { $0.tokens > $1.tokens }
        }
    }

    private func accumulate(from start: Date, into window: inout UsageWindow) {
        for sample in samples where sample.date >= start {
            window.tokens += sample.tokens
            window.cost += sample.cost
        }
    }

    // MARK: - Análisis

    /// Fechas UTC que hay que mirar: ocho días cubren la semana más el desfase horario.
    private nonisolated static func horizonStamps() -> Set<String> {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"

        return Set((0...8).compactMap { offset in
            Calendar.current.date(byAdding: .day, value: -offset, to: Date())
                .map(formatter.string(from:))
        })
    }

    private nonisolated static func scan(
        root: URL,
        horizon: Set<String>,
        cache: [String: FileCache]
    ) -> (samples: [UsageSample], cache: [String: FileCache], available: Bool) {

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], [:], false)
        }

        let key = horizon.sorted().joined()
        var fresh: [String: FileCache] = [:]
        var all: [UsageSample] = []

        // Los transcripts que deja nuestro propio sondeo del plan no son uso del
        // usuario: contarlos inflaría la cifra, y releerlos cada 20 s era trabajo que
        // sólo podía crecer.
        let ownFolder = ClaudePlanReader.transcriptDirectory.lastPathComponent

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard url.deletingLastPathComponent().lastPathComponent != ownFolder else { continue }

            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast

            let entry: FileCache
            if let hit = cache[url.path], hit.modified == modified, hit.horizon == key {
                entry = hit
            } else {
                entry = FileCache(modified: modified, horizon: key, samples: parse(url, horizon: horizon))
            }

            fresh[url.path] = entry
            all.append(contentsOf: entry.samples)
        }

        return (all, fresh, true)
    }

    private nonisolated static func parse(_ url: URL, horizon: Set<String>) -> [UsageSample] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        let stamps = horizon.map { "\"timestamp\":\"\($0)" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var result: [UsageSample] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            // Filtrar por fecha antes de parsear JSON es lo que hace viable recorrer
            // 70 MB en cada refresco.
            guard line.contains("\"type\":\"assistant\""),
                  stamps.contains(where: line.contains)
            else { continue }

            guard
                let data = line.data(using: .utf8),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let stamp = root["timestamp"] as? String,
                let date = iso.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp),
                let message = root["message"] as? [String: Any],
                let model = message["model"] as? String,
                let usage = message["usage"] as? [String: Any]
            else { continue }

            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0

            let creation = usage["cache_creation"] as? [String: Any]
            let write1h = creation?["ephemeral_1h_input_tokens"] as? Int ?? 0
            let write5m = creation?["ephemeral_5m_input_tokens"] as? Int ?? max(0, cacheWrite - write1h)

            var cost = 0.0
            if let price = ModelPricing.forModel(model) {
                let m = 1_000_000.0
                cost = Double(input) / m * price.input
                    + Double(output) / m * price.output
                    + Double(write5m) / m * price.cacheWrite5m
                    + Double(write1h) / m * price.cacheWrite1h
                    + Double(cacheRead) / m * price.cacheRead
            }

            result.append(UsageSample(
                date: date,
                model: model,
                tokens: input + output + cacheWrite + cacheRead,
                cost: cost
            ))
        }

        return result
    }
}

struct ModelUsage: Identifiable, Equatable {
    let model: String
    var tokens: Int = 0
    var cost: Double = 0

    var id: String { model }

    mutating func add(tokens: Int, cost: Double) {
        self.tokens += tokens
        self.cost += cost
    }
}
