import SwiftUI

struct PomodoroView: View {

    @ObservedObject var timer: PomodoroTimer

    private var accent: Color {
        timer.phase.isBreak ? .green.opacity(0.85) : Theme.Ink.primary
    }

    var body: some View {
        HStack(spacing: 24) {
            ring

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: timer.phase.title, symbol: timer.phase.symbol)
                sessionDots
                controls
            }
            // Sin ancho fijo: los 210 pt de antes dejaban aire muerto a la derecha de
            // la columna y descentraban el bloque dentro del panel.
            .fixedSize()
        }
        .fixedSize()
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.Fill.hover, lineWidth: 6)

            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timer.progress)

            VStack(spacing: 0) {
                Text(timer.formattedRemaining)
                    .font(Theme.Typo.display(21))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Ink.primary)

                Text(timer.isRunning ? "en curso" : "en pausa")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .frame(width: 92, height: 92)
    }

    /// Puntos del ciclo actual. Al completar la cuarta sesión el resto da 0, y hay que
    /// mostrar los cuatro llenos en vez de vaciarlos justo al lograrlo.
    private var filledDots: Int {
        let remainder = timer.completedSessions % PomodoroTimer.sessionsPerCycle
        if remainder == 0 && timer.completedSessions > 0 {
            return PomodoroTimer.sessionsPerCycle
        }
        return remainder
    }

    private var sessionDots: some View {
        HStack(spacing: 5) {
            ForEach(0 ..< PomodoroTimer.sessionsPerCycle, id: \.self) { index in
                Capsule()
                    .fill(index < filledDots ? accent : Theme.Fill.hover)
                    .frame(width: index < filledDots ? 14 : 7, height: 4)
                    .animation(DockMetrics.moduleAnimation, value: filledDots)
            }

            Text("\(timer.completedSessions) completadas")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Ink.tertiary)
                .padding(.leading, 3)
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button(action: timer.toggle) {
                HStack(spacing: 5) {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(timer.isRunning ? "Pausar" : "Empezar")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)

            IconButton(symbol: "arrow.counterclockwise", help: "Reiniciar fase", action: timer.reset)
            IconButton(symbol: "forward.end.fill", help: "Saltar fase", action: timer.skip)
        }
    }
}
