import SwiftUI

enum AppColors {
    static let background = Color(platformColor: .systemGroupedBackground)
    #if os(macOS)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    #else
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    #endif
    static let border = Color.primary.opacity(0.08)
    static let panelHeader = LinearGradient(
        colors: [Color.blue.opacity(0.10), Color.green.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum TaskColorPalette {
    static let hexValues = [
        "1677FF", "0A84FF", "5E5CE6", "7C3AED", "AF52DE", "BF5AF2",
        "FF2D55", "EF4444", "FF453A", "F97316", "FF9F0A", "F59E0B",
        "FFD60A", "A3E635", "34C759", "16A34A", "30D158", "00C7BE",
        "0EA5E9", "64D2FF", "06B6D4", "64748B", "8E8E93", "3A3A3C"
    ]
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt64(sanitized, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}

#if os(macOS)
typealias PlatformColor = NSColor
extension PlatformColor {
    static var systemGroupedBackground: NSColor { NSColor.windowBackgroundColor }
}
#else
typealias PlatformColor = UIColor
#endif
