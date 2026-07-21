import SwiftUI

struct ActivityHeatmapPalettePreview: View {
    let colorHex: String

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ActivityHeatmapIntensity.allCases, id: \.rawValue) { intensity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(palette.color(for: intensity))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.localized("home.heatmap.palette.accessibilityLabel"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: colorHex))
    }

    private var palette: ActivityHeatmapPalette {
        ActivityHeatmapPalette(
            colorHex: colorHex,
            colorScheme: colorScheme,
            colorSchemeContrast: colorSchemeContrast
        )
    }
}

struct ActivityHeatmapPalette {
    let colorHex: String
    let colorScheme: ColorScheme
    let colorSchemeContrast: ColorSchemeContrast

    func color(for intensity: ActivityHeatmapIntensity) -> Color {
        if intensity == .none {
            return Color.secondary.opacity(emptyOpacity)
        }
        let opacity: Double = switch intensity {
        case .none: emptyOpacity
        case .low: colorScheme == .dark ? 0.42 : 0.32
        case .medium: colorScheme == .dark ? 0.60 : 0.50
        case .high: colorScheme == .dark ? 0.78 : 0.72
        case .maximum: 1
        }
        let contrastBoost = colorSchemeContrast == .increased ? 0.10 : 0
        return (Color(hex: colorHex) ?? .blue)
            .opacity(min(1, opacity + contrastBoost))
    }

    private var emptyOpacity: Double {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? 0.30 : 0.20
        }
        return colorScheme == .dark ? 0.18 : 0.11
    }
}
