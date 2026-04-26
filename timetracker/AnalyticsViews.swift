import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var range: AnalyticsRange = .today

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let overview = store.analyticsOverview(for: range, now: context.date)
            let daily = store.dailyBreakdown(range: range, now: context.date)
            let tasks = store.taskBreakdown(range: range, now: context.date)
            let overlaps = store.overlapSegments(range: range, now: context.date)
            let todaySegments = store.todaySegments

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            if horizontalSizeClass != .compact {
                                analyticsTitle(range)
                            }
                            Spacer()
                            analyticsRangePicker
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            if horizontalSizeClass != .compact {
                                analyticsTitle(range)
                            }
                            analyticsRangePicker
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        AnalyticsMetric(title: "Wall Time", value: DurationFormatter.compact(overview.wallSeconds), footnote: AppStrings.localized("analytics.wall.footnote"))
                        AnalyticsMetric(title: "Gross Time", value: DurationFormatter.compact(overview.grossSeconds), footnote: AppStrings.localized("analytics.gross.footnote"))
                        AnalyticsMetric(title: "Overlap", value: DurationFormatter.compact(overview.overlapSeconds), footnote: AppStrings.localized("analytics.overlap.footnote"))
                        AnalyticsMetric(title: "Pomodoros", value: "\(overview.pomodoroCount)", footnote: AppStrings.localized("analytics.pomodoros.footnote"))
                    }

                    if range == .today {
                        OverlappingTimelineCard(store: store, segments: todaySegments, now: context.date)
                        TaskDonutCard(tasks: tasks, totalSeconds: max(overview.grossSeconds, 1))
                    } else {
                        AnalyticsChartCard(title: AppStrings.localized("analytics.dailyTrend.title"), subtitle: AppStrings.localized("analytics.dailyTrend.subtitle")) {
                            Chart(daily) { point in
                                BarMark(
                                    x: .value("Day", point.label),
                                    y: .value("Wall Minutes", point.wallSeconds / 60)
                                )
                                .foregroundStyle(.blue)

                                LineMark(
                                    x: .value("Day", point.label),
                                    y: .value("Gross Minutes", point.grossSeconds / 60)
                                )
                                .foregroundStyle(.green)
                                .symbol(.circle)
                            }
                            .chartYAxisLabel(AppStrings.localized("analytics.minutes"))
                            .frame(height: 240)
                        }
                    }

                    AnalyticsChartCard(title: AppStrings.localized("analytics.taskRank.title"), subtitle: AppStrings.localized("analytics.taskRank.subtitle")) {
                        if tasks.isEmpty {
                            EmptyStateRow(title: AppStrings.localized("analytics.empty.rangeTaskTime"), icon: "chart.bar")
                        } else {
                            Chart(tasks.prefix(8).map { $0 }) { task in
                                BarMark(
                                    x: .value("Minutes", task.grossSeconds / 60),
                                    y: .value("Task", task.title)
                                )
                                .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                            }
                            .chartXAxisLabel(AppStrings.localized("analytics.grossMinutes"))
                            .frame(height: max(220, CGFloat(min(tasks.count, 8)) * 34))
                        }
                    }

                    AnalyticsChartCard(title: AppStrings.localized("analytics.topTasks.title"), subtitle: AppStrings.localized("analytics.topTasks.subtitle")) {
                        VStack(spacing: 0) {
                            if tasks.isEmpty {
                                EmptyStateRow(title: AppStrings.localized("analytics.empty.topTasks"), icon: "list.number")
                            } else {
                                ForEach(tasks.prefix(6)) { task in
                                    AnalyticsTaskRow(task: task, totalSeconds: max(overview.grossSeconds, 1))
                                    if task.id != tasks.prefix(6).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    AnalyticsChartCard(title: AppStrings.localized("analytics.overlap.title"), subtitle: AppStrings.localized("analytics.overlap.subtitle")) {
                        VStack(spacing: 0) {
                            if overlaps.isEmpty {
                                EmptyStateRow(title: AppStrings.localized("analytics.empty.overlap"), icon: "rectangle.2.swap")
                            } else {
                                ForEach(overlaps.prefix(6)) { overlap in
                                    OverlapRow(overlap: overlap)
                                    if overlap.id != overlaps.prefix(6).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(AppStrings.analytics)
        .background(AppColors.background)
    }

    private func analyticsTitle(_ range: AnalyticsRange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
                            Text(AppStrings.analytics)
                                .font(.largeTitle.bold())
                            Text(range == .today ? AppStrings.localized("analytics.header.today") : AppStrings.localized("analytics.header.other"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
    }

    private var analyticsRangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }
}

struct AnalyticsMetric: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }
}

struct AnalyticsChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }
}

struct OverlappingTimelineCard: View {
    @ObservedObject var store: TimeTrackerStore
    let segments: [TimeSegment]
    let now: Date

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: now) ?? DateInterval(start: Calendar.current.startOfDay(for: now), duration: 86_400)
    }

    private var displayInterval: DateInterval {
        layoutResult.displayInterval
    }

    private var visibleSegments: [TimeSegment] {
        segments
            .filter { $0.deletedAt == nil && ($0.endedAt ?? now) > dayInterval.start && $0.startedAt < dayInterval.end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    private var laneEntries: [TimelineLaneEntry] {
        let segmentsByID = Dictionary(uniqueKeysWithValues: visibleSegments.map { ($0.id, $0) })
        return layoutResult.entries.enumerated().compactMap { index, entry in
            guard let segment = segmentsByID[entry.id] else { return nil }
            return TimelineLaneEntry(
                segment: segment,
                lane: entry.lane,
                labelIndex: index,
                interval: entry.item.interval
            )
        }
    }

    private var layoutItems: [TimelineLayoutItem] {
        visibleSegments.map { segment in
            TimelineLayoutItem(
                id: segment.id,
                startedAt: segment.startedAt,
                endedAt: segment.endedAt ?? now
            )
        }
    }

    private var layoutResult: TimelineLayoutResult {
        TimelineLayoutEngine.layout(
            items: layoutItems,
            dayInterval: dayInterval,
            minimumLaneGap: minimumLaneGap
        )
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.timeline.title"), subtitle: AppStrings.localized("analytics.timeline.subtitle")) {
            if visibleSegments.isEmpty {
                EmptyStateRow(title: AppStrings.localized("analytics.timeline.empty"), icon: "timeline.selection")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if isCompact {
                        verticalTimeline
                            .frame(height: 520)
                    } else {
                        horizontalTimeline
                            .frame(height: horizontalTimelineHeight)
                    }

                    Divider()

                    VStack(spacing: 0) {
                        ForEach(visibleSegments) { segment in
                            timelineLegendRow(segment)
                            if segment.id != visibleSegments.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var isCompact: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var laneCount: Int {
        (laneEntries.map(\.lane).max() ?? 0) + 1
    }

    private var minimumLaneGap: TimeInterval {
        60
    }

    private var horizontalTimelineHeight: CGFloat {
        max(120, CGFloat(laneCount) * 34 + 34)
    }

    private var horizontalTimeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                horizontalHourGrid(width: proxy.size.width, height: proxy.size.height)
                ForEach(laneEntries) { entry in
                    horizontalBar(entry: entry, width: proxy.size.width)
                }
            }
        }
    }

    private var verticalTimeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                verticalHourGrid(width: proxy.size.width, height: proxy.size.height)
                ForEach(laneEntries) { entry in
                    verticalBar(entry: entry, width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
    }

    private func horizontalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourTicks(), id: \.self) { tick in
                let ratio = tick.timeIntervalSince(displayInterval.start) / displayInterval.duration
                let x = width * CGFloat(ratio)
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 1, height: height - 24)
                    Text(hourLabel(tick))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.92)
                            .frame(width: 52, alignment: .leading)
                }
                .offset(x: min(max(0, x), width - 52))
            }
        }
    }

    private func verticalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourTicks(), id: \.self) { tick in
                let ratio = tick.timeIntervalSince(displayInterval.start) / displayInterval.duration
                let y = height * CGFloat(ratio)
                HStack(spacing: 8) {
                    Text(hourLabel(tick))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .frame(width: 56, alignment: .trailing)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.16))
                        .frame(height: 1)
                }
                .offset(y: min(max(0, y - 6), height - 12))
            }
        }
    }

    private func horizontalBar(entry: TimelineLaneEntry, width: CGFloat) -> some View {
        let segment = entry.segment
        let interval = entry.interval
        let startRatio = interval.start.timeIntervalSince(displayInterval.start) / displayInterval.duration
        let durationRatio = interval.duration / displayInterval.duration
        let task = store.task(for: segment.taskID)
        let barWidth = max(18, width * CGFloat(durationRatio))
        let x = width * CGFloat(startRatio)

        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(hex: task?.colorHex) ?? .blue)
            .frame(width: barWidth, height: 24)
            .overlay {
                Image(systemName: task?.iconName ?? "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .offset(x: x, y: CGFloat(entry.lane) * 34 + 16)
            .help("\(store.displayTitle(for: segment)) \(shortRange(segment))")
    }

    private func verticalBar(entry: TimelineLaneEntry, width: CGFloat, height: CGFloat) -> some View {
        let segment = entry.segment
        let interval = entry.interval
        let startRatio = interval.start.timeIntervalSince(displayInterval.start) / displayInterval.duration
        let durationRatio = interval.duration / displayInterval.duration
        let task = store.task(for: segment.taskID)
        let leftAxis: CGFloat = 68
        let laneWidth = max(22, min(38, (width - leftAxis - 12) / CGFloat(max(laneCount, 1)) - 8))
        let barHeight = max(20, height * CGFloat(durationRatio))
        let x = leftAxis + CGFloat(entry.lane) * (laneWidth + 8)
        let y = height * CGFloat(startRatio)

        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: task?.colorHex) ?? .blue)
            .frame(width: laneWidth, height: barHeight)
            .overlay(alignment: .top) {
                Image(systemName: task?.iconName ?? "checkmark.circle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
            }
            .offset(x: x, y: min(y, height - barHeight))
            .help("\(store.displayTitle(for: segment)) \(shortRange(segment))")
    }

    private func timelineLegendRow(_ segment: TimeSegment) -> some View {
        let task = store.task(for: segment.taskID)
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: task?.colorHex) ?? .blue)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: task?.iconName ?? "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.displayTitle(for: segment))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(displayPathText(for: segment))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shortRange(segment))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(DurationFormatter.compact(Int((segment.endedAt ?? now).timeIntervalSince(segment.startedAt))))
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
    }

    private func hourTicks() -> [Date] {
        let calendar = Calendar.current
        let totalHours = max(1, displayInterval.duration / 3600)
        let step: Int
        if totalHours <= 4 {
            step = 1
        } else if totalHours <= 10 {
            step = 2
        } else {
            step = 4
        }
        let firstHour = calendar.dateInterval(of: .hour, for: displayInterval.start)?.start ?? displayInterval.start
        var tick = firstHour
        var result: [Date] = []
        while tick <= displayInterval.end {
            if tick >= displayInterval.start {
                result.append(tick)
            }
            guard let next = calendar.date(byAdding: .hour, value: step, to: tick) else { break }
            tick = next
        }
        if result.isEmpty || result.last! < displayInterval.end {
            result.append(displayInterval.end)
        }
        return result
    }

    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func shortRange(_ segment: TimeSegment) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: segment.startedAt))-\(segment.endedAt.map { formatter.string(from: $0) } ?? AppStrings.localized("common.now"))"
    }

    private func displayPathText(for segment: TimeSegment) -> String {
        let path = store.displayPath(for: segment).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? AppStrings.rootTask : path
    }
}

