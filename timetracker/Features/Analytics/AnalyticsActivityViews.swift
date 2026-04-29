import SwiftUI

struct TodayActivityCard: View {
    @ObservedObject var store: TimeTrackerStore
    let segments: [TimeSegment]
    let now: Date

    private var calendar: Calendar { .current }

    private var dayInterval: DateInterval {
        calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
    }

    private var hourly: [HourTaskActivity] {
        (0..<24).map { hour in
            let start = calendar.date(byAdding: .hour, value: hour, to: dayInterval.start) ?? dayInterval.start
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3_600)
            let interval = DateInterval(start: start, end: min(end, dayInterval.end))
            var secondsByTaskID: [UUID: Int] = [:]

            for segment in segments where segment.deletedAt == nil {
                guard let clipped = clippedInterval(for: segment, in: interval) else { continue }
                secondsByTaskID[segment.taskID, default: 0] += Int(clipped.end.timeIntervalSince(clipped.start))
            }

            let slices = secondsByTaskID.compactMap { taskID, seconds -> HourTaskSlice? in
                guard seconds > 0 else { return nil }
                let task = store.task(for: taskID)
                return HourTaskSlice(
                    taskID: taskID,
                    title: task?.title ?? AppStrings.localized("task.deleted"),
                    symbolName: task?.iconName ?? "checkmark.circle",
                    colorHex: task?.colorHex ?? "0A84FF",
                    seconds: seconds
                )
            }
            .sorted { $0.seconds > $1.seconds }

            return HourTaskActivity(hour: hour, slices: slices)
        }
    }

    private var totalSeconds: Int {
        hourly.reduce(0) { $0 + $1.totalSeconds }
    }

    private var legendItems: [HourTaskSlice] {
        let grouped = Dictionary(grouping: hourly.flatMap(\.slices), by: \.taskID)
        return grouped.compactMap { _, slices -> HourTaskSlice? in
            guard let first = slices.first else { return nil }
            return HourTaskSlice(
                taskID: first.taskID,
                title: first.title,
                symbolName: first.symbolName,
                colorHex: first.colorHex,
                seconds: slices.reduce(0) { $0 + $1.seconds }
            )
        }
        .sorted { $0.seconds > $1.seconds }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.hourDistribution.title"), subtitle: AppStrings.localized("analytics.hourDistribution.subtitle")) {
            if totalSeconds == 0 {
                EmptyStateRow(title: AppStrings.localized("analytics.empty.todayTaskTime"), icon: "chart.bar")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DurationFormatter.compact(totalSeconds))
                                .font(.title3.weight(.semibold).monospacedDigit())
                            Text(AppStrings.todayTracked)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(AppStrings.localized("analytics.hourDistribution.taskColorHint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    hourlyBars

                    HStack {
                        ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                            Text(String(format: "%02d", hour))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if hour != 24 {
                                Spacer()
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(legendItems) { item in
                            AnalyticsLegendSwatch(color: item.color, title: item.title)
                        }
                    }
                }
            }
        }
    }

    private var hourlyBars: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(hourly) { point in
                    HourTaskActivityBar(
                        point: point,
                        availableHeight: proxy.size.height
                    )
                }
            }
        }
        .frame(height: 150)
        .padding(.horizontal, 2)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func clippedInterval(for segment: TimeSegment, in interval: DateInterval) -> DateInterval? {
        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return DateInterval(start: start, end: clippedEnd)
    }
}

private struct HourTaskActivity: Identifiable {
    let hour: Int
    let slices: [HourTaskSlice]

    var id: Int { hour }
    var totalSeconds: Int { slices.reduce(0) { $0 + $1.seconds } }
}

private struct HourTaskSlice: Identifiable {
    let taskID: UUID
    let title: String
    let symbolName: String
    let colorHex: String
    let seconds: Int

    var id: UUID { taskID }
    var color: Color { Color(hex: colorHex) ?? .blue }
}

struct HourStackLayoutInput: Equatable {
    let id: UUID
    let seconds: Int
}

struct HourStackLayoutItem: Identifiable, Equatable {
    let id: UUID
    let height: Double
}

