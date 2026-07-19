import SwiftUI

struct TaskManagementRowPresentation {
    let identity: TaskIdentityPresentation
    let identityContext: TaskIdentityPresentation.Context
    let progress: ChecklistProgress
    let rollup: TaskRollup?
    let workedSeconds: Int
    let childCount: Int
    let isRunning: Bool
}

struct TaskManagementRowContent: View {
    let presentation: TaskManagementRowPresentation
    let showsNavigationChevron: Bool

    var body: some View {
        TaskSummaryRow(
            presentation: presentation.identity,
            context: presentation.identityContext,
            iconSize: 30,
            metadata: TaskSummaryRowMetadata(
                checklistProgress: presentation.progress.totalCount > 0
                    ? presentation.progress
                    : nil,
                workedSeconds: presentation.workedSeconds,
                isRunning: presentation.isRunning,
                showsNavigationChevron: showsNavigationChevron
            )
        )
        .padding(.vertical, 6)
    }
}
