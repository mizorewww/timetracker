import SwiftUI

extension OverlappingTimelineContent {
    func timelineLegendRow(_ entry: AnalyticsTimelineEntry) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    timelineLegendIdentity(entry)
                    timelineLegendMetrics(entry)
                }
            } else {
                HStack(spacing: 12) {
                    timelineLegendIdentity(entry)
                    Spacer()
                    timelineLegendMetrics(entry)
                }
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func timelineLegendIdentity(_ entry: AnalyticsTimelineEntry) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: entry.colorHex) ?? .blue)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: entry.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            TaskColorPalette.contrastingForegroundColor(for: entry.colorHex)
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

    private func timelineLegendMetrics(_ entry: AnalyticsTimelineEntry) -> some View {
        HStack(spacing: 12) {
                Text(shortRange(entry))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(DurationFormatter.compact(entry.durationSeconds))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }
    }

    func shortRange(_ entry: AnalyticsTimelineEntry) -> String {
        "\(TimeDisplayFormatter.hourMinute(entry.startedAt))-\(TimeDisplayFormatter.hourMinute(entry.endedAt))"
    }
}
