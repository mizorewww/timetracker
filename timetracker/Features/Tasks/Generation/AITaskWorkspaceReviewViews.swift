import MarkdownView
import SwiftUI

struct AITaskWorkspaceReviewView: View {
    let draft: AITaskWorkspaceReviewDraft
    let errorMessage: String?
    let isApplying: Bool
    let onChangeRequest: () -> Void
    private let operationPresentations:
        [AITaskWorkspaceOperationPresentation]

    init(
        draft: AITaskWorkspaceReviewDraft,
        errorMessage: String?,
        isApplying: Bool,
        onChangeRequest: @escaping () -> Void
    ) {
        self.draft = draft
        self.errorMessage = errorMessage
        self.isApplying = isApplying
        self.onChangeRequest = onChangeRequest
        operationPresentations = AITaskWorkspaceReviewPresentation(
            operations: draft.plan.operations,
            original: draft.plan.originalSnapshot,
            resulting: draft.plan.resultingSnapshot
        ).operations
    }

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(.app("aiTaskPlan.preview.workspaceNotice"))
                            .font(.headline)
                        Text(draft.localizedOperationSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checklist.checked")
                        .foregroundStyle(.purple)
                }
                .accessibilityIdentifier("aiTaskPlan.changeSummary")

                Button(action: onChangeRequest) {
                    Label(
                        AppStrings.localized("aiTaskPlan.editRequest"),
                        systemImage: "arrow.backward"
                    )
                }
                .disabled(isApplying)
                .accessibilityIdentifier("aiTaskPlan.editRequest")
            } footer: {
                Text(.app("aiTaskPlan.preview.workspaceFooter"))
            }

            Section(AppStrings.localized("aiTaskPlan.changes.header")) {
                ForEach(operationPresentations) { presentation in
                    AITaskWorkspaceOperationRow(
                        presentation: presentation
                    )
                }
            }

            if let reasoning = draft.plan.reasoningContent {
                Section {
                    DisclosureGroup {
                        ScrollView {
                            MarkdownView(reasoning)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .accessibilityIdentifier(
                                    "aiTaskPlan.reasoning.content"
                                )
                        }
                        .frame(maxHeight: 320)
                        .padding(.vertical, 4)
                    } label: {
                        Label(
                            AppStrings.localized(
                                "aiTaskPlan.reasoning.title"
                            ),
                            systemImage: "brain"
                        )
                    }
                    .accessibilityIdentifier("aiTaskPlan.reasoning")
                }
            }

            if let rawOutput = draft.plan.rawResponseContent {
                Section {
                    DisclosureGroup {
                        ScrollView {
                            Text(rawOutput)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .accessibilityIdentifier(
                                    "aiTaskPlan.rawOutput.content"
                                )
                        }
                        .frame(maxHeight: 320)
                        .padding(.vertical, 4)
                    } label: {
                        Label(
                            AppStrings.localized(
                                "aiTaskPlan.rawOutput.title"
                            ),
                            systemImage: "curlybraces"
                        )
                    }
                    .accessibilityIdentifier("aiTaskPlan.rawOutput")
                }
            }

            if draft.mutationCount == 0 {
                Section {
                    ContentUnavailableView(
                        AppStrings.localized(
                            "aiTaskPlan.noChanges.title"
                        ),
                        systemImage: "checkmark.circle",
                        description: Text(.app(
                            "aiTaskPlan.noChanges.message"
                        ))
                    )
                    .accessibilityIdentifier("aiTaskPlan.noChanges")
                }
            }

            if let errorMessage {
                Section {
                    Label(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("aiTaskPlan.error")
                } footer: {
                    Text(.app("aiTaskPlan.error.previewPreserved"))
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .accessibilityIdentifier("aiTaskPlan.preview")
    }
}

private struct AITaskWorkspaceOperationRow: View {
    let presentation: AITaskWorkspaceOperationPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.operation.previewSymbolName)
                .foregroundStyle(presentation.operation.previewTint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.operation.localizedKind)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.operation.previewTint)
                Text(presentation.title)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if presentation.context.isEmpty == false {
                    Text(presentation.context)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if presentation.fieldChanges.isEmpty == false {
                    AITaskWorkspaceFieldChangesView(
                        changes: presentation.fieldChanges
                    )
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier(
            "aiTaskPlan.operation.\(presentation.accessibilityIndex)"
        )
    }
}

private struct AITaskWorkspaceFieldChangesView: View {
    let changes: [AITaskWorkspaceFieldChange]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 3) {
                    Text(change.field.localizedTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    AITaskWorkspaceDiffValueView(
                        label: AppStrings.localized(
                            "aiTaskPlan.diff.before"
                        ),
                        value: change.before
                    )
                    AITaskWorkspaceDiffValueView(
                        label: AppStrings.localized(
                            "aiTaskPlan.diff.after"
                        ),
                        value: change.after
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AITaskWorkspaceDiffValueView: View {
    let label: String
    let value: AITaskWorkspacePreviewValue

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            valueContent
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valueContent: some View {
        switch value {
        case let .icon(iconName):
            Label(value.localizedText, systemImage: iconName)
        case let .color(colorHex):
            Label {
                Text(value.localizedText)
            } icon: {
                Circle()
                    .fill(Color(hex: colorHex) ?? .secondary)
                    .frame(width: 10, height: 10)
            }
        case .text,
             .optionalText,
             .minutes,
             .date,
             .boolean,
             .quantityGoal,
             .recurrence:
            Text(value.localizedText)
        }
    }
}

private extension AITaskWorkspaceOperation {
    var previewSymbolName: String {
        switch self {
        case .useExistingCategory:
            "arrow.triangle.merge"
        case .createCategory, .createTask, .createChecklistItem:
            "plus.circle.fill"
        case .updateCategory, .updateTask, .updateChecklistItem:
            "pencil.circle.fill"
        case .archiveTask:
            "archivebox.fill"
        case .deleteCategory, .deleteChecklistItem:
            "trash.circle.fill"
        }
    }

    var previewTint: Color {
        switch self {
        case .archiveTask, .deleteCategory, .deleteChecklistItem:
            .red
        case .useExistingCategory:
            .teal
        case .createCategory, .createTask, .createChecklistItem:
            .green
        case .updateCategory, .updateTask, .updateChecklistItem:
            .blue
        }
    }
}
