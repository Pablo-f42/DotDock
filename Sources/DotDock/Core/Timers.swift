import Foundation

extension Timer {

    /// Temporizador repetitivo en modo `.common`.
    ///
    /// `Timer.scheduledTimer` lo registra en modo `.default`, que **se detiene**
    /// mientras hay un bucle de seguimiento activo: un menú abierto, un arrastre, el
    /// redimensionado de una ventana. Para una app que vive de sondear — reproducción,
    /// portapapeles, cuenta atrás del pomodoro — eso significa quedarse congelada justo
    /// cuando el usuario está interactuando.
    @discardableResult
    static func repeatingOnCommonModes(
        every interval: TimeInterval,
        _ block: @escaping @MainActor () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated(block)
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
