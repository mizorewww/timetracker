import SwiftUI

extension Color {
    init?(hex: String?) {
        guard let rgb = HexColorParser.components(for: hex) else { return nil }
        self.init(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue
        )
    }
}
