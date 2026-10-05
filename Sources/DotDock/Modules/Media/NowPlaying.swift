import AppKit

enum MediaSource: String, CaseIterable {
    case spotify
    case music

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .music: "com.apple.Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Música"
        }
    }

    /// Spotify reporta la duración en milisegundos; Music en segundos.
    var durationIsMilliseconds: Bool { self == .spotify }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Icono real de la app, para marcar la carátula con su origen. Más legible que
    /// poner "Spotify" en texto, y ocupa mucho menos.
    var appIcon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

enum PlaybackState: String {
    case playing
    case paused
    case stopped
}

enum MediaCommand {
    case playPause
    case next
    case previous

    /// Comando en el dialecto de AppleScript que entienden Music y Spotify.
    var appleScript: String {
        switch self {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
    }
}

struct NowPlaying: Equatable {
    var source: MediaSource
    var title: String
    var artist: String
    var album: String
    var state: PlaybackState
    var duration: TimeInterval
    var position: TimeInterval

    /// Identifica la pista para saber cuándo recargar la carátula. En Spotify es la
    /// URL del artwork; en Music, el ID persistente.
    var artworkKey: String

    var isPlaying: Bool { state == .playing }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

extension NowPlaying {
    /// Dos lecturas son la misma pista si coinciden fuente y metadatos; la posición
    /// cambia constantemente y no debe contar.
    func isSameTrack(as other: NowPlaying?) -> Bool {
        guard let other else { return false }
        return source == other.source
            && title == other.title
            && artist == other.artist
            && artworkKey == other.artworkKey
    }
}
