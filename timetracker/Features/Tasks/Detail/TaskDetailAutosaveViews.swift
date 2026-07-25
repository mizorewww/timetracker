import SwiftUI

struct TaskDetailAutosaveFailureSection: View {
    let controller: TaskDetailAutosaveController

    var body: some View {
        if case let .failed(message) = controller.status {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        AppStrings.localized("task.autosave.failed"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.red)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        controller.retry()
                    } label: {
                        Label(
                            AppStrings.localized("task.autosave.retry"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .accessibilityIdentifier("task.detail.autosave.retry")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("task.detail.autosave.failure")
            }
        }
    }
}
