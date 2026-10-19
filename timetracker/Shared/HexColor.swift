import SwiftUI

extension Color {
    /// Plain sRGB color for the widget, watch, and Live Activity. The app's
    /// SharedUI `Color.init?(hex:)` deliberately differs: it adapts luminance
    /// for dark/light backgrounds. This file is excluded from the app target
    /// and shared explicitly with those targets.
    init?(hex: String?) {
        guard let rgb = HexColorParser.components(for: hex) else { return nil }
        self.init(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue
        )
    }
}
