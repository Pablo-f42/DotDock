import SwiftUI

/// Lo que se ve en el panel en reposo mientras suena algo: la carátula en el ala
/// izquierda y un visualizador en la derecha.
///
/// El centro va vacío a propósito — ahí está la muesca de la pantalla, donde no se puede
/// dibujar nada legible.
struct LiveActivityView: View {

    @ObservedObject var media: MediaController
    @ObservedObject var pomodoro: PomodoroTimer
    @ObservedObject var settings: AppSettings

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
            Visualizer(style: settings.visualizerStyle, tint: visualizerTint, isAnimating: isPlaying)
        }
    }

    private var visualizerTint: Color {
        switch settings.visualizerTint {
        case .white: .white.opacity(0.85)
        case .artwork: media.artworkColor ?? .white.opacity(0.85)
        case .spotify: Color(red: 0.12, green: 0.84, blue: 0.38)
        case .custom: settings.customTint
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

/// Visualizador de audio animado.
///
/// Es decorativo: no lee el nivel real de audio. Capturarlo exigiría interceptar la
/// salida del sistema (ScreenCaptureKit o un dispositivo virtual), que es un proyecto
/// en sí mismo y pediría permisos aparte.
///
/// Va con `TimelineView` en vez de animaciones repetidas porque `repeatForever` se
/// desincroniza al entrar y salir de la jerarquía; aquí todo es función pura del
/// tiempo, así que siempre se ve coherente.
struct Visualizer: View {

    let style: VisualizerStyle
    let tint: Color
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            Group {
                switch style {
                case .bars: bars(at: time)
                case .wave: wave(at: time)
                case .dots: dots(at: time)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Cada elemento tiene su propia frecuencia y desfase; sin eso se mueven todos al
    /// unísono y parece un ecualizador de juguete. Devuelve 0...1.
    private func level(at time: TimeInterval, index: Int) -> CGFloat {
        guard isAnimating else { return 0 }

        let speeds: [Double] = [5.1, 7.3, 6.2, 8.4]
        let phases: [Double] = [0, 1.7, 3.1, 4.6]
        let wave = sin(time * speeds[index % 4] + phases[index % 4])
        return CGFloat((wave + 1) / 2)
    }

    private func bars(at time: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0 ..< 4, id: \.self) { index in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.5, height: 3 + 11 * level(at: time, index: index))
            }
        }
    }

    private func wave(at time: TimeInterval) -> some View {
        let amplitude = isAnimating ? 0.35 + 0.65 * level(at: time, index: 1) : 0

        return WaveLine(phase: time * 7, amplitude: amplitude)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 20, height: 12)
    }

    private func dots(at time: TimeInterval) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0 ..< 3, id: \.self) { index in
                let value = level(at: time, index: index)
                Circle()
                    .fill(tint.opacity(0.45 + 0.55 * Double(value)))
                    .frame(width: 3 + 2.5 * value, height: 3 + 2.5 * value)
                    .frame(width: 5.5, height: 5.5)
            }
        }
    }
}

/// Una senoide de dos ciclos que se desplaza con `phase`.
private struct WaveLine: Shape {

    var phase: Double
    var amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 40

        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let angle = Double(progress) * .pi * 4 + phase
            // Los extremos van más bajos: la onda nace y muere en el centro.
            let envelope = sin(progress * .pi)
            let y = rect.midY + CGFloat(sin(angle)) * rect.height / 2 * amplitude * envelope
            let point = CGPoint(x: rect.minX + rect.width * progress, y: y)

            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }

        return path
    }
}
