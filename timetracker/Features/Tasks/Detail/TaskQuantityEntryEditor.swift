import Foundation
import SwiftUI

nonisolated struct TaskQuantityEntryEditorDraft: Equatable, Sendable {
    var amount: Int
    var recordedAt: Date

    var isValid: Bool {
        TaskQuantityPolicy.valueRange.contains(amount) &&
            PersistentDatePolicy.contains(recordedAt)
    }

    var validationMessage: String {
        if TaskQuantityPolicy.valueRange.contains(amount) == false {
            return TaskQuantityEntryMutationError.invalidAmount
                .localizedDescription
        }
        return TaskQuantityEntryMutationError.invalidRecordedAt
            .localizedDescription
    }
}

nonisolated struct TaskQuantityEntryEditorRoute:
    Identifiable,
    Equatable,
    Sendable
{
    nonisolated enum Mode: Equatable, Sendable {
        case add(entryID: UUID)
        case edit(
            entryBaseline: TaskQuantityEntryMutationBaseline,
            updateOperationID: UUID,
            deleteOperationID: UUID
        )
    }

    let id: UUID
    let taskID: UUID
    let goalBaseline: TaskQuantityGoalMutationBaseline
    let unitLabel: String
    let initialDraft: TaskQuantityEntryEditorDraft
    let mode: Mode

    static func add(
        detail: TaskQuantityDetailSnapshot,
        now: Date = Date(),
        routeID: UUID = UUID(),
        entryID: UUID = UUID()
    ) -> TaskQuantityEntryEditorRoute {
        let remaining = detail.progress.remainingAmount
        let amount = remaining > 0 ? Int(remaining) : 1
        return TaskQuantityEntryEditorRoute(
            id: routeID,
            taskID: detail.progress.taskID,
            goalBaseline: detail.progress.goalBaseline,
            unitLabel: detail.progress.unitLabel,
            initialDraft: TaskQuantityEntryEditorDraft(
                amount: amount,
                recordedAt: now
            ),
            mode: .add(entryID: entryID)
        )
    }

    static func edit(
        detail: TaskQuantityDetailSnapshot,
        entry: TaskQuantityEntrySnapshot,
        routeID: UUID = UUID(),
        updateOperationID: UUID = UUID(),
        deleteOperationID: UUID = UUID()
    ) -> TaskQuantityEntryEditorRoute {
        TaskQuantityEntryEditorRoute(
            id: routeID,
            taskID: detail.progress.taskID,
            goalBaseline: detail.progress.goalBaseline,
            unitLabel: detail.progress.unitLabel,
            initialDraft: TaskQuantityEntryEditorDraft(
                amount: entry.amount,
                recordedAt: entry.recordedAt
            ),
            mode: .edit(
                entryBaseline: entry.baseline,
                updateOperationID: updateOperationID,
                deleteOperationID: deleteOperationID
            )
        )
    }

    var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }
}

struct TaskQuantityEntryEditorSheet: View {
    let store: TimeTrackerStore
    let route: TaskQuantityEntryEditorRoute
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskQuantityEntryEditorDraft
    @State private var isDiscardConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @FocusState private var isAmountFocused: Bool

    init(store: TimeTrackerStore, route: TaskQuantityEntryEditorRoute) {
        self.store = store
        self.route = route
        _draft = State(initialValue: route.initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        TextField(
                            AppStrings.localized(
                                "task.quantity.entry.editor.amount"
                            ),
                            value: $draft.amount,
                            format: .number.grouping(.never)
                        )
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .focused($isAmountFocused)
                        .accessibilityIdentifier(
                            "task.detail.quantity.amount"
                        )
                    } label: {
                        Text(.app("task.quantity.entry.editor.amount"))
                    }
                    LabeledContent(
                        AppStrings.localized(
                            "task.quantity.entry.editor.unit"
                        ),
                        value: route.unitLabel
                    )
                    DatePicker(
                        AppStrings.localized(
                            "task.quantity.entry.editor.date"
                        ),
                        selection: $draft.recordedAt,
                        in: Self.allowedDateRange,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .accessibilityIdentifier("task.detail.quantity.date")

                    if draft.isValid == false {
                        TaskEditorInlineErrorMessage(
                            message: draft.validationMessage,
                            accessibilityIdentifier:
                            "task.detail.quantity.validation"
                        )
                    }
                } header: {
                    Text(.app("task.quantity.entry.editor.section"))
                }

                if route.isEditing {
                    Section {
                        Button(role: .destructive) {
                            isDeleteConfirmationPresented = true
                        } label: {
                            Label(
                                AppStrings.localized(
                                    "task.quantity.entry.editor.delete"
                                ),
                                systemImage: "trash"
                            )
                        }
                        .accessibilityIdentifier(
                            "task.detail.quantity.delete"
                        )
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(
                AppStrings.localized(
                    route.isEditing
                        ? "task.quantity.entry.editor.editTitle"
                        : "task.quantity.entry.editor.addTitle"
                )
            )
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel, action: requestCancel)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier(
                            "task.detail.quantity.cancel"
                        )
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save"), action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(draft.isValid == false)
                        .accessibilityIdentifier(
                            "task.detail.quantity.save"
                        )
                }
                #if os(iOS)
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppStrings.done) { isAmountFocused = false }
                        .accessibilityIdentifier("task.detail.quantity.keyboard.done")
                }
                #endif
            }
        }
        .platformSheetFrame(width: 480, height: 500)
        .presentationDetents([.large])
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: draft != route.initialDraft,
            discard: dismiss.callAsFunction
        )
        .confirmationDialog(
            AppStrings.localized("task.quantity.entry.editor.deleteTitle"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                AppStrings.localized(
                    "task.quantity.entry.editor.deleteConfirm"
                ),
                role: .destructive,
                action: delete
            )
            .accessibilityIdentifier(
                "task.detail.quantity.delete.confirm"
            )
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("task.quantity.entry.editor.deleteMessage"))
        }
    }

    private static var allowedDateRange: ClosedRange<Date> {
        let maximumDate = PersistentDatePolicy.maximumDateExclusive.addingTimeInterval(-1)
        return PersistentDatePolicy.minimumDate ... maximumDate
    }

    private func requestCancel() {
        isAmountFocused = false
        if draft == route.initialDraft {
            dismiss()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private func save() {
        isAmountFocused = false
        let didCommit: Bool = switch route.mode {
        case let .add(entryID):
            store.recordTaskQuantity(
                taskID: route.taskID,
                goalBaseline: route.goalBaseline,
                amount: draft.amount,
                entryID: entryID,
                recordedAt: draft.recordedAt
            )
        case let .edit(entryBaseline, operationID, _):
            store.updateTaskQuantityEntry(
                baseline: entryBaseline,
                goalBaseline: route.goalBaseline,
                amount: draft.amount,
                recordedAt: draft.recordedAt,
                operationID: operationID
            )
        }
        if didCommit {
            dismiss()
        }
    }

    private func delete() {
        guard case let .edit(entryBaseline, _, operationID) = route.mode
        else {
            return
        }
        if store.deleteTaskQuantityEntry(
            baseline: entryBaseline,
            operationID: operationID
        ) {
            dismiss()
        }
    }
}
