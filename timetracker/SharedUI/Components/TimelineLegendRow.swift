import SwiftUI

struct TimelineLegendRow: View {
    let entry: AnalyticsTimelineEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    identity
                    metrics
                }
            } else {
                HStack(spacing: 12) {
                    identity
                    Spacer()
                    metrics
                }
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: entry.colorHex) ?? .blue)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: entry.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            TaskColorPalette.contrastingForegroundColor(
                                for: entry.colorHex
                            )
                        )
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(entry.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            Text(shortRange)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Text(DurationFormatter.compact(entry.durationSeconds))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
    }

    private var shortRange: String {
        "\(TimeDisplayFormatter.hourMinute(entry.startedAt))-\(TimeDisplayFormatter.hourMinute(entry.endedAt))"
    }
}
