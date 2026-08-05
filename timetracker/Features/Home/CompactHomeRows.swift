import SwiftUI

struct CompactTodaySummaryRow: View {
    let store: TimeTrackerStore
    @Environment(\.todayClockIsActive) private var clockIsActive

    var body: some View {
        if clockIsActive {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                summaryContent(snapshot: store.todayMetricsSnapshot(now: context.date))
            }
        } else {
            // Static render while the Today tab is not selected.
            summaryContent(snapshot: store.todayMetricsSnapshot(now: Date()))
        }
    }

    private func summaryContent(snapshot: TodayMetricsSnapshot) -> some View {
        VStack(spacing: 12) {
            CompactSummaryMetric(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(snapshot.grossSeconds),
                systemImage: "square.stack.3d.up",
                tint: AppColors.grossTime
            )

            if store.preferences.showGrossAndWallTogether {
                Divider()
                CompactSummaryMetric(
                    title: AppStrings.wallTime,
                    value: DurationFormatter.compact(snapshot.wallSeconds),
                    systemImage: "timeline.selection",
                    tint: AppColors.wallTime
                )
            }
        }
    }
}

struct CompactSummaryMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(title)
                            .font(.headline)
                    } icon: {
                        AppRowIcon(systemImage: systemImage, tint: tint)
                    }
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    AppRowIcon(systemImage: systemImage, tint: tint)
                    Text(title)
                    Spacer(minLength: 12)
                    Text(value)
                        .font(.headline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
