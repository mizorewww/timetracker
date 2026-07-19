import Foundation
import SwiftUI

enum TodayTimelineEntryRowStyle: Equatable {
    case list
    case card
}

struct TodayTimelineEntryRow: View {
    let store: TimeTrackerStore
    let entry: AnalyticsTimelineEntry
    let segmentByID: [UUID: TimeSegment]
    let style: TodayTimelineEntryRowStyle
    let showsDivider: Bool
    let openTaskDetail: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            rowContent

            if showsDivider {
                Divider()
                    .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        switch entry.id {
        case let .trackedSegment(segmentID):
            if let segment = segmentByID[segmentID] {
                TimelineRow(
                    store: store,
                    segment: segment,
                    openTaskDetail: openTaskDetail
                )
            }
        case .appleHealthWorkout, .appleHealthSleep:
            if style == .card {
                TimelineLegendRow(entry: entry)
                    .padding(.horizontal, 18)
            } else {
                TimelineLegendRow(entry: entry)
            }
        }
    }
}