enum HourStackLayoutEngine {
    static func maxVisibleSliceCount(availableHeight: Double, minSliceHeight: Double) -> Int {
        guard availableHeight > 0, minSliceHeight > 0 else { return 0 }
        return max(1, Int(floor(availableHeight / minSliceHeight)) - 1)
    }

    static func layout(
        inputs: [HourStackLayoutInput],
        availableHeight: Double,
        minSliceHeight: Double,
        maxItems: Int? = nil
    ) -> [HourStackLayoutItem] {
        let sorted = inputs
            .filter { $0.seconds > 0 }
            .sorted { lhs, rhs in
                if lhs.seconds == rhs.seconds {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.seconds > rhs.seconds
            }
        guard availableHeight > 0, minSliceHeight > 0, !sorted.isEmpty else { return [] }

        let capacity = maxItems ?? maxVisibleSliceCount(availableHeight: availableHeight, minSliceHeight: minSliceHeight)
        let visible = Array(sorted.prefix(capacity))
        let effectiveMinSliceHeight = min(minSliceHeight, availableHeight / Double(max(visible.count, 1)))
        let totalSeconds = max(1, visible.reduce(0) { $0 + $1.seconds })
        var heights = visible.map { input in
            availableHeight * Double(input.seconds) / Double(totalSeconds)
        }

        var deficit = 0.0
        for index in heights.indices where heights[index] < effectiveMinSliceHeight {
            deficit += effectiveMinSliceHeight - heights[index]
            heights[index] = effectiveMinSliceHeight
        }

        while deficit > 0.0001 {
            guard let donorIndex = heights.indices
                .filter({ heights[$0] > effectiveMinSliceHeight })
                .max(by: { heights[$0] < heights[$1] })
            else {
                break
            }
            let take = min(deficit, heights[donorIndex] - effectiveMinSliceHeight)
            heights[donorIndex] -= take
            deficit -= take
        }

        return zip(visible, heights).map { input, height in
            HourStackLayoutItem(id: input.id, height: height)
        }
    }
}

private struct HourTaskActivityBar: View {
    let point: HourTaskActivity
    let availableHeight: CGFloat
    private let sliceSpacing: CGFloat = 1
    private let cornerRadius: CGFloat = 4

    private var minSliceHeight: CGFloat {
        max(5, min(8, availableHeight * 0.05))
    }

    private var visibleSliceCount: Int {
        let activeSliceCount = point.slices.filter { $0.seconds > 0 }.count
        let capacity = HourStackLayoutEngine.maxVisibleSliceCount(
            availableHeight: Double(max(0, availableHeight)),
            minSliceHeight: Double(minSliceHeight)
        )
        return min(activeSliceCount, capacity)
    }

    private var contentHeight: CGFloat {
        let sliceCount = CGFloat(max(visibleSliceCount - 1, 0))
        return max(0, availableHeight - sliceCount * sliceSpacing)
    }

    private var renderedSlices: [RenderedHourTaskSlice] {
        let inputs = point.slices.map { HourStackLayoutInput(id: $0.id, seconds: $0.seconds) }
        let layouts = HourStackLayoutEngine.layout(
            inputs: inputs,
            availableHeight: Double(max(0, contentHeight)),
            minSliceHeight: Double(minSliceHeight),
            maxItems: visibleSliceCount
        )
        let slicesByID = Dictionary(uniqueKeysWithValues: point.slices.map { ($0.id, $0) })
        return layouts.compactMap { layout in
            guard let slice = slicesByID[layout.id] else { return nil }
            return RenderedHourTaskSlice(slice: slice, height: CGFloat(layout.height))
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if point.totalSeconds > 0, renderedSlices.isEmpty == false {
                VStack(spacing: sliceSpacing) {
                    ForEach(Array(renderedSlices.reversed())) { rendered in
                        Rectangle()
                            .fill(rendered.slice.color)
                            .frame(height: rendered.height)
                    }
                }
                .frame(height: availableHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .help("\(String(format: "%02d:00", point.hour)) \(DurationFormatter.compact(point.totalSeconds))")
    }
}

private struct RenderedHourTaskSlice: Identifiable {
    let slice: HourTaskSlice
    let height: CGFloat

    var id: UUID { slice.id }
}

private struct AnalyticsLegendSwatch: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

