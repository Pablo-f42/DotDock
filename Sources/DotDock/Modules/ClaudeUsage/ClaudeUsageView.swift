import SwiftUI

struct ClaudeUsageView: View {

    @ObservedObject var store: ClaudeUsageStore

    var body: some View {
        if !store.isAvailable {
            message(icon: "questionmark.folder",
                    title: "Sin datos de Claude Code",
                    detail: "No se encontró ~/.claude/projects")
        } else if !store.hasPlanData, let issue = store.planIssue {
            // Decir por qué falta el dato y qué hacer. Antes cualquier fallo se
            // anunciaba como "CLI de Claude no encontrado", que casi nunca era cierto
            // y mandaba a reinstalar algo que ya estaba instalado.
            message(icon: Self.icon(issue), title: Self.title(issue), detail: Self.detail(issue))
        } else if store.session.tokens == 0 && store.week.tokens == 0 {
            message(icon: "sparkles",
                    title: "Sin uso esta semana",
                    detail: "Aquí aparece tu consumo por ventana")
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            WindowRow(title: "Sesión actual", window: store.session)
            WindowRow(title: "Semana", window: store.week)

            footer
        }
        .frame(width: 420, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(store.hasPlanData ? "Plan Claude Code" : Self.title(store.planIssue))
                .foregroundStyle(Theme.Ink.faint)

            Spacer(minLength: 0)

            if let top = store.models.first {
                Text(ModelPricing.shortName(top.model))
                    .foregroundStyle(Theme.Ink.faint)
            }

            Text(Self.money(store.session.cost))
                .foregroundStyle(Theme.Ink.tertiary)
                .monospacedDigit()
        }
        .font(Theme.Typo.caption)
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.Ink.faint)

            Text(title)
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.Ink.secondary)

            Text(detail)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(width: 420, height: 100)
    }

    // MARK: - Diagnóstico

    static func icon(_ issue: PlanRead?) -> String {
        switch issue {
        case .notInstalled: "questionmark.app.dashed"
        case .unreadable: "person.crop.circle.badge.exclamationmark"
        default: "exclamationmark.triangle"
        }
    }

    static func title(_ issue: PlanRead?) -> String {
        switch issue {
        case .notInstalled: "Claude Code no está instalado"
        case .unreadable: "Sesión de Claude Code cerrada"
        case .failed: "No se pudo consultar el uso"
        case .ok, nil: "Consultando el uso…"
        }
    }

    static func detail(_ issue: PlanRead?) -> String {
        switch issue {
        case .notInstalled: "Este módulo necesita el CLI de Claude Code"
        case .unreadable: "Abre Claude Code y ejecuta /login"
        case .failed: "Reintentando en unos segundos"
        case .ok, nil: "Un momento"
        }
    }

    // MARK: - Formato

    static func money(_ value: Double) -> String {
        value < 10 ? String(format: "$%.2f", value) : String(format: "$%.1f", value)
    }

    static func compact(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...: String(format: "%.1fM", Double(tokens) / 1_000_000)
        case 1_000...: String(format: "%.0fk", Double(tokens) / 1_000)
        default: "\(tokens)"
        }
    }
}

private struct WindowRow: View {

    let title: String
    let window: UsageWindow

    /// Sin calibración la barra no puede representar un porcentaje, así que se dibuja
    /// como progreso de la propia ventana en el tiempo — no como consumo.
    private var fill: Double {
        guard let percent = window.percent else { return 0 }
        return min(max(percent / 100, 0), 1)
    }

    private var tint: Color {
        guard let percent = window.percent else { return Theme.Ink.secondary }
        return switch percent {
        case ..<75: Theme.Ink.primary
        case ..<90: .orange
        default: .red
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.Ink.primary)

                if let remaining = window.resetLabel {
                    Text("Se restablece \(remaining)")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }
            .frame(width: 132, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Fill.raised)

                    if window.percent != nil {
                        Capsule()
                            .fill(tint)
                            .frame(width: max(3, geo.size.width * fill))
                    }
                }
            }
            .frame(height: 8)

            VStack(alignment: .trailing, spacing: 1) {
                if let percent = window.percent {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Ink.faint)
                }

                Text(ClaudeUsageView.compact(window.tokens))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            .monospacedDigit()
            .frame(width: 54, alignment: .trailing)
        }
    }
}
