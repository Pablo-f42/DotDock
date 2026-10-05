import Combine
import Foundation
import SwiftUI

/// Estado que comparten todas las pantallas.
///
/// Con varios monitores hay un `DockModel` y un panel por pantalla, pero los datos
/// son uno solo: la bandeja, el portapapeles y el temporizador deben verse iguales
/// en todos, y el pomodoro no puede contar cinco veces.
@MainActor
final class DockStores: ObservableObject {

    let shelf = ShelfStore()
    let media = MediaController()
    let pomodoro = PomodoroTimer()
    let clipboard = ClipboardStore()
    let claude = ClaudeUsageStore()
    let blob = BlobSettings()

    /// Vive aquí y no en la vista para que la expresión sobreviva a cerrar y reabrir
    /// el panel, y para que sea la misma en todas las pantallas.
    @Published var calculatorInput = ""
    @Published private(set) var calculatorHistory: [CalculationEntry] = []

    static let calculatorHistoryCapacity = 3

    func start() {
        media.start()
        clipboard.start()
        claude.start()
    }

    /// Datos frescos en cuanto el panel se despliega, sin esperar al siguiente sondeo.
    /// Es también la red de seguridad si algo vuelve a estrangular los temporizadores.
    func refreshOnOpen() {
        claude.refresh()
        claude.refreshPlanIfStale()
    }

    // MARK: - Calculadora

    func recordCalculation(_ expression: String, result: String) {
        let entry = CalculationEntry(expression: expression, result: result)
        guard calculatorHistory.first != entry else { return }

        withAnimation(DockMetrics.moduleAnimation) {
            calculatorHistory.removeAll { $0 == entry }
            calculatorHistory.insert(entry, at: 0)

            if calculatorHistory.count > Self.calculatorHistoryCapacity {
                calculatorHistory.removeLast(calculatorHistory.count - Self.calculatorHistoryCapacity)
            }
        }
    }

    func clearCalculator() {
        withAnimation(DockMetrics.moduleAnimation) {
            calculatorInput = ""
            calculatorHistory.removeAll()
        }
    }
}
