import SwiftUI

/// One visual grammar for ledger time on Today and in Analytics.
///
/// Exact record values and actions stay in the adjacent feature-owned rows.
/// This component owns only the shared axis, overlap lanes, bars, and omitted
/// idle-gap presentation.
struct TimelineChart: View {
    let timeline: AnalyticsTimelineSnapshot
    var compactHeight: CGFloat = 360
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if usesVerticalLayout {
                verticalTimeline
                    .frame(height: compactHeight)
            } else {
                horizontalTimeline
                    .frame(height: horizontalTimelineHeight)
            }
        }
        .accessibilityHidden(true)
    }

    var displayInterval: DateInterval {
        timeline.displayInterval
            ?? DateInterval(start: Date(timeIntervalSince1970: 0), duration: 1)
    }

    var laneEntries: [AnalyticsTimelineEntry] {
        timeline.entries
    }

    var axisCompression: TimelineAxisCompression {
        timeline.axisCompression
            ?? TimelineAxisCompression(displayInterval: displayInterval, busyIntervals: [])
    }

    var laneCount: Int {
        timeline.laneCount
    }

    private var usesVerticalLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var horizontalTimelineHeight: CGFloat {
        max(120, CGFloat(laneCount) * 34 + 34)
    }
}

extension TimelineChart {
    var horizontalTimeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                horizontalHourGrid(width: proxy.size.width, height: proxy.size.height)
                ForEach(axisCompression.omittedGaps) { gap in
                    horizontalGapMarker(gap, width: proxy.size.width, height: proxy.size.height)
                        .zIndex(1)
                }
                let lanes = TimelineChartLayout.horizontalLanes(
                    height: proxy.size.height,
                    laneCount: laneCount
                )
                ForEach(laneEntries) { entry in
                    horizontalBar(
                        entry: entry,
                        width: proxy.size.width,
                        lanes: lanes
                    )
                }
            }
        }
    }

    var verticalTimeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                verticalHourGrid(width: proxy.size.width, height: proxy.size.height)
                ForEach(axisCompression.omittedGaps) { gap in
                    verticalGapMarker(gap, width: proxy.size.width, height: proxy.size.height)
                }
                let lanes = TimelineChartLayout.verticalLanes(
                    width: proxy.size.width,
                    laneCount: laneCount
                )
                ForEach(laneEntries) { entry in
                    verticalBar(
                        entry: entry,
                        height: proxy.size.height,
                        lanes: lanes
                    )
                }
            }
        }
    }
}
