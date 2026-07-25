import SwiftUI

struct TaskDetailTrackingAvailabilitySection: View {
    let store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        if !store.isTaskVisible(task) {
            availabilitySection(
                titleKey: "status.archived",
                messageKey: "task.archived.trackingUnavailable",
                systemImage: "archivebox"
            )
        } else if store.isTaskRecurrenceTemplate(task) {
            availabilitySection(
                titleKey: "task.recurrence.template.title",
                messageKey:
                "task.recurrence.template.trackingUnavailable",
                systemImage: "calendar.badge.clock"
            )
        } else if !store.isTaskAvailableForTracking(task) {
            availabilitySection(
                titleKey: "task.healthSyncOnly.title",
                messageKey: "task.healthSyncOnly.trackingUnavailable",
                systemImage: "heart.text.clipboard"
            )
        }
    }

    private func availabilitySection(
        titleKey: String,
        messageKey: String,
        systemImage: String
    ) -> some View {
        Section {
            Label(
                AppStrings.localized(titleKey),
                systemImage: systemImage
            )
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(
                "task.detail.trackingUnavailable"
            )
        } footer: {
            Text(.app(messageKey))
        }
    }
}
