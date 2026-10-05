import SwiftUI

/// Lo que se ve en el panel en reposo mientras suena algo: la carátula en el ala
/// izquierda y un visualizador en la derecha.
///
/// El centro va vacío a propósito — ahí está la muesca de la pantalla, donde no se puede
/// dibujar nada legible.
struct LiveActivityView: View {

    @ObservedObject var media: MediaController
    @ObservedObject var pomodoro: PomodoroTimer

    let isPlaying: Bool
    let cutoutWidth: CGFloat
    let height: CGFloat

    private var sideWidth: CGFloat { DockMetrics.liveActivitySideWidth }

    /// El pomodoro manda sobre la música: si estás contando tiempo, ese es el dato
    /// urgente. La carátula sigue a la izquierda si además hay algo sonando.
    private var showsPomodoro: Bool { pomodoro.isRunning }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: sideWidth, height: height)

            Spacer(minLength: 0)
                .frame(width: cutoutWidth)

            trailing
                .frame(width: sideWidth, height: height)
        }
        .frame(height: height)
        .transition(.opacity)
    }

    @ViewBuilder
    private var leading: some View {
        if media.nowPlaying != nil {
            artwork
        } else if showsPomodoro {
            Image(systemName: pomodoro.phase.symbol)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if showsPomodoro {
            PomodoroPie(
                remaining: 1 - pomodoro.progress,
                tint: pomodoro.phase.isBreak ? .green.opacity(0.9) : Theme.Ink.primary
            )
            .animation(.linear(duration: 1), value: pomodoro.progress)
        } else {
            AudioBars(isAnimating: isPlaying)
        }
    }

    private var artwork: some View {
        Group {
            if let image = media.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white.opacity(0.15))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Barras de audio animadas.
///
/// Son decorativas: no leen el nivel real de audio. Capturarlo exigiría interceptar
/// la salida del sistema (ScreenCaptureKit o un dispositivo virtual), que es un
/// proyecto en sí mismo y pediría permisos aparte.
///
/// Van con `TimelineView` en vez de animaciones repetidas porque `repeatForever` se
/// desincroniza al entrar y salir de la jerarquía; aquí la altura es función pura del
/// tiempo, así que siempre se ve coherente.
private struct AudioBars: View {

    let isAnimating: Bool

    private let barCount = 4
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 14
    private let minHeight: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 2) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: barWidth, height: height(at: time, index: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Cada barra tiene su propia frecuencia y desfase; sin eso se mueven todas al
    /// unísono y parece un ecualizador de juguete.
    private func height(at time: TimeInterval, index: Int) -> CGFloat {
        guard isAnimating else { return minHeight }

        let speeds: [Double] = [5.1, 7.3, 6.2, 8.4]
        let phases: [Double] = [0, 1.7, 3.1, 4.6]

        let wave = sin(time * speeds[index] + phases[index])
        let normalized = (wave + 1) / 2

        return minHeight + (maxHeight - minHeight) * normalized
    }
}