private struct TimelineLaneEntry: Identifiable {
    let segment: TimeSegment
    let lane: Int
    let labelIndex: Int
    let interval: DateInterval

    var id: UUID { segment.id }
}

struct TaskDonutCard: View {
    let tasks: [TaskAnalyticsPoint]
    let totalSeconds: Int

    private var visibleTasks: [TaskAnalyticsPoint] {
        Array(tasks.prefix(8))
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.taskUsage.title"), subtitle: AppStrings.localized("analytics.taskUsage.subtitle")) {
            if tasks.isEmpty {
                EmptyStateRow(title: AppStrings.localized("analytics.empty.rangeTaskTime"), icon: "chart.pie")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 22) {
                        donut
                        taskList
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        donut
                        taskList
                    }
                }
            }
        }
    }

    private var donut: some View {
        Chart(visibleTasks) { task in
            SectorMark(
                angle: .value("Seconds", task.grossSeconds),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
        }
        .chartLegend(.hidden)
        .frame(width: 210, height: 210)
        .overlay {
            VStack(spacing: 2) {
                Text(DurationFormatter.compact(totalSeconds))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text(.app("analytics.total"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            ForEach(visibleTasks) { task in
                ScreenTimeTaskRow(task: task, totalSeconds: totalSeconds)
                if task.id != visibleTasks.last?.id {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TodayActivityCard: View {
    let hourly: [HourlyAnalyticsPoint]

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.hourDistribution.title"), subtitle: AppStrings.localized("analytics.hourDistribution.subtitle")) {
            Chart(hourly) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Gross Minutes", point.grossSeconds / 60),
                    width: .fixed(8)
                )
                .foregroundStyle(Color.blue.opacity(0.16))

                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Wall Minutes", point.wallSeconds / 60),
                    width: .fixed(8)
                )
                .foregroundStyle(.blue)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(hour == 23 ? "24" : "\(hour)")
                        }
                    }
                }
            }
            .chartYAxisLabel(AppStrings.localized("analytics.minutes"))
            .frame(height: 220)
        }
    }
}

