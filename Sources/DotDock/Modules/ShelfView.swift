import SwiftUI

struct ShelfView: View {

    @ObservedObject var store: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sin título: la pestaña activa ya dice en qué módulo estás.
            if !store.items.isEmpty {
                HStack {
                    Text("Arrastra fuera para usarlos")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Ink.faint)

                    Spacer(minLength: 0)

                    Button("Vaciar", action: store.removeAll)
                        .buttonStyle(.plain)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }

            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.items) { item in
                            ShelfItemView(
                                item: item,
                                onRemove: { store.remove(item) },
                                onOpen: { store.open(item) },
                                onReveal: { store.reveal(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
        // Sin `.onDrop`: el arrastre lo maneja `DockHostingView` en AppKit, porque
        // SwiftUI no llega a verlo con el panel cerrado. `isTargeted` lo alimenta esa
        // misma vista.
        .frame(width: 420, alignment: .topLeading)
        // El disco se toca aquí y no al arrancar: abrir la bandeja es la acción del
        // usuario que justifica pedir acceso, si la carpeta resulta estar protegida.
        .onAppear(perform: store.validate)
    }

    private var emptyState: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(store.isTargeted ? Theme.Fill.hover : Theme.Fill.raised)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(
                        store.isTargeted ? Theme.Ink.secondary : Theme.Line.hairline,
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            }
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: store.isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 17))
                        .foregroundStyle(store.isTargeted ? Theme.Ink.primary : Theme.Ink.faint)

                    Text(store.isTargeted ? "Suelta aquí" : "Arrastra archivos aquí")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }
            .frame(height: 76)
            .animation(DockMetrics.closeAnimation, value: store.isTargeted)
    }
}

private struct ShelfItemView: View {

    let item: ShelfItem
    let onRemove: () -> Void
    let onOpen: () -> Void
    let onReveal: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 38, height: 38)

            Text(item.name)
                .font(Theme.Typo.caption)
                .foregroundStyle(isHovering ? Theme.Ink.primary : Theme.Ink.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 66)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(isHovering ? Theme.Fill.hover : .clear)
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Ink.secondary)
                        .background(Circle().fill(.black))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
            }
        }
        .help(item.url.path)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2, perform: onOpen)
        .contextMenu {
            Button("Abrir", action: onOpen)
            Button("Mostrar en Finder", action: onReveal)
            Divider()
            Button("Quitar de la bandeja", action: onRemove)
        }
    }
}
