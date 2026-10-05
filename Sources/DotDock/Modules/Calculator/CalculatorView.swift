import AppKit
import SwiftUI

struct CalculatorView: View {

    @ObservedObject var stores: DockStores

    @FocusState private var isFocused: Bool
    @State private var justCopied = false

    private var result: Double? {
        ExpressionParser.evaluate(stores.calculatorInput)
    }

    private var isIncomplete: Bool {
        result == nil && !stores.calculatorInput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            toolbar
            input
            resultRow

            if !stores.calculatorHistory.isEmpty {
                Divider().overlay(Theme.Line.hairline)
                history
            }

        }
        .frame(width: 300, alignment: .topLeading)
        .onAppear { isFocused = true }
        .onChange(of: stores.calculatorInput) { justCopied = false }
    }

    // MARK: - Partes

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("+ − × ÷ % ^ ( )")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.faint)

            Spacer(minLength: 0)

            // Botón explícito además de ⌘V: el panel no siempre tiene el foco del
            // teclado, y aquí el pegado es la entrada más común.
            if pasteboardNumber != nil {
                CompactButton(title: "Pegar", symbol: "doc.on.clipboard", action: paste)
            }

            if !stores.calculatorInput.isEmpty || !stores.calculatorHistory.isEmpty {
                CompactButton(title: "Limpiar", symbol: "trash", action: stores.clearCalculator)
            }
        }
    }

    private var input: some View {
        TextField("2 + 2 × 8", text: $stores.calculatorInput)
            .textFieldStyle(.plain)
            .font(Theme.Typo.display(19, weight: .light))
            .foregroundStyle(Theme.Ink.primary)
            .focused($isFocused)
            .onSubmit(commit)
    }

    private var resultRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // El "=" ancla la lectura: deja claro que la línea de abajo es el
            // resultado y no otra entrada.
            Text("=")
                .font(Theme.Typo.display(19, weight: .light))
                .foregroundStyle(Theme.Ink.faint)

            Text(displayResult)
                .font(Theme.Typo.display(25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isIncomplete ? Theme.Ink.faint : Theme.Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            Spacer(minLength: 0)

            if result != nil {
                CompactButton(
                    title: justCopied ? "Copiado" : "Guardar",
                    symbol: justCopied ? "checkmark" : "return",
                    action: commit
                )
            }
        }
    }

    private var history: some View {
        VStack(spacing: 3) {
            ForEach(stores.calculatorHistory) { entry in
                HistoryRow(entry: entry) { reuse(entry) }
            }
        }
    }

    // MARK: - Acciones

    private var displayResult: String {
        guard let result else {
            return stores.calculatorInput.isEmpty ? "0" : "…"
        }
        return Self.format(result)
    }

    /// Guarda en el historial y deja el resultado en el portapapeles, todo con Enter.
    private func commit() {
        guard let result else { return }
        let formatted = Self.format(result)

        stores.recordCalculation(stores.calculatorInput, result: formatted)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        justCopied = true
    }

    /// Encadena cuentas: el resultado elegido entra donde estaba el cursor lógico, al
    /// final de lo escrito.
    private func reuse(_ entry: CalculationEntry) {
        stores.calculatorInput += entry.result
        isFocused = true
    }

    private func paste() {
        guard let number = pasteboardNumber else { return }
        stores.calculatorInput += number
        isFocused = true
    }

    /// Sólo ofrecemos pegar si lo copiado sirve como operando: pegar un párrafo en una
    /// calculadora no ayuda a nadie.
    private var pasteboardNumber: String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }

        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: " ", with: "")

        guard !cleaned.isEmpty, cleaned.count <= 24 else { return nil }
        guard cleaned.allSatisfy({ $0.isNumber || "+-*/^%().".contains($0) }) else { return nil }

        return cleaned
    }

    /// Enteros sin decimales; el resto con hasta 8 cifras y sin ceros de relleno.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(format: "%.0f", value)
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = false

        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private struct HistoryRow: View {

    let entry: CalculationEntry
    let onReuse: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onReuse) {
            HStack(spacing: 6) {
                Text(entry.expression)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Text("=")
                    .foregroundStyle(Theme.Ink.faint)

                Text(entry.result)
                    .foregroundStyle(isHovering ? Theme.Ink.primary : Theme.Ink.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isHovering {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(isHovering ? Theme.Fill.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Usar \(entry.result) en la cuenta actual")
        .onHover { isHovering = $0 }
    }
}

private struct CompactButton: View {

    let title: String
    let symbol: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(Theme.Typo.caption)
            .foregroundStyle(isHovering ? Theme.Ink.primary : Theme.Ink.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isHovering ? Theme.Fill.hover : Theme.Fill.raised)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
