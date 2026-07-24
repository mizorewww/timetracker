import SwiftUI

struct PhoneTodaySummaryRow: View {
    let store: TimeTrackerStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let snapshot = store.todayMetricsSnapshot(now: context.date)
            VStack(spacing: 12) {
                PhoneSummaryMetric(
                    title: AppStrings.grossTime,
                    value: DurationFormatter.compact(snapshot.grossSeconds),
                    systemImage: "square.stack.3d.up",
                    tint: AppColors.grossTime
                )

                if store.preferences.showGrossAndWallTogether {
                    Divider()
                    PhoneSummaryMetric(
                        title: AppStrings.wallTime,
                        value: DurationFormatter.compact(snapshot.wallSeconds),
                        systemImage: "timeline.selection",
                        tint: AppColors.wallTime
                    )
                }
            }
        }
    }
}

struct PhoneSummaryMetric: View {
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

