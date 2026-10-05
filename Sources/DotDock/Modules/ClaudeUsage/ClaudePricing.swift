import Foundation

/// Tarifas por millón de tokens, en dólares.
///
/// Verificadas contra la documentación de Anthropic el 11 de agosto de 2026. Los
/// multiplicadores de caché son los oficiales: escribir cuesta 1,25× la entrada con
/// TTL de 5 minutos y 2× con TTL de una hora; leer cuesta 0,1×.
struct ModelPricing {

    let input: Double
    let output: Double

    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2.0 }
    var cacheRead: Double { input * 0.1 }

    /// Precio de introducción de Sonnet 5, vigente hasta el 31 de agosto de 2026.
    private static let sonnet5IntroEnd = DateComponents(
        calendar: .current, year: 2026, month: 9, day: 1
    ).date ?? .distantPast

    static func forModel(_ id: String, on date: Date = Date()) -> ModelPricing? {
        switch id {
        case "claude-fable-5", "claude-mythos-5":
            ModelPricing(input: 10, output: 50)

        case let m where m.hasPrefix("claude-opus"):
            ModelPricing(input: 5, output: 25)

        case "claude-sonnet-5":
            date < sonnet5IntroEnd
                ? ModelPricing(input: 2, output: 10)
                : ModelPricing(input: 3, output: 15)

        case let m where m.hasPrefix("claude-sonnet"):
            ModelPricing(input: 3, output: 15)

        case let m where m.hasPrefix("claude-haiku"):
            ModelPricing(input: 1, output: 5)

        default:
            // `<synthetic>` y modelos desconocidos: se cuentan los tokens pero no
            // se inventa un precio.
            nil
        }
    }

    /// Nombre corto para la interfaz. El identificador completo no cabe.
    static func shortName(_ id: String) -> String {
        id
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
