import SwiftUI

struct QuickStartTaskGroup: View {
    let tasks: [TaskNode]
    let store: TimeTrackerStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 360 : 300),
                spacing: 12
            )
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tasks, id: \.id) { task in
                let activeSegment = store.activeSegment(for: task.id)
                HomeTimerTaskRow(
                    presentation: store.taskIdentityPresentation(for: task),
                    activeSegment: activeSegment,
                    command: store.timerPickerSelectionCommand(for: task),
                    openTask: {
                        store.openTaskDetail(task.id)
                    },
                    performTimerAction: {
                        if let activeSegment {
                            store.stop(segment: activeSegment)
                        } else {
                            store.performTimerPickerSelection(task)
                        }
                    },
                    taskAccessibilityIdentifier: "home.quickStart.task.\(task.id.uuidString)",
                    actionAccessibilityIdentifier: "home.quickStart.timer.\(task.id.uuidString)"
                )
                .appCard(padding: 12)
            }
        }
    }
}
