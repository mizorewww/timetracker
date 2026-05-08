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

struct HourTaskActivity: Identifiable {
    let hour: Int
    let slices: [HourTaskSlice]

    var id: Int { hour }
    var totalSeconds: Int { slices.reduce(0) { $0 + $1.seconds } }
}

struct HourTaskSlice: Identifiable {
    let taskID: UUID
    let title: String
    let symbolName: String
    let colorHex: String
    let seconds: Int

    var id: UUID { taskID }
    var color: Color { Color(hex: colorHex) ?? .blue }
}
