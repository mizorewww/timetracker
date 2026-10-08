import SwiftUI

struct TodayTimelineEntryRow: View {
    let store: TimeTrackerStore
    let entry: AnalyticsTimelineEntry
    let segmentByID: [UUID: TimeSegment]
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "home.timeline.entry.\(entry.id.namespacedKey)"
        )
    }

    @ViewBuilder
    private var rowContent: some View {
        switch entry.id {
        case let .trackedSegment(segmentID):
            if let segment = segmentByID[segmentID] {
                TimelineRow(
                    store: store,
                    entry: entry,
                    segment: segment,
                    openTaskDetail: openTaskDetail
                )
            }
        }
    }
}
