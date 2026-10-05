import SwiftUI

struct ClipboardView: View {

    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.entries.isEmpty {
                emptyState
            } else {
                header

                VStack(spacing: 3) {
                    ForEach(store.entries) { entry in
                        ClipboardRow(
                            entry: entry,
                            onCopy: { store.copy(entry) },
                            onRemove: { store.remove(entry) }
                        )
                    }
                }
            }
        }
        .frame(width: 400, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Text("Clic para copiar · no se guarda en disco")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.faint)

            Spacer(minLength: 0)

            Button("Borrar", action: store.clear)
                .buttonStyle(.plain)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Ink.faint)

            Text("Sin copias todavía")
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.Ink.secondary)

            Text("Copia texto en cualquier app y aparecerá aquí")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(width: 400, height: 120)
    }
}

private struct ClipboardRow: View {

    let entry: ClipboardEntry
    let onCopy: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @State private var justCopied = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 8) {
                Image(systemName: justCopied ? "checkmark" : "text.alignleft")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(justCopied ? Theme.Ink.primary : Theme.Ink.faint)
                    .frame(width: 12)

                Text(entry.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(isHovering ? Theme.Ink.primary : Theme.Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if entry.lineCount > 1 {
                    Text("\(entry.lineCount) líneas")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Ink.faint)
                }

                if isHovering {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.Ink.tertiary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Quitar del historial")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(isHovering ? Theme.Fill.hover : Theme.Fill.raised)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.text)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private func copy() {
        onCopy()
        justCopied = true

        // El destello confirma la acción; la fila se queda arriba de todas formas.
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            justCopied = false
        }
    }
}
