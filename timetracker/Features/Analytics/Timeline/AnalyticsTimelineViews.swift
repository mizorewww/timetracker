import SwiftUI

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
