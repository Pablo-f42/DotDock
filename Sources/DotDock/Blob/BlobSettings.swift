import Foundation

/// Preferencias de la gotita. Son globales: viven en `DockStores` y las comparten
/// todas las pantallas.
@MainActor
final class BlobSettings: ObservableObject {

    enum Trigger: Equatable {
        /// A ratos al azar, sólo con el panel cerrado y sin nada sonando.
        case resting
        /// Cada tantos minutos, suene algo o no.
        case every(minutes: Int)
    }

    static let intervalChoices = [1, 3, 5, 10, 15, 30]

    private static let enabledKey = "blob.enabled"
    private static let intervalKey = "blob.intervalMinutes"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    @Published var trigger: Trigger {
        didSet {
            let minutes = if case .every(let minutes) = trigger { minutes } else { 0 }
            UserDefaults.standard.set(minutes, forKey: Self.intervalKey)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true

        let minutes = defaults.integer(forKey: Self.intervalKey)
        trigger = minutes > 0 ? .every(minutes: minutes) : .resting
    }
}
