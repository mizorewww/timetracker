import Charts
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var range: AnalyticsRange = .today

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let snapshot = store.analyticsSnapshot(for: range, now: context.date)
            let overview = snapshot.overview
            let daily = snapshot.daily
            let tasks = snapshot.taskBreakdown
            let overlaps = snapshot.overlaps
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
                        AnalyticsMetric(title: AppStrings.wallTime, value: DurationFormatter.compact(overview.wallSeconds), footnote: AppStrings.localized("analytics.wall.footnote"))
                        AnalyticsMetric(title: AppStrings.grossTime, value: DurationFormatter.compact(overview.grossSeconds), footnote: AppStrings.localized("analytics.gross.footnote"))
                        AnalyticsMetric(title: AppStrings.localized("analytics.metric.overlap"), value: DurationFormatter.compact(overview.overlapSeconds), footnote: AppStrings.localized("analytics.overlap.footnote"))
                        AnalyticsMetric(title: AppStrings.localized("analytics.metric.pomodoros"), value: "\(overview.pomodoroCount)", footnote: AppStrings.localized("analytics.pomodoros.footnote"))
                    }

                    TaskForecastsCard(store: store)

                    if range == .today {
                        TodayActivityCard(store: store, segments: todaySegments, now: context.date)
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
        Picker(AppStrings.localized("analytics.range"), selection: $range) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.displayName).tag(range)
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
        .appCard()
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
        .appCard()
    }
}

struct TaskForecastsCard: View {
    @ObservedObject var store: TimeTrackerStore

    private var forecastItems: [AnalyticsForecastItem] {
        store.tasks.compactMap { task -> AnalyticsForecastItem? in
            guard task.deletedAt == nil,
                  task.status != .archived,
                  task.status != .completed,
                  let rollup = store.rollup(for: task.id),
                  rollup.isDisplayableForecast else {
                return nil
            }
            return AnalyticsForecastItem(task: task, rollup: rollup)
        }
        .sorted {
            ($0.rollup.remainingSeconds ?? 0) > ($1.rollup.remainingSeconds ?? 0)
        }
        .prefix(6)
        .map { $0 }
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.forecasts.title"), subtitle: AppStrings.localized("analytics.forecasts.subtitle")) {
            if forecastItems.isEmpty {
                EmptyStateRow(title: AppStrings.localized("analytics.forecasts.empty"), icon: "checklist")
            } else {
                VStack(spacing: 12) {
                    ForecastExplanationCallout()

                    VStack(spacing: 0) {
                        ForEach(forecastItems) { item in
                            ForecastAnalyticsRow(store: store, item: item)
                            if item.id != forecastItems.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ForecastAnalyticsRow: View {
    @ObservedObject var store: TimeTrackerStore
    let item: AnalyticsForecastItem

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: item.task, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.rollup.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let paceText = item.rollup.historicalPaceDisplayText {
                    Text(paceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProgressView(value: item.rollup.completionFraction)
                    .tint(Color(hex: item.task.colorHex) ?? .blue)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(item.rollup.remainingDisplayText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(daysText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(item.task.id)
        }
        .padding(.vertical, 10)
    }

    private var daysText: String {
        item.rollup.projectedDays == nil ? item.rollup.confidence.displayName : item.rollup.projectedDaysDisplayText
    }
}

private struct AnalyticsForecastItem: Identifiable {
    let task: TaskNode
    let rollup: TaskRollup

    var id: UUID { task.id }
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

    private var axisCompression: TimelineAxisCompression {
        TimelineAxisCompression(
            displayInterval: displayInterval,
            busyIntervals: layoutResult.entries.map(\.item.interval)
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
                ForEach(axisCompression.omittedGaps) { gap in
                    horizontalGapMarker(gap, width: proxy.size.width, height: proxy.size.height)
                }
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
                ForEach(axisCompression.omittedGaps) { gap in
                    verticalGapMarker(gap, width: proxy.size.width, height: proxy.size.height)
                }
                ForEach(laneEntries) { entry in
                    verticalBar(entry: entry, width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
    }

    private func horizontalHourGrid(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourTicks().filter { !axisCompression.isInsideOmittedGap($0) }, id: \.self) { tick in
                let ratio = axisCompression.ratio(for: tick)
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
            ForEach(hourTicks().filter { !axisCompression.isInsideOmittedGap($0) }, id: \.self) { tick in
                let ratio = axisCompression.ratio(for: tick)
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
        let startRatio = axisCompression.ratio(for: interval.start)
        let endRatio = axisCompression.ratio(for: interval.end)
        let durationRatio = max(0, endRatio - startRatio)
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
        let startRatio = axisCompression.ratio(for: interval.start)
        let endRatio = axisCompression.ratio(for: interval.end)
        let durationRatio = max(0, endRatio - startRatio)
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

    private func horizontalGapMarker(_ gap: TimelineOmittedGap, width: CGFloat, height: CGFloat) -> some View {
        let x = width * CGFloat(axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset))
        return DashedTimelineLine(isVertical: true)
            .stroke(Color.secondary.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: 1, height: max(28, height - 28))
            .overlay(alignment: .center) {
                Text(omittedGapText(gap))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
            }
            .offset(x: min(max(0, x), width - 1), y: 4)
    }

    private func verticalGapMarker(_ gap: TimelineOmittedGap, width: CGFloat, height: CGFloat) -> some View {
        let y = height * CGFloat(axisCompression.ratio(forCompressedOffset: gap.compressedMidpointOffset))
        return DashedTimelineLine(isVertical: false)
            .stroke(Color.secondary.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: max(40, width - 68), height: 1)
            .overlay(alignment: .center) {
                Text(omittedGapText(gap))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .fixedSize()
            }
            .offset(x: 68, y: min(max(0, y), height - 1))
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

    private func omittedGapText(_ gap: TimelineOmittedGap) -> String {
        String(format: AppStrings.localized("analytics.timeline.gap.omitted"), DurationFormatter.compact(Int(gap.duration)))
    }
}

private struct DashedTimelineLine: Shape {
    let isVertical: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isVertical {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
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
