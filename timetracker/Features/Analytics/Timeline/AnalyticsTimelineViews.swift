import SwiftUI

struct OverlappingTimelineCard: View {
    @ObservedObject var store: TimeTrackerStore
    let segments: [TimeSegment]
    let now: Date

    var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: now) ?? DateInterval(start: Calendar.current.startOfDay(for: now), duration: 86_400)
    }

    var displayInterval: DateInterval {
        layoutResult.displayInterval
    }

    var visibleSegments: [TimeSegment] {
        segments
            .filter { $0.deletedAt == nil && ($0.endedAt ?? now) > dayInterval.start && $0.startedAt < dayInterval.end }
            .sorted { $0.startedAt < $1.startedAt }
    }

    var laneEntries: [TimelineLaneEntry] {
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

    var layoutItems: [TimelineLayoutItem] {
        visibleSegments.map { segment in
            TimelineLayoutItem(
                id: segment.id,
                startedAt: segment.startedAt,
                endedAt: segment.endedAt ?? now
            )
        }
    }

    var layoutResult: TimelineLayoutResult {
        TimelineLayoutEngine.layout(
            items: layoutItems,
            dayInterval: dayInterval,
            minimumLaneGap: minimumLaneGap
        )
    }

    var axisCompression: TimelineAxisCompression {
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

    var isCompact: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var laneCount: Int {
        (laneEntries.map(\.lane).max() ?? 0) + 1
    }

    var minimumLaneGap: TimeInterval {
        60
    }

    var horizontalTimelineHeight: CGFloat {
        max(120, CGFloat(laneCount) * 34 + 34)
    }
}
