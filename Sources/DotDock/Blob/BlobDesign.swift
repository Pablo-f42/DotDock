import AppKit
import SwiftUI

/// Proporciones de la gotita, en puntos.
struct BlobProportions: Codable, Equatable {
    var bodyWidth: CGFloat = 42
    var height: CGFloat = 27

    /// Radio de los filetes cóncavos que la unen al borde de la muesca. Son los que la
    /// hacen parecer del mismo material y no una pieza pegada debajo.
    var fillet: CGFloat = 16

    var eyeWidth: CGFloat = 4
    var eyeHeight: CGFloat = 9.5
    var eyeSpacing: CGFloat = 8.5

    /// Altura de los ojos dentro del cuerpo: 0 arriba, 1 abajo.
    var eyeLevel: CGFloat = 0.15

    var frameWidth: CGFloat { bodyWidth + fillet * 2 }
    var eyeSize: CGSize { CGSize(width: eyeWidth, height: eyeHeight) }
}

/// Proporciones vigentes, editables en vivo desde Ajustes → Dot.
final class BlobDesign: ObservableObject {

    static let shared = BlobDesign()

    private static let key = "blob.proportions"

    @Published var proportions: BlobProportions {
        didSet {
            guard let data = try? JSONEncoder().encode(proportions) else { return }
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        proportions = data.flatMap { try? JSONDecoder().decode(BlobProportions.self, from: $0) }
            ?? BlobProportions()
    }
}
