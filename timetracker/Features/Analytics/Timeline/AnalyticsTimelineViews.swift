import SwiftUI

struct OverlappingTimelineContent: View {
    let timeline: AnalyticsTimelineSnapshot
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var displayInterval: DateInterval {
        timeline.displayInterval ?? DateInterval(start: Date(timeIntervalSince1970: 0), duration: 1)
    }

    var laneEntries: [AnalyticsTimelineEntry] {
        timeline.entries
    }

    var axisCompression: TimelineAxisCompression {
        timeline.axisCompression ?? TimelineAxisCompression(displayInterval: displayInterval, busyIntervals: [])
    }

    var body: some View {
        if laneEntries.isEmpty {
            EmptyStateRow(title: AppStrings.localized("analytics.timeline.empty"), icon: "timeline.selection")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if isCompact {
                    verticalTimeline
                        .frame(height: 520)
                        .accessibilityHidden(true)
                } else {
                    horizontalTimeline
                        .frame(height: horizontalTimelineHeight)
                        .accessibilityHidden(true)
                }

                Divider()

                VStack(spacing: 0) {
                    let lastEntryID = laneEntries.last?.id
                    ForEach(laneEntries) { entry in
                        timelineLegendRow(entry)
                        if entry.id != lastEntryID {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var laneCount: Int {
        timeline.laneCount
    }

    var horizontalTimelineHeight: CGFloat {
        max(120, CGFloat(laneCount) * 34 + 34)
    }
}
