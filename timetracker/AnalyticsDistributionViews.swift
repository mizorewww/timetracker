import SwiftUI

struct TaskDonutCard: View {
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
        AnalyticsChartCard(title: AppStrings.localized("analytics.taskUsage.title"), subtitle: AppStrings.localized("analytics.taskUsage.subtitle")) {
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
    private let lineWidth: CGFloat = 26

    private var total: Int {
        max(1, slices.reduce(0) { $0 + $1.grossSeconds })
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: lineWidth)

            if slices.count == 1, let slice = slices.first {
                Circle()
                    .stroke(slice.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            } else {
                ForEach(segmentData) { segment in
                    DonutSegmentShape(
                        startAngle: .degrees(segment.startDegrees - 90),
                        endAngle: .degrees(segment.endDegrees - 90),
                        inset: lineWidth / 2
                    )
                    .stroke(segment.slice.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                }
            }

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

    private var segmentData: [DonutSegmentData] {
        var cursor = 0.0
        let gap = slices.count > 1 ? min(2.0, 18.0 / Double(slices.count)) : 0
        return slices.map { slice in
            let span = Double(slice.grossSeconds) / Double(total) * 360
            let start = cursor + gap / 2
            let end = max(start, cursor + span - gap / 2)
            defer { cursor += span }
            return DonutSegmentData(slice: slice, startDegrees: start, endDegrees: end)
        }
    }
}

private struct DonutSegmentData: Identifiable {
    let slice: TaskDistributionSlice
    let startDegrees: Double
    let endDegrees: Double

    var id: String { slice.id }
}

private struct DonutSegmentShape: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
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

