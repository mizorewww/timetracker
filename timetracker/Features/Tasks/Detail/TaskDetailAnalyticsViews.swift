import SwiftUI

struct TaskDetailAnalysisSection: View {
    @Binding var range: AnalyticsRange
    let snapshot: TaskAnalyticsSnapshot
    let isRefreshing: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            rangePicker

            if snapshot.overview.grossSeconds == 0 {
                EmptyStateRow(title: AppStrings.localized("task.detail.emptyRange"), icon: "chart.bar")
            } else {
                TaskDetailContributionBar(snapshot: snapshot)
                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.rhythm.averageSegment"),
                    value: DurationFormatter.compact(snapshot.rhythm.averageSegmentSeconds),
                    systemImage: "timer",
                    tint: .blue
                )
                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.rhythm.longest"),
                    value: DurationFormatter.compact(snapshot.rhythm.longestContinuousSeconds),
                    systemImage: "arrow.left.and.right",
                    tint: .indigo
                )
                TaskDetailValueRow(
                    title: AppStrings.localized("analytics.quality.switches"),
                    value: "\(snapshot.quality.switchCount)",
                    systemImage: "arrow.triangle.swap",
                    tint: .orange
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
                if isRefreshing {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(AppStrings.localized("analytics.loading"))
                        .accessibilityIdentifier("task.detail.analyticsRefreshing")
                }
            }
        } footer: {
            Text(.app("task.detail.analysisSubtitle"))
        }
        .accessibilityIdentifier("task.detail.analysis")
    }

    @ViewBuilder
    private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(AppStrings.localized("analytics.range"), selection: $range) {
                ForEach(AnalyticsRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("task.detail.analysis.range")
        } else {
            Picker(AppStrings.localized("analytics.range"), selection: $range) {
                ForEach(AnalyticsRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
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
