import SwiftUI

/// Explains why the visible edits are not persisted: a save failure (with
/// retry) or a draft that fails validation and is held until it is fixed.
struct TaskDetailAutosaveFailureSection: View {
    let controller: TaskDetailAutosaveController

    var body: some View {
        switch controller.status {
        case let .failed(message):
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
        case .validationBlocked:
            Section {
                Label(
                    AppStrings.localized("task.autosave.invalid"),
                    systemImage: "exclamationmark.circle"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task.detail.autosave.invalid")
            }
        default:
            EmptyView()
        }
    }
}
