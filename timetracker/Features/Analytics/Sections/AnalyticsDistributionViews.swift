import Charts
import SwiftUI

struct TaskDonutCard: View {
    let tasks: [TaskAnalyticsPoint]
    let totalSeconds: Int

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.taskUsage.title"), subtitle: AppStrings.localized("analytics.taskUsage.subtitle")) {
            TaskDonutContent(tasks: tasks, totalSeconds: totalSeconds)
        }
    }
}

struct TaskDonutContent: View {
    let tasks: [TaskAnalyticsPoint]
    let totalSeconds: Int

    private var slices: [TaskDistributionSlice] {
        tasks.compactMap { task -> TaskDistributionSlice? in
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
        .sorted { $0.grossSeconds > $1.grossSeconds }
        .prefix(8)
        .map { $0 }
    }

    var body: some View {
        if tasks.isEmpty {
            EmptyStateRow(title: AppStrings.localized("analytics.empty.rangeTaskTime"), icon: "chart.pie")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                StableDonutChart(slices: slices, totalSeconds: max(totalSeconds, 1))
                    .frame(maxWidth: .infinity)
                distributionLegend
            }
        }
    }

    private var distributionLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(slices) { slice in
                TaskDistributionLegendItem(slice: slice, totalSeconds: max(totalSeconds, 1))
            }
        }
    }
}

private struct TaskDistributionSlice: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let colorHex: String
    let grossSeconds: Int

    var color: Color {
        Color(hex: colorHex) ?? .blue
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
        .accessibilityElement(children: .combine)
    }
}

private struct TaskDistributionLegendItem: View {
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
                    .lineLimit(1)
                Text("\(DurationFormatter.compact(slice.grossSeconds)) · \(percentage)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var percentage: Int {
        Int((Double(slice.grossSeconds) / Double(max(totalSeconds, 1))) * 100)
    }
}
