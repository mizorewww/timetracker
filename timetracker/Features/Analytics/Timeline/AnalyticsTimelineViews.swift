import SwiftUI

struct OverlappingTimelineCard: View {
    let timeline: AnalyticsTimelineSnapshot

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
        AnalyticsChartCard(title: AppStrings.localized("analytics.timeline.title"), subtitle: AppStrings.localized("analytics.timeline.subtitle")) {
            if laneEntries.isEmpty {
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
                        ForEach(laneEntries) { entry in
                            timelineLegendRow(entry)
                            if entry.id != laneEntries.last?.id {
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
        timeline.laneCount
    }

    var horizontalTimelineHeight: CGFloat {
        max(120, CGFloat(laneCount) * 34 + 34)
    }
}
