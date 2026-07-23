import SwiftUI

struct TaskDetailAppleHealthPeriodSection: View {
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?

    private var periodTitle: String {
        AnalyticsPeriodText.title(
            for: range,
            date: referenceDate,
            liveNow: liveNow
        )
    }

    var body: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    TaskDetailAnalyticsRangePicker(range: $range)
                        .fixedSize(horizontal: true, vertical: false)
                    AnalyticsPeriodNavigator(
                        range: range,
                        referenceDate: $referenceDate,
                        liveNow: liveNow,
                        monthNavigationAnchor: $monthNavigationAnchor
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 8) {
                    TaskDetailAnalyticsRangePicker(range: $range)
                    HStack(spacing: 8) {
                        AnalyticsPeriodNavigator(
                            range: range,
                            referenceDate: $referenceDate,
                            liveNow: liveNow,
                            monthNavigationAnchor: $monthNavigationAnchor
                        )
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AppStrings.localized("analytics.range"))
            .accessibilityValue(periodTitle)
            .accessibilityIdentifier(
                "task.detail.appleHealth.periodFilter"
            )
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AppStrings.localized("analytics.range"))
                Spacer(minLength: 8)
                Text(periodTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier(
                        "task.detail.appleHealth.periodTitle"
                    )
            }
        }
    }

}

struct TaskDetailAnalysisSection: View {
    @Binding var range: AnalyticsRange
    let snapshot: TaskAnalyticsSnapshot
    let isRefreshing: Bool
    let retryAppleHealth: () -> Void

    var body: some View {
        Section {
            if snapshot.source == .tracked {
                TaskDetailAnalyticsRangePicker(range: $range)
            }

            if snapshot.overview.grossSeconds == 0,
               snapshot.source == .appleHealth {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        AppStrings.localized(
                            "task.detail.appleHealth.empty.title"
                        ),
                        systemImage: "heart.text.square"
                    )
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier(
                        "task.detail.appleHealth.empty"
                    )

                    Text(.app("task.detail.appleHealth.empty.message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(
                            "task.detail.appleHealth.empty.message"
                        )
                }
                .padding(.vertical, 3)

                TaskDetailAppleHealthRetryButton(
                    action: retryAppleHealth
                )
            } else if snapshot.overview.grossSeconds == 0 {
                EmptyStateRow(
                    title: AppStrings.localized("task.detail.emptyRange"),
                    icon: "chart.bar"
                )
                .accessibilityIdentifier("task.detail.analysis.empty")
            } else if snapshot.source == .appleHealth {
                DailyTimeSeriesChart(
                    points: snapshot.daily,
                    mode: .wallBarsAndGrossLine,
                    accessibilityTitle: AppStrings.localized(
                        "task.detail.appleHealth.history.chart"
                    )
                )
                .frame(height: 260)
                .accessibilityIdentifier("task.detail.history.chart")
                .accessibilityValue(snapshot.range.rawValue)

                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.rhythm.averageSegment"),
                    value: DurationFormatter.compact(
                        snapshot.rhythm.averageSegmentSeconds
                    ),
                    systemImage: "timer",
                    tint: .blue,
                    accessibilityIdentifier: "task.detail.analysis.average"
                )
                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.rhythm.longest"),
                    value: DurationFormatter.compact(
                        snapshot.rhythm.longestContinuousSeconds
                    ),
                    systemImage: "arrow.left.and.right",
                    tint: .indigo,
                    accessibilityIdentifier: "task.detail.analysis.longest"
                )
            } else {
                TaskDetailContributionBar(snapshot: snapshot)
                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.rhythm.averageSegment"),
                    value: DurationFormatter.compact(snapshot.rhythm.averageSegmentSeconds),
                    systemImage: "timer",
                    tint: .blue,
                    accessibilityIdentifier: "task.detail.analysis.average"
                )
                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.rhythm.longest"),
                    value: DurationFormatter.compact(snapshot.rhythm.longestContinuousSeconds),
                    systemImage: "arrow.left.and.right",
                    tint: .indigo,
                    accessibilityIdentifier: "task.detail.analysis.longest"
                )
                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.quality.switches"),
                    value: "\(snapshot.quality.switchCount)",
                    systemImage: "arrow.triangle.swap",
                    tint: .orange,
                    accessibilityIdentifier: "task.detail.analysis.switches"
                )

                ForEach(snapshot.childBreakdown) { item in
                    AnalyticsGroupBreakdownRowForTask(
                        item: item,
                        totalSeconds: max(snapshot.overview.grossSeconds, 1)
                    )
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text(AppStrings.localized("task.detail.analysis"))
                    .accessibilityIdentifier("task.detail.analysis")
                if isRefreshing {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(AppStrings.localized("analytics.loading"))
                        .accessibilityIdentifier(
                            snapshot.source == .appleHealth
                                ? "task.detail.appleHealth.refreshing"
                                : "task.detail.analyticsRefreshing"
                        )
                }
            }
        } footer: {
            Text(
                .app(
                    snapshot.source == .appleHealth
                        ? "task.detail.appleHealth.analysisSubtitle"
                        : "task.detail.analysisSubtitle"
                )
            )
        }
    }

}

private struct TaskDetailAnalyticsRangePicker: View {
    @Binding var range: AnalyticsRange
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(AppStrings.localized("analytics.range"), selection: $range) {
                ForEach(AnalyticsRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .accessibilityIdentifier("task.detail.analysis.range")
        } else {
            Picker(AppStrings.localized("analytics.range"), selection: $range) {
                ForEach(AnalyticsRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier("task.detail.analysis.range")
        }
    }
}

private struct TaskDetailContributionBar: View {
    let snapshot: TaskAnalyticsSnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

            legend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppStrings.localized("task.detail.analysis"))
        .accessibilityValue(
            "\(AppStrings.localized("task.detail.direct")) \(Int(directRatio * 100))%, " +
            "\(AppStrings.localized("task.detail.children")) \(100 - Int(directRatio * 100))%"
        )
    }

    @ViewBuilder
    private var legend: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                AnalyticsLegendSwatch(color: .blue, title: AppStrings.localized("task.detail.direct"))
                AnalyticsLegendSwatch(color: .green, title: AppStrings.localized("task.detail.children"))
            }
        } else {
            HStack {
                AnalyticsLegendSwatch(color: .blue, title: AppStrings.localized("task.detail.direct"))
                AnalyticsLegendSwatch(color: .green, title: AppStrings.localized("task.detail.children"))
            }
        }
    }
}

private struct AnalyticsGroupBreakdownRowForTask: View {
    let item: AnalyticsGroupBreakdownPoint
    let totalSeconds: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    breakdownIdentity
                    breakdownTotals
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) {
                    breakdownIdentity
                    Spacer(minLength: 8)
                    breakdownTotals
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var breakdownIdentity: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: item.colorHex) ?? .blue)
                .frame(minWidth: 30, minHeight: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakdownTotals: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(DurationFormatter.compact(item.grossSeconds))
                .font(.subheadline.monospacedDigit())
            Text("\(Int((Double(item.grossSeconds) / Double(max(totalSeconds, 1))) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
