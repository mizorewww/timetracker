import SwiftUI

struct TaskDetailOverviewGrid: View {
    let snapshot: TaskAnalyticsSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            AnalyticsMetric(
                title: AppStrings.localized("task.field.total"),
                value: DurationFormatter.compact(snapshot.overview.grossSeconds),
                footnote: AppStrings.grossTime
            )
            AnalyticsMetric(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(snapshot.overview.wallSeconds),
                footnote: AppStrings.localized("analytics.wall.footnote")
            )
            AnalyticsMetric(
                title: AppStrings.localized("task.detail.direct"),
                value: DurationFormatter.compact(snapshot.directSeconds),
                footnote: AppStrings.localized("task.detail.directFootnote")
            )
            AnalyticsMetric(
                title: AppStrings.localized("task.detail.children"),
                value: DurationFormatter.compact(snapshot.descendantSeconds),
                footnote: AppStrings.localized("task.detail.childrenFootnote")
            )
        }
    }
}

struct TaskDetailAnalysisSection: View {
    @Binding var range: AnalyticsRange
    let snapshot: TaskAnalyticsSnapshot

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("task.detail.analysis"),
            subtitle: AppStrings.localized("task.detail.analysisSubtitle")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker(AppStrings.localized("analytics.range"), selection: $range) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if snapshot.overview.grossSeconds == 0 {
                    EmptyStateRow(title: AppStrings.localized("task.detail.emptyRange"), icon: "chart.bar")
                } else {
                    TaskDetailContributionBar(snapshot: snapshot)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.rhythm.averageSegment"),
                            value: DurationFormatter.compact(snapshot.rhythm.averageSegmentSeconds),
                            iconName: "timer"
                        )
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.rhythm.longest"),
                            value: DurationFormatter.compact(snapshot.rhythm.longestContinuousSeconds),
                            iconName: "arrow.left.and.right"
                        )
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.quality.switches"),
                            value: "\(snapshot.quality.switchCount)",
                            iconName: "arrow.triangle.swap"
                        )
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.quality.shortSegments"),
                            value: "\(snapshot.quality.shortSegmentCount)",
                            iconName: "scissors"
                        )
                    }

                    if !snapshot.childBreakdown.isEmpty {
                        let lastChildBreakdownID = snapshot.childBreakdown.last?.id
                        VStack(spacing: 0) {
                            ForEach(snapshot.childBreakdown) { item in
                                AnalyticsGroupBreakdownRowForTask(item: item, totalSeconds: max(snapshot.overview.grossSeconds, 1))
                                if item.id != lastChildBreakdownID {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TaskDetailContributionBar: View {
    let snapshot: TaskAnalyticsSnapshot

    private var directRatio: CGFloat {
        CGFloat(snapshot.directSeconds) / CGFloat(max(snapshot.overview.grossSeconds, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.blue)
                        .frame(width: max(0, proxy.size.width * directRatio))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.green)
                        .frame(width: max(0, proxy.size.width * (1 - directRatio)))
                }
            }
            .frame(height: 14)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))

            HStack {
                AnalyticsLegendSwatch(color: .blue, title: AppStrings.localized("task.detail.direct"))
                AnalyticsLegendSwatch(color: .green, title: AppStrings.localized("task.detail.children"))
            }
        }
    }
}

private struct TaskDetailMetricCell: View {
    let title: String
    let value: String
    let iconName: String

    var body: some View {
        HStack(spacing: 10) {
            AppRowIcon(systemImage: iconName)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .appCard(padding: 12)
    }
}

private struct AnalyticsGroupBreakdownRowForTask: View {
    let item: AnalyticsGroupBreakdownPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: item.colorHex) ?? .blue)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(item.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int((Double(item.grossSeconds) / Double(max(totalSeconds, 1))) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
    }
}
