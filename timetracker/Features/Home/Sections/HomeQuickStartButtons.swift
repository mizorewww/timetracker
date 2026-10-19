import SwiftUI

struct QuickStartTaskGroup: View {
    let tasks: [TaskNode]
    let store: TimeTrackerStore
    let openTask: (UUID) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 360 : 300),
                spacing: 12
            ),
        ]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tasks, id: \.id) { task in
                HomeQuickStartTaskRow(
                    store: store,
                    task: task,
                    actionLabelStyle: .titleAndIcon,
                    openTask: openTask
                )
                .appCard(padding: 12)
            }
        }
    }
}
