import SwiftUI

struct AnalyticsOverlapContent: View {
    let overlaps: [OverlapAnalyticsPoint]

    var body: some View {
        let displayedOverlaps = Array(overlaps.prefix(6))
        let lastID = displayedOverlaps.last?.id

        VStack(spacing: 0) {
            if displayedOverlaps.isEmpty {
                EmptyStateRow(
                    title: AppStrings.localized("analytics.empty.overlap"),
                    icon: "rectangle.2.swap"
                )
            } else {
                ForEach(displayedOverlaps) { overlap in
                    AnalyticsOverlapRow(overlap: overlap)
                    if overlap.id != lastID {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct AnalyticsOverlapRow: View {
    let overlap: OverlapAnalyticsPoint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    identity
                    duration
                }
            } else {
                HStack(spacing: 12) {
                    identity
                    Spacer(minLength: 8)
                    duration
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.2.swap")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(overlap.firstTitle) + \(overlap.secondTitle)")
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var duration: some View {
        Text(DurationFormatter.compact(overlap.durationSeconds))
            .font(.subheadline.monospacedDigit())
    }

    private var timeRangeText: String {
        "\(TimeDisplayFormatter.monthDayHourMinute(overlap.start)) - \(TimeDisplayFormatter.hourMinute(overlap.end))"
    }
}
