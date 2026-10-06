import AppKit
import SwiftUI

enum PomodoroPhase: String, CaseIterable {
    case focus
    case shortBreak
    case longBreak

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
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false

    /// Sesiones de concentración completadas en el ciclo actual.
    @Published private(set) var completedSessions = 0

    /// Cuándo terminó, completa, la última sesión de concentración.
    @Published private(set) var lastFocusCompletion: Date?

    /// Cada cuántas sesiones de concentración toca el descanso largo.
    static let sessionsPerCycle = 4

    private var timer: Timer?

    /// Duración de cada fase. La fijan los ajustes.
    private var durations: [PomodoroPhase: TimeInterval] = [
        .focus: 25 * 60, .shortBreak: 5 * 60, .longBreak: 15 * 60
    ]

    var playsSound = true

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        durations[phase] ?? 25 * 60
    }

    /// Cambiar la duración con la cuenta parada reinicia la fase a la nueva medida; en
    /// marcha se respeta lo que lleva y aplica a la siguiente vez.
    func setMinutes(_ minutes: Int, for phase: PomodoroPhase) {
        let seconds = TimeInterval(max(minutes, 1) * 60)
        guard durations[phase] != seconds else { return }

        let wasPristine = !isRunning && remaining == duration(of: self.phase)
        durations[phase] = seconds
        if phase == self.phase, wasPristine { remaining = seconds }
    }

    var progress: Double {
        1 - (remaining / duration(of: phase))
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
        remaining = duration(of: phase)
    }

    func skip() {
        advance(countCompletion: false)
    }

    /// Sólo para inspección: arranca con la cuenta ya avanzada, para poder capturar el
    /// indicador a media tarta sin esperar minutos.
    func debugStart(remainingFraction: Double) {
        remaining = duration(of: phase) * min(max(remainingFraction, 0), 1)
        start()
    }

    // MARK: - Interno

    private func tick() {
        remaining -= 1
        guard remaining <= 0 else { return }

        if playsSound { NSSound(named: "Glass")?.play() }
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

        remaining = duration(of: phase)
    }
}
