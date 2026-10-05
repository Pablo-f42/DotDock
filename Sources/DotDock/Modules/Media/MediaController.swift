import AppKit
import Combine
import Foundation

/// Sondea a los proveedores y publica el estado de reproducción para la UI.
///
/// AppleScript bloquea, así que cada sondeo se va a una cola serial propia y sólo el
/// resultado vuelve al hilo principal.
@MainActor
final class MediaController: ObservableObject {

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?

    /// `true` si el usuario negó el permiso de Automatización. La UI lo usa para
    /// explicar por qué no hay datos en vez de fingir que no suena nada.
    @Published private(set) var needsAutomationPermission = false

    /// Hay un reproductor abierto que aún no hemos pedido autorizar. La UI ofrece un
    /// botón; el diálogo del sistema no aparece hasta que el usuario lo pulsa.
    @Published private(set) var canRequestPermission = false

    private let providers = MediaSource.allCases.map(AppleScriptMediaProvider.init(source:))
    private let queue = DispatchQueue(label: "dev.faz.dotdock.media", qos: .utility)

    private var timer: Timer?
    private var loadedArtworkKey: String?

    /// Sondeos encolados que aún no han contestado.
    private var outstandingPolls = 0
    private var lastPollStart = Date.distantPast

    private static let pollInterval: TimeInterval = 1.0

    /// Pasado este tiempo se da por perdido un sondeo y se admite el siguiente.
    private static let pollDeadline: TimeInterval = 15

    /// Tope de sondeos encolados. Sin él, un AppleScript encallado acumularía trabajo
    /// en la cola serial sin límite.
    private static let maxOutstandingPolls = 2

    // MARK: - Ciclo de vida

    func start() {
        guard timer == nil else { return }

        poll()
        timer = Timer.repeatingOnCommonModes(every: Self.pollInterval) { [weak self] in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Sólo para inspección: deja de sondear y finge una pista sonando, para ver el
    /// reproductor lleno sin abrir Spotify. Ver `DOTDOCK_DEBUG_TRACK`.
    func debugFakeTrack(title: String) {
        stop()
        // Un sondeo ya encolado contestaría después y la pisaría.
        debugTrack = NowPlaying(
                source: .spotify,
                title: title,
                artist: "Artista de prueba",
                album: "Álbum",
                state: .playing,
                duration: 215,
                position: 64,
                artworkKey: ""
            )
        apply(nil, deniedPermission: false)
    }

    private var debugTrack: NowPlaying?

    // MARK: - Sondeo

    private func poll() {
        // Si el sondeo anterior sigue vivo (AppleScript lento, app colgada), no
        // encolamos otro encima. Pero pasado el plazo sí se admite uno más: con la
        // guarda a secas, un sondeo que no volvía dejaba el módulo muerto el resto de
        // la sesión, y eso es exactamente lo que ocurría.
        if outstandingPolls > 0 {
            guard outstandingPolls < Self.maxOutstandingPolls,
                  -lastPollStart.timeIntervalSinceNow > Self.pollDeadline
            else { return }
        }

        outstandingPolls += 1
        lastPollStart = Date()

        let providers = self.providers

        queue.async {
            var best: (provider: AppleScriptMediaProvider, track: NowPlaying)?
            var denied = false

            for provider in providers {
                switch provider.fetch() {
                case .none:
                    continue
                case .notAuthorized:
                    denied = true
                case .track(let track):
                    // Gana la que esté sonando; si ninguna suena, la primera pausada.
                    if track.isPlaying {
                        best = (provider, track)
                    } else if best == nil {
                        best = (provider, track)
                    }
                }
            }

            let pending = providers.contains { if case .notAsked = $0.permission { true } else { false } }

            let result = best?.track
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.canRequestPermission = pending
                    self.apply(result, deniedPermission: denied)
                    self.outstandingPolls = max(0, self.outstandingPolls - 1)
                }
            }
        }
    }

    private func apply(_ track: NowPlaying?, deniedPermission: Bool) {
        let track = debugTrack ?? track
        needsAutomationPermission = deniedPermission && track == nil

        let changedTrack = !(track?.isSameTrack(as: nowPlaying) ?? (nowPlaying == nil))
        nowPlaying = track

        guard changedTrack else { return }

        guard let track, !track.artworkKey.isEmpty else {
            artwork = nil
            loadedArtworkKey = nil
            return
        }

        guard track.artworkKey != loadedArtworkKey else { return }
        loadedArtworkKey = track.artworkKey
        loadArtwork(for: track)
    }

    // MARK: - Carátula

    private func loadArtwork(for track: NowPlaying) {
        artwork = nil

        switch track.source {
        case .spotify:
            guard let url = URL(string: track.artworkKey) else { return }
            downloadArtwork(from: url, key: track.artworkKey)

        case .music:
            exportMusicArtwork(key: track.artworkKey)
        }
    }

    private func downloadArtwork(from url: URL, key: String) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // La pista pudo cambiar mientras descargábamos.
                    guard self.loadedArtworkKey == key else { return }
                    self.artwork = image
                }
            }
        }.resume()
    }

    private func exportMusicArtwork(key: String) {
        guard let provider = providers.first(where: { $0.source == .music }) else { return }

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotdock-artwork.tiff").path

        queue.async {
            let image = provider.exportArtwork(to: path) ? NSImage(contentsOfFile: path) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.loadedArtworkKey == key else { return }
                    self.artwork = image
                }
            }
        }
    }

    /// Pide el permiso a los reproductores abiertos. Sólo desde una acción del usuario.
    ///
    /// Fuera de la cola de sondeo a propósito: la llamada del sistema no vuelve hasta
    /// que el usuario contesta el diálogo, y ahí dentro pararía el reproductor entero
    /// justo mientras se le pide al usuario que lo active.
    func requestPermission() {
        let providers = self.providers
        DispatchQueue.global(qos: .userInitiated).async {
            for provider in providers where provider.isRunning {
                provider.requestPermission()
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.poll() }
            }
        }
    }

    // MARK: - Control

    func send(_ command: MediaCommand) {
        guard let source = nowPlaying?.source,
              let provider = providers.first(where: { $0.source == source })
        else { return }

        queue.async { provider.send(command) }

        // Respuesta inmediata: no esperamos al siguiente sondeo para mover el botón.
        if command == .playPause {
            nowPlaying?.state = nowPlaying?.state == .playing ? .paused : .playing
        }
    }
}
