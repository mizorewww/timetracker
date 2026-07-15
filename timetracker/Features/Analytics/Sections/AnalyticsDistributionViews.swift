import Charts
import SwiftUI

struct TaskDonutContent: View {
    let tasks: [TaskAnalyticsPoint]
    let totalSeconds: Int

    private var distribution: TaskDistributionPresentation {
        TaskDistributionPresentation.make(
            tasks: tasks,
            reportedTotalSeconds: totalSeconds,
            otherTitle: AppStrings.localized("analytics.taskUsage.other")
        )
    }

    var body: some View {
        let presentation = distribution
        let displayedSlices = presentation.slices

        if displayedSlices.isEmpty {
            EmptyStateRow(title: AppStrings.localized("analytics.empty.rangeTaskTime"), icon: "chart.pie")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                StableDonutChart(
                    slices: displayedSlices,
                    totalSeconds: presentation.totalSeconds
                )
                .frame(maxWidth: .infinity)
                distributionLegend(
                    displayedSlices,
                    totalSeconds: presentation.totalSeconds
                )
            }
        }
    }

    private func distributionLegend(
        _ displayedSlices: [TaskDistributionSlice],
        totalSeconds: Int
    ) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(displayedSlices) { slice in
                TaskDistributionLegendItem(slice: slice, totalSeconds: totalSeconds)
            }
        }
    }
}

struct TaskDistributionPresentation {
    let slices: [TaskDistributionSlice]
    let totalSeconds: Int

    static func make(
        tasks: [TaskAnalyticsPoint],
        reportedTotalSeconds: Int,
        maximumSliceCount: Int = 8,
        otherTitle: String
    ) -> TaskDistributionPresentation {
        let candidates = tasks.compactMap { task -> TaskDistributionSlice? in
            guard task.grossSeconds > 0 else { return nil }
            return TaskDistributionSlice(
                id: task.taskID.uuidString,
                title: task.title,
                subtitle: task.path,
                symbolName: task.iconName ?? "checkmark.circle",
                colorHex: task.colorHex ?? "0A84FF",
                grossSeconds: task.grossSeconds
            )
        }
        .sorted {
            if $0.grossSeconds != $1.grossSeconds {
                return $0.grossSeconds > $1.grossSeconds
            }
            return $0.id < $1.id
        }

        let accountedSeconds = candidates.reduce(0) { $0 + $1.grossSeconds }
        let effectiveTotal = max(max(0, reportedTotalSeconds), accountedSeconds)
        var otherSeconds = effectiveTotal - accountedSeconds
        let sliceLimit = max(1, maximumSliceCount)
        let needsOverflowSlice = candidates.count + (otherSeconds > 0 ? 1 : 0) > sliceLimit
        let visibleTaskCount = needsOverflowSlice ? max(0, sliceLimit - 1) : candidates.count
        var displayed = Array(candidates.prefix(visibleTaskCount))

        if needsOverflowSlice {
            otherSeconds += candidates.dropFirst(visibleTaskCount).reduce(0) {
                $0 + $1.grossSeconds
            }
        }
        if otherSeconds > 0 {
            displayed.append(
                TaskDistributionSlice(
                    id: "analytics-task-distribution-other",
                    title: otherTitle,
                    subtitle: "",
                    symbolName: "ellipsis.circle",
                    colorHex: "8E8E93",
                    grossSeconds: otherSeconds
                )
            )
        }

        return TaskDistributionPresentation(
            slices: displayed,
            totalSeconds: effectiveTotal
        )
    }
}

struct TaskDistributionSlice: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let colorHex: String
    let grossSeconds: Int

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    var accessibilityTitle: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}

private struct StableDonutChart: View {
    let slices: [TaskDistributionSlice]
    let totalSeconds: Int

    var body: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value(AppStrings.grossTime, slice.grossSeconds),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(slice.color)
            .accessibilityLabel(slice.accessibilityTitle)
            .accessibilityValue(DurationFormatter.compact(slice.grossSeconds))
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 2) {
                Text(DurationFormatter.compact(totalSeconds))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(.app("analytics.total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 190, height: 190)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(AppStrings.localized("analytics.taskUsage.title"))
    }
}

private struct TaskDistributionLegendItem: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let slice: TaskDistributionSlice
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: slice.symbolName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(slice.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(slice.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(detailText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var percentage: Int {
        Int(
            ((Double(slice.grossSeconds) / Double(max(totalSeconds, 1))) * 100)
                .rounded()
        )
    }

    private var detailText: String {
        let measurement = "\(DurationFormatter.compact(slice.grossSeconds)) · \(percentage)%"
        return slice.subtitle.isEmpty ? measurement : "\(slice.subtitle) · \(measurement)"
    }
}