struct ScreenTimeBreakdownCard: View {
    let tasks: [TaskAnalyticsPoint]
    let totalSeconds: Int

    private var visibleTasks: [TaskAnalyticsPoint] {
        Array(tasks.prefix(6))
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.screenTime.title"), subtitle: AppStrings.localized("analytics.screenTime.subtitle")) {
            VStack(alignment: .leading, spacing: 14) {
                if tasks.isEmpty {
                    EmptyStateRow(title: AppStrings.localized("analytics.empty.todayTaskTime"), icon: "hourglass")
                } else {
                    screenTimeBar

                    VStack(spacing: 0) {
                        ForEach(visibleTasks) { task in
                            ScreenTimeTaskRow(task: task, totalSeconds: totalSeconds)
                            if task.id != visibleTasks.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var screenTimeBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(visibleTasks) { task in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: task.colorHex) ?? .blue)
                        .frame(width: segmentWidth(for: task, totalWidth: proxy.size.width))
                }
                if tasks.count > visibleTasks.count {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 20)
                }
            }
        }
        .frame(height: 16)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func segmentWidth(for task: TaskAnalyticsPoint, totalWidth: CGFloat) -> CGFloat {
        let ratio = CGFloat(task.grossSeconds) / CGFloat(max(totalSeconds, 1))
        return max(10, totalWidth * ratio)
    }
}

struct ScreenTimeTaskRow: View {
    let task: TaskAnalyticsPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(task.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(task.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int((Double(task.grossSeconds) / Double(max(totalSeconds, 1))) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct AnalyticsTaskRow: View {
    let task: TaskAnalyticsPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                Text(task.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(task.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int(Double(task.grossSeconds) / Double(totalSeconds) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct OverlapRow: View {
    let overlap: OverlapAnalyticsPoint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.2.swap")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(overlap.firstTitle) + \(overlap.secondTitle)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(timeRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(DurationFormatter.compact(overlap.durationSeconds))
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 10)
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: overlap.start)) - \(endFormatter.string(from: overlap.end))"
    }
}
