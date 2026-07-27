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
        case .appleHealthWorkout, .appleHealthSleep:
            appleHealthRow
        }
    }

    @ViewBuilder
    private var appleHealthRow: some View {
        if let taskID = store.appleHealthGeneratedTaskID(for: entry.subject) {
            Button {
                openTaskDetail(taskID)
            } label: {
                appleHealthContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppStrings.localized("tasks.openDetail"))
        } else {
            appleHealthContent
        }
    }

    private var appleHealthContent: some View {
        TodayTimelineRecordContent(
            presentation: TodayTimelineRecordPresentation(
                id: entry.id,
                visual: TaskVisualPresentation(
                    iconName: entry.iconName,
                    colorHex: entry.colorHex
                ),
                title: entry.title,
                sourceLabel: AppStrings.localized(
                    "health.timeline.source"
                ),
                sourceTint: Color(hex: entry.colorHex) ?? .red,
                startedAt: entry.startedAt,
                endedAt: entry.endedAt,
                usesCurrentEndLabel: false,
                duration: .fixed(seconds: entry.durationSeconds)
            )
        )
        .modifier(TodayTimelineRecordInsets())
    }
}
