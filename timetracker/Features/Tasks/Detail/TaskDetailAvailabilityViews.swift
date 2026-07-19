import SwiftUI

struct TaskDetailTrackingAvailabilitySection: View {
    let store: TimeTrackerStore
    let task: TaskNode

    @ViewBuilder
    var body: some View {
        if !store.isTaskVisible(task) {
            Section {
                Label(AppStrings.localized("status.archived"), systemImage: "archivebox")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task.detail.trackingUnavailable")
            } footer: {
                Text(.app("task.archived.trackingUnavailable"))
            }
        }
    }
}
