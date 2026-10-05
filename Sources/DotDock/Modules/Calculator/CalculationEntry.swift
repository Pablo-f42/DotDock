import Foundation

/// Una operación ya resuelta, guardada para reutilizar su resultado.
struct CalculationEntry: Identifiable, Equatable {
    let id = UUID()
    let expression: String
    let result: String

    /// La identidad es el contenido, no el `id`: repetir la misma cuenta debe subirla
    /// en el historial, no duplicarla.
    static func == (lhs: CalculationEntry, rhs: CalculationEntry) -> Bool {
        lhs.expression == rhs.expression && lhs.result == rhs.result
    }
}
