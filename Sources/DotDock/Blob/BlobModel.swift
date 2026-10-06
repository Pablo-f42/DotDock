import AppKit
import Combine
import SwiftUI

/// Comportamiento de la gotita. Las proporciones viven en `BlobProportions`.
enum BlobMetrics {
    /// Cuánto se desplazan los ojos al mirar a un lado.
    static let gazeTravel = CGSize(width: 2.5, height: 1.5)

    /// Si el cursor se acerca a menos de esto, se esconde antes de que la toques.
    static let shyDistance: CGFloat = 70
}

enum BlobMood: Equatable {
    case normal
    /// Acabas de terminar un pomodoro de concentración.
    case happy
    /// Llevas rato sin tocar el Mac, o es muy tarde.
    case sleepy
    /// La sesión de Claude va por encima del 80 %.
    case worried
    /// Suena música: baila con los ojos cerrados.
    case music
    /// Copiaste algo: te guiña un ojo, como si lo guardara.
    case wink
    /// Soltaste un archivo en la bandeja: se lo traga.
    case gulp
    /// Volviste tras un rato fuera: te saluda.
    case hello
    /// El cursor se le acercó.
    case startled
}

/// La gotita negra que de vez en cuando se asoma por debajo de la muesca.
///
/// Sólo dibuja estado; toda la coreografía vive aquí como una secuencia de pasos
/// animados. Cada asomada es una `Task` cancelable, así que esconderse de golpe es
/// cancelar la que esté en curso y lanzar la retirada.
@MainActor
final class BlobModel: ObservableObject {

    /// Hay gotita en pantalla, aunque esté a medio salir o a medio esconderse.
    @Published private(set) var isPresent = false
    /// 0 escondida, 1 asomada del todo. El resorte la pasa de 1 para que rebote.
    @Published private(set) var reach: CGFloat = 0
    @Published private(set) var eyeOpenness: CGFloat = 0
    /// Hacia dónde mira, en -1...1 por eje (y crece hacia abajo).
    @Published private(set) var gaze: CGSize = .zero
    @Published private(set) var mood: BlobMood = .normal
    /// Desplazamiento horizontal respecto al centro de la muesca.
    @Published private(set) var offsetX: CGFloat = 0
    /// Balanceo del cuerpo, -1...1. Los filetes quedan fijos a la muesca; sólo se mueve
    /// la panza, como un líquido.
    @Published private(set) var lean: CGFloat = 0
    /// Avance de la nota musical que suelta al bailar, 0...1, y de qué lado sale.
    @Published private(set) var noteProgress: CGFloat = 1
    @Published private(set) var noteSide: CGFloat = 1
    /// Cierra sólo el ojo izquierdo, para guiñar.
    @Published private(set) var isWinking = false

    /// Dónde asomarse cuando toca. Lo instala el `AppDelegate` para que salga en la
    /// pantalla donde está el cursor; sin él, sale en la propia.
    var target: (() -> BlobModel?)?

    private unowned let dock: DockModel
    private var settings: AppSettings { dock.stores.settings }

    private var isRunning = false
    private var isRetreating = false
    /// Quieta y asomada mientras el panel de diseño está abierto.
    private var isHeldForDesign = false
    private var lastCursorMove = Date.distantPast
    /// Última vez que salió por cada reacción. Sin respiro, copiar diez cosas
    /// seguidas la sacaría diez veces.
    private var lastReaction: [BlobReaction: Date] = [:]
    private var lastIdle: TimeInterval = 0
    private var scheduler: Task<Void, Never>?
    private var performance: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(dock: DockModel) {
        self.dock = dock
    }

