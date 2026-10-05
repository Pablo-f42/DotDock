import SwiftUI

/// Reproductor: carátula a la izquierda, metadatos y transporte a la derecha.
struct PlayerView: View {

    @ObservedObject var media: MediaController

    var body: some View {
        if let track = media.nowPlaying {
            content(track)
        } else {
            placeholder
        }
    }

    // MARK: - Con reproducción

    private func content(_ track: NowPlaying) -> some View {
        HStack(alignment: .top, spacing: 14) {
            artwork(track)

            VStack(alignment: .leading, spacing: 1) {
                // Dos líneas: los títulos largos con remix o subtítulo se cortaban
                // justo donde estaba la información que los distingue.
                Text(track.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(track.artist)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(1)

                if Self.showsAlbum(track) {
                    Text(track.album)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                        .lineLimit(1)
                }

                // Separación fija, no `Spacer`: un espaciador flexible estiraba la
                // columna hasta llenar el panel, y como la altura del panel sale de
                // medir el contenido, se quedaba con la del módulo anterior.
                Color.clear.frame(height: 6)

                // Controles arriba y progreso debajo: en una sola fila competían por
                // el ancho y la barra quedaba raquítica.
                controls(isPlaying: track.isPlaying)

                HStack(spacing: 8) {
                    Text(Self.time(track.position))
                    ProgressBar(progress: track.progress)
                    Text(Self.time(track.duration))
                }
                .font(Theme.Typo.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.top, 4)
            }
            // Ancho fijo en vez de elástico: es lo que decide el ancho del panel, y
            // también lo que impedía que la barra de progreso se estirase de más.
            .frame(width: 268, alignment: .leading)
        }
        .animation(DockMetrics.closeAnimation, value: track.title)
    }

    private func artwork(_ track: NowPlaying) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(Theme.Fill.raised)
            .frame(width: 88, height: 88)
            .overlay {
                if let image = media.artwork {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(Theme.Line.hairline, lineWidth: 1)
            }
            // La insignia dice de dónde sale la música sin gastar una línea de texto.
            .overlay(alignment: .bottomTrailing) {
                if let icon = track.source.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.black).frame(width: 24, height: 24))
                        .offset(x: 6, y: 6)
                        .help(track.source.displayName)
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 9, y: 4)
    }

    private func controls(isPlaying: Bool) -> some View {
        HStack(spacing: 2) {
            IconButton(symbol: "backward.fill", size: 11, help: "Anterior") {
                media.send(.previous)
            }

            Button {
                media.send(.playPause)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.Ink.primary))
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pausar" : "Reproducir")

            IconButton(symbol: "forward.fill", size: 11, help: "Siguiente") {
                media.send(.next)
            }
        }
        .padding(.leading, -6)
    }

    // MARK: - Sin reproducción

    @ViewBuilder
    private var placeholder: some View {
        if media.canRequestPermission {
            activation
        } else {
            unavailable
        }
    }

    /// Nada de diálogos por sorpresa: el permiso se pide desde aquí, con contexto y
    /// sólo si el usuario quiere el módulo.
    private var activation: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Ink.faint)

            Text("Conectar con tu música")
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.Ink.primary)

            Text("macOS te pedirá permiso para Spotify o Música")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.tertiary)

            Button(action: media.requestPermission) {
                Text("Conectar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.Ink.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(width: 300, height: 128)
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: media.needsAutomationPermission ? "lock" : "music.note")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Ink.faint)

            Text(media.needsAutomationPermission ? "Permiso pendiente" : "Sin reproducción")
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.Ink.secondary)

            Text(media.needsAutomationPermission
                 ? "Autoriza DotDock en Ajustes → Privacidad → Automatización"
                 : "Abre Spotify o Música y dale a play")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 300, height: 92)
    }

    /// A partir de este largo el título ocupa dos líneas y se come la del álbum. Es una
    /// estimación por caracteres, no una medida: basta para mantener constante la
    /// altura del bloque, que es lo que evita el hueco muerto sobre los controles.
    private static let wrappingTitleLength = 48

    /// Muchas pistas repiten el título en el álbum — sobre todo sencillos y remixes —
    /// y mostrar ambos es ruido que además roba una línea al título.
    static func showsAlbum(_ track: NowPlaying) -> Bool {
        guard !track.album.isEmpty else { return false }
        guard track.title.count <= wrappingTitleLength else { return false }

        let album = normalize(track.album)
        let title = normalize(track.title)
        guard !album.isEmpty, !title.isEmpty else { return false }

        // Compara por prefijo y no por igualdad: "Canción" y "Canción (Remix)" son el
        // mismo dato a efectos de lectura.
        let length = min(14, min(album.count, title.count))
        return !album.hasPrefix(title.prefix(length)) && !title.hasPrefix(album.prefix(length))
    }

    /// Sin acentos, sin mayúsculas y sin puntuación: los metadatos de las tiendas de
    /// música son inconsistentes en las tres cosas.
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    static func time(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ProgressBar: View {

    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Fill.hover)
                Capsule()
                    .fill(Theme.Ink.primary)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 1), value: progress)
    }
}
