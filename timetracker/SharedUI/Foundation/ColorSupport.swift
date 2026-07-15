import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
    nonisolated static let hexValues = [
        "1677FF", "0A84FF", "5E5CE6", "7C3AED", "AF52DE", "BF5AF2",
        "FF2D55", "EF4444", "FF453A", "F97316", "FF9F0A", "F59E0B",
        "FFD60A", "A3E635", "34C759", "16A34A", "30D158", "00C7BE",
        "0EA5E9", "64D2FF", "06B6D4", "64748B", "8E8E93", "3A3A3C"
    ]

    static func accessibilityName(for hex: String) -> String {
        let normalized = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        let key: String
        switch normalized {
        case "1677FF": key = "color.name.royalBlue"
        case "0A84FF": key = "color.name.blue"
        case "5E5CE6": key = "color.name.indigo"
        case "7C3AED": key = "color.name.violet"
        case "AF52DE": key = "color.name.purple"
        case "BF5AF2": key = "color.name.lavenderPurple"
        case "FF2D55": key = "color.name.pink"
        case "EF4444": key = "color.name.red"
        case "FF453A": key = "color.name.coralRed"
        case "F97316": key = "color.name.orange"
        case "FF9F0A": key = "color.name.amber"
        case "F59E0B": key = "color.name.goldenOrange"
        case "FFD60A": key = "color.name.yellow"
        case "A3E635": key = "color.name.lime"
        case "34C759": key = "color.name.green"
        case "16A34A": key = "color.name.darkGreen"
        case "30D158": key = "color.name.mintGreen"
        case "00C7BE": key = "color.name.teal"
        case "0EA5E9": key = "color.name.skyBlue"
        case "64D2FF": key = "color.name.lightBlue"
        case "06B6D4": key = "color.name.cyan"
        case "64748B": key = "color.name.slate"
        case "8E8E93": key = "color.name.gray"
        case "3A3A3C": key = "color.name.charcoal"
        default:
            return String.localizedStringWithFormat(
                AppStrings.localized("color.name.custom"),
                normalized
            )
        }
        return AppStrings.localized(key)
    }
}

struct AccessibleSRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var relativeLuminance: Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func adapted(forDarkBackground: Bool) -> AccessibleSRGB {
        // Against the system's near-black/near-white base surfaces these
        // luminance limits satisfy WCAG's 4.5:1 small-text contrast target.
        let target = forDarkBackground ? 0.175 : 0.183
        if forDarkBackground, relativeLuminance >= target { return self }
        if !forDarkBackground, relativeLuminance <= target { return self }

        let blendTarget = forDarkBackground ? 1.0 : 0.0
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<16 {
            let midpoint = (lower + upper) / 2
            let candidate = blended(toward: blendTarget, amount: midpoint)
            let reachedTarget = forDarkBackground
                ? candidate.relativeLuminance >= target
                : candidate.relativeLuminance <= target
            if reachedTarget {
                upper = midpoint
            } else {
                lower = midpoint
            }
        }
        return blended(toward: blendTarget, amount: upper)
    }

    private func blended(toward target: Double, amount: Double) -> AccessibleSRGB {
        AccessibleSRGB(
            red: red + (target - red) * amount,
            green: green + (target - green) * amount,
            blue: blue + (target - blue) * amount
        )
    }

    private func linear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        var sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if sanitized.count == 3 {
            sanitized = sanitized.map { "\($0)\($0)" }.joined()
        }
        guard sanitized.count == 6 else { return nil }
        guard let value = UInt64(sanitized, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        let rgb = AccessibleSRGB(red: red, green: green, blue: blue)
        #if os(macOS)
        let dynamicColor = NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let adapted = rgb.adapted(forDarkBackground: dark)
            return NSColor(srgbRed: adapted.red, green: adapted.green, blue: adapted.blue, alpha: 1)
        }
        self.init(nsColor: dynamicColor)
        #else
        let dynamicColor = UIColor { traits in
            let adapted = rgb.adapted(forDarkBackground: traits.userInterfaceStyle == .dark)
            return UIColor(red: adapted.red, green: adapted.green, blue: adapted.blue, alpha: 1)
        }
        self.init(uiColor: dynamicColor)
        #endif
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
