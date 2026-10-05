import AppKit
import SwiftUI

enum PomodoroPhase: String, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    var duration: TimeInterval {
        switch self {
        case .focus: 25 * 60
        case .shortBreak: 5 * 60
        case .longBreak: 15 * 60
        }
    }

    var title: String {
        switch self {
        case .focus: "Concentración"
        case .shortBreak: "Descanso"
        case .longBreak: "Descanso largo"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "brain.head.profile"
        case .shortBreak, .longBreak: "cup.and.saucer"
        }
    }

    var isBreak: Bool { self != .focus }
}

@MainActor
final class PomodoroTimer: ObservableObject {

    @Published private(set) var phase: PomodoroPhase = .focus
    @Published private(set) var remaining: TimeInterval = PomodoroPhase.focus.duration
    @Published private(set) var isRunning = false

    /// Sesiones de concentración completadas en el ciclo actual.
    @Published private(set) var completedSessions = 0

    /// Cuándo terminó, completa, la última sesión de concentración.
    @Published private(set) var lastFocusCompletion: Date?

    /// Cada cuántas sesiones de concentración toca el descanso largo.
    static let sessionsPerCycle = 4

    private var timer: Timer?

    var progress: Double {
        1 - (remaining / phase.duration)
    }

    /// `mm:ss`, redondeando hacia arriba para que el último segundo se vea como 0:01
    /// y no salte de 0:02 a 0:00.
    var formattedRemaining: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Control

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        timer = Timer.repeatingOnCommonModes(every: 1) { [weak self] in
            self?.tick()
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// Reinicia la fase actual sin cambiar de fase ni perder el conteo del ciclo.
    func reset() {
        pause()
        remaining = phase.duration
    }

    func skip() {
        advance(countCompletion: false)
    }

    /// Sólo para inspección: arranca con la cuenta ya avanzada, para poder capturar el
    /// indicador a media tarta sin esperar minutos.
    func debugStart(remainingFraction: Double) {
        remaining = phase.duration * min(max(remainingFraction, 0), 1)
        start()
    }

    // MARK: - Interno

    private func tick() {
        remaining -= 1
        guard remaining <= 0 else { return }

        NSSound(named: "Glass")?.play()
        advance(countCompletion: true)
    }

    /// Al terminar una fase no arrancamos la siguiente sola: si te levantaste de la
    /// silla, un descanso que corre sin ti no sirve de nada.
    private func advance(countCompletion: Bool) {
        pause()

        if phase == .focus {
            if countCompletion {
                completedSessions += 1
                lastFocusCompletion = Date()
            }
            let cycleDone = completedSessions % Self.sessionsPerCycle == 0
            phase = (cycleDone && completedSessions > 0) ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }

        remaining = phase.duration
    }
}