    // MARK: - Programación

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Sólo lo que afecta al horario lo reprograma; cambiar el color del
        // visualizador no debería reiniciar la cuenta de la gotita.
        Publishers.CombineLatest3(settings.$blobEnabled, settings.$blobTrigger, settings.$blobPersonality)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)

        observeReactions()
        reschedule()
    }

    // MARK: - Reacciones

    private func observeReactions() {
        let stores = dock.stores

        // Al terminar un pomodoro sale a celebrarlo. El segundo de espera deja que el
        // panel recoja el live activity primero.
        stores.pomodoro.$lastFocusCompletion
            .compactMap { $0 }
            .delay(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.react(.pomodoro, mood: .happy, cooldown: 0) }
            .store(in: &cancellables)

        // Al empezar a sonar algo sale a bailar, pero no cada vez que pausas y
        // reanudas la misma canción.
        stores.media.$nowPlaying
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .filter { $0 }
            .delay(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.react(.music, mood: .music, cooldown: 600) }
            .store(in: &cancellables)

        stores.clipboard.$entries
            .map { $0.first?.id }
            .removeDuplicates()
            .dropFirst()
            .filter { $0 != nil }
            .sink { [weak self] _ in self?.react(.copy, mood: .wink, cooldown: 180) }
            .store(in: &cancellables)

        // Sale cuando el panel ya se cerró: soltar el archivo lo abre.
        let shelfCount = stores.shelf.items.count
        stores.shelf.$items
            .map(\.count)
            .dropFirst()
            .scan((shelfCount, shelfCount)) { ($0.1, $1) }
            .filter { $0.1 > $0.0 }
            .sink { [weak self] _ in self?.react(.shelf, mood: .gulp, cooldown: 30) }
            .store(in: &cancellables)

        stores.claude.$session
            .map { ($0.percent ?? 0) >= 80 }
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.react(.claude, mood: .worried, cooldown: 1800) }
            .store(in: &cancellables)

        // Volver tras diez minutos sin tocar el Mac: se nota porque el tiempo
        // inactivo cae de golpe.
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.checkWelcomeBack() }
            .store(in: &cancellables)
    }

    private func react(_ reaction: BlobReaction, mood: BlobMood, cooldown: TimeInterval) {
        guard settings.reacts(to: reaction) else { return }
        if let last = lastReaction[reaction], Date().timeIntervalSince(last) < cooldown { return }

        lastReaction[reaction] = Date()
        peekWhenPossible(mood: mood, ignoringActivity: true)
    }

    private func checkWelcomeBack() {
        let idle = Self.idleSeconds()
        defer { lastIdle = idle }

        if lastIdle > 600, idle < 10 {
            react(.welcome, mood: .hello, cooldown: 0)
        }
    }

    private static func idleSeconds() -> TimeInterval {
        // ~0 es `kCGAnyInputEventType`: cualquier teclado o ratón.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func stop() {
        isRunning = false
        cancellables.removeAll()
        scheduler?.cancel()
        hideNow()
    }

    private func reschedule() {
        scheduler?.cancel()
        guard isRunning, settings.blobEnabled else {
            hideNow()
            return
        }

        scheduler = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.nextDelay() else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }

                let resting = self.settings.blobTrigger == .resting
                self.peekWhenPossible(mood: nil, ignoringActivity: !resting)
            }
        }
    }

    private func nextDelay() -> TimeInterval {
        switch settings.blobTrigger {
        case .resting: .random(in: settings.blobPersonality.restingDelay)
        case .every(let minutes): TimeInterval(minutes * 60)
        }
    }

    /// Espera un rato a que se den las condiciones: si justo estás usando el panel o
    /// tienes el cursor encima, la gotita aguarda en vez de perderse el turno.
    func peekWhenPossible(mood: BlobMood?, ignoringActivity: Bool) {
        Task { [weak self] in
            for _ in 0..<40 {
                guard let self else { return }
                // Se elige en cada intento: si mueves el cursor a otro monitor
                // mientras espera, sale en ese.
                let blob = self.target?() ?? self
                if blob.canPeek(ignoringActivity: ignoringActivity) {
                    blob.peek(mood: mood)
                    return
                }
                try? await Task.sleep(for: .seconds(0.5))
            }
        }
    }

    private func canPeek(ignoringActivity: Bool) -> Bool {
        guard !isPresent, !isHeldForDesign, dock.state == .closed else { return false }
        if !ignoringActivity, dock.showsLiveActivity { return false }
        return distance(to: NSEvent.mouseLocation) > BlobMetrics.shyDistance * 2
    }

    /// Sólo para inspección: se asoma ya con el ánimo pedido, sin mirar condiciones.
    /// Ver `DOTDOCK_DEBUG_BLOB`.
    func debugPeek(mood name: String) {
        let moods: [String: BlobMood] = [
            "happy": .happy, "sleepy": .sleepy, "worried": .worried, "music": .music,
            "wink": .wink, "gulp": .gulp, "hello": .hello
        ]
        peek(mood: moods[name] ?? .normal)
    }

    // MARK: - Panel de diseño

    /// Con el panel abierto la gotita sale y se queda fuera, sin asustarse del cursor,
    /// para poder verla mientras se mueven los deslizadores.
    func setDesignHold(_ held: Bool) {
        isHeldForDesign = held
        if held, !isPresent { peek(mood: .normal) }
    }

    func preview(mood: BlobMood) {
        guard isPresent, !isRetreating else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            self.mood = mood
            eyeOpenness = restingOpenness
        }
    }

    /// Se esconde y vuelve a salir, para revisar la animación con las medidas nuevas.
    func replayForDesign(mood: BlobMood) {
        Task { [weak self] in
            guard let self else { return }
            let held = self.isHeldForDesign
            self.isHeldForDesign = false
            self.hideNow()
            try? await Task.sleep(for: .seconds(0.8))
            self.isHeldForDesign = held
            self.peek(mood: mood)
        }
    }

    // MARK: - Coreografía

    private func peek(mood forced: BlobMood?) {
        performance?.cancel()

        mood = forced ?? currentMood()
        offsetX = randomOffset()
        reach = 0
        eyeOpenness = 0
        gaze = .zero
        lean = 0
        noteProgress = 1
        isWinking = false
        isRetreating = false
        isPresent = true

        performance = Task { [weak self] in await self?.perform() }
    }

    private func perform() async {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { reach = 1 }
        guard await pause(0.5) else { return }

        withAnimation(.easeOut(duration: 0.2)) { eyeOpenness = restingOpenness }
        guard await pause(0.5) else { return }

        switch mood {
        case .normal:
            guard await look(-1, hold: 0.9),
                  await look(1, hold: 0.9),
                  await blink(),
                  await look(0, hold: 0.8),
                  await blink(),
                  await pause(0.4)
            else { return }

        case .happy:
            for _ in 0..<2 {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { reach = 1.18 }
                guard await pause(0.2) else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { reach = 1 }
                guard await pause(0.35) else { return }
            }
            guard await look(-0.6, hold: 0.6), await look(0.6, hold: 0.6) else { return }

        case .sleepy:
            guard await pause(0.8), await blink(duration: 0.5), await pause(0.6) else { return }
            withAnimation(.easeInOut(duration: 1.2)) { eyeOpenness = 0.12 }
            guard await pause(1.4) else { return }
            withAnimation(.easeOut(duration: 0.25)) { eyeOpenness = restingOpenness }
            guard await look(0.5, hold: 1.0) else { return }

        case .worried:
            for side in [-1.0, 1.0, -1.0, 1.0] {
                guard await look(side, hold: 0.35) else { return }
            }
            guard await blink(), await look(0, hold: 0.6) else { return }

        case .music:
            guard await dance(beats: 8) else { return }

        case .wink:
            guard await look(0, hold: 0.4) else { return }
            withAnimation(.easeIn(duration: 0.08)) { isWinking = true }
            guard await pause(0.45) else { return }
            withAnimation(.easeOut(duration: 0.12)) { isWinking = false }
            guard await hop(), await pause(0.6) else { return }

        case .gulp:
            // Se estira como abriendo la boca, traga de golpe con los ojos
            // apretados y queda contenta.
            withAnimation(.easeOut(duration: 0.2)) { reach = 1.3 }
            guard await pause(0.25) else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) {
                reach = 0.8
                eyeOpenness = 0
            }
            guard await pause(0.3) else { return }
            mood = .happy
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                reach = 1
                eyeOpenness = 1
            }
            guard await pause(0.9) else { return }

        case .hello:
            guard await hop(), await hop(), await look(0, hold: 0.3),
                  await blink(), await blink(), await pause(0.6)
            else { return }

        case .startled:
            break
        }

        // Con el panel de diseño abierto, termina su número y se queda fuera.
        while isHeldForDesign {
            guard await pause(0.2) else { return }
        }

        await retreat(fast: false)
    }

    /// Rebota a tiempo y se balancea de lado a lado, soltando una nota cada dos
    /// tiempos. No sabe el tempo real de la canción; ~110 bpm queda bien con casi todo.
    private func dance(beats: Int) async -> Bool {
        let beat: TimeInterval = 0.55

        for n in 0..<beats {
            let side: CGFloat = n.isMultiple(of: 2) ? 1 : -1

            if n.isMultiple(of: 2) {
                noteSide = n.isMultiple(of: 4) ? 1 : -1
                noteProgress = 0
                withAnimation(.easeOut(duration: beat * 1.6)) { noteProgress = 1 }
            }

            withAnimation(.easeOut(duration: beat * 0.3)) {
                reach = 1.1
                lean = side
            }
            guard await pause(beat * 0.3) else { return false }
            withAnimation(.easeInOut(duration: beat * 0.7)) { reach = 1 }
            guard await pause(beat * 0.7) else { return false }
        }

        withAnimation(.easeInOut(duration: 0.3)) { lean = 0 }
        return await pause(0.4)
    }

    /// Un saltito: se estira un poco y rebota.
    private func hop() async -> Bool {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { reach = 1.15 }
        guard await pause(0.2) else { return false }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { reach = 1 }
        return await pause(0.3)
    }

    private var restingOpenness: CGFloat {
        switch mood {
        case .sleepy: 0.45
        case .worried: 0.8
        default: 1
        }
    }

    /// Mira a un lado. Si moviste el cursor hace poco, lo sigue a él en vez del guion.
    private func look(_ side: CGFloat, hold: TimeInterval) async -> Bool {
        if Date().timeIntervalSince(lastCursorMove) > 1.2 {
            withAnimation(.easeInOut(duration: 0.22)) { gaze = CGSize(width: side, height: 0.3) }
        }
        return await pause(hold)
    }

    private func blink(duration: TimeInterval = 0.16) async -> Bool {
        let open = eyeOpenness
        withAnimation(.easeIn(duration: duration * 0.4)) { eyeOpenness = 0 }
        guard await pause(duration * 0.5) else { return false }
        withAnimation(.easeOut(duration: duration * 0.6)) { eyeOpenness = open }
        return await pause(duration * 0.6)
    }

    private func retreat(fast: Bool) async {
        isRetreating = true

        withAnimation(.easeIn(duration: fast ? 0.06 : 0.14)) { eyeOpenness = 0 }
        guard await pause(fast ? 0.04 : 0.18) else { return }

        let animation: Animation = fast
            ? .spring(response: 0.2, dampingFraction: 1)
            : .spring(response: 0.4, dampingFraction: 0.85)
        withAnimation(animation) { reach = 0 }
        guard await pause(fast ? 0.3 : 0.55) else { return }

        isPresent = false
        isRetreating = false
    }

    /// Se esconde ya. Para cuando el panel se despliega encima de ella.
    func hideNow() {
        guard isPresent else { return }
        performance?.cancel()
        performance = Task { [weak self] in await self?.retreat(fast: true) }
    }

    private func startle() {
        performance?.cancel()
        isRetreating = true

        performance = Task { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.08)) {
                self.mood = .startled
                self.eyeOpenness = 1
            }
            guard await self.pause(0.14) else { return }
            await self.retreat(fast: true)
        }
    }

    /// `false` si la asomada se canceló mientras esperaba.
    private func pause(_ seconds: TimeInterval) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    // MARK: - Cursor

    func cursorMoved(to point: CGPoint) {
        guard isPresent, !isRetreating else { return }

        if !isHeldForDesign, settings.blobIsShy, distance(to: point) < BlobMetrics.shyDistance {
            startle()
            return
        }

        guard settings.blobFollowsCursor else { return }
        lastCursorMove = Date()

        let center = blobCenter
        let dx = point.x - center.x
        let dy = point.y - center.y
        let length = max(hypot(dx, dy), 1)
        let strength = min(length / 150, 1)

        // AppKit cuenta y hacia arriba; SwiftUI, hacia abajo.
        withAnimation(.easeOut(duration: 0.15)) {
            gaze = CGSize(width: dx / length * strength, height: -dy / length * strength)
        }
    }

    // MARK: - Geometría

    /// Rect de la gotita asomada en coordenadas globales de AppKit.
    private var blobRect: CGRect {
        let cutoutRect = dock.geometry.cutoutRect
        let top = cutoutRect.maxY - dock.contentSize.height
        let shape = BlobDesign.shared.proportions

        return CGRect(
            x: cutoutRect.midX + offsetX - shape.frameWidth / 2,
            y: top - shape.height,
            width: shape.frameWidth,
            height: shape.height
        )
    }

    private var blobCenter: CGPoint {
        CGPoint(x: blobRect.midX, y: blobRect.midY)
    }

    private func distance(to point: CGPoint) -> CGFloat {
        let rect = blobRect
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Un sitio al azar a lo largo del borde inferior, lejos de las esquinas redondas.
    private func randomOffset() -> CGFloat {
        let half = dock.contentSize.width / 2
            - DockMetrics.closedBottomRadius
            - BlobDesign.shared.proportions.frameWidth / 2
            - 2
        return half > 0 ? .random(in: -half...half) : 0
    }

    private func currentMood() -> BlobMood {
        let stores = dock.stores

        if let done = stores.pomodoro.lastFocusCompletion, Date().timeIntervalSince(done) < 600 {
            return .happy
        }
        if stores.media.nowPlaying?.isPlaying == true {
            return .music
        }
        if (stores.claude.session.percent ?? 0) >= 80 {
            return .worried
        }

        let idle = Self.idleSeconds()
        let hour = Calendar.current.component(.hour, from: Date())
        if idle > 180 || hour >= 23 || hour < 6 {
            return .sleepy
        }

        return .normal
    }
}
