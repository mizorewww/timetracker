import SwiftUI

struct TaskDraftRecoveryCleanupSection: View {
    let isRetrying: Bool
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        Section {
            Label(
                AppStrings.localized("tasks.recovery.saved.title"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(.green)

            Text(.app("tasks.recovery.saved.cleanupMessage"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: retry) {
                if isRetrying {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Label(
                        AppStrings.localized("tasks.recovery.finishCleanup"),
                        systemImage: "arrow.clockwise"
                    )
                }
            }
            .disabled(isRetrying)
            .accessibilityIdentifier("task.editor.recovery.finishCleanup")

            Button(action: close) {
                Label(
                    AppStrings.localized("tasks.recovery.cleanupLater"),
                    systemImage: "clock"
                )
            }
            .disabled(isRetrying)
            .accessibilityIdentifier("task.editor.recovery.cleanupLater")
        }
        .accessibilityIdentifier("task.editor.recovery.cleanup")
    }
}
