import SwiftUI

struct ManualTimeSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: ManualTimeDraft

    var body: some View {
        ManualTimePanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.manualTimeDraft = nil
                dismiss()
            },
            onSave: { draft in
                if store.saveManualTimeDraft(draft) {
                    dismiss()
                }
            }
        )
        .platformSheetFrame(width: 620, height: 560)
        .presentationDetents([.medium, .large])
    }
}

struct ManualTimePanel: View {
    let store: TimeTrackerStore
    @State private var draft: ManualTimeDraft
    @State private var isDiscardConfirmationPresented = false
    let initialDraft: ManualTimeDraft
    let onCancel: () -> Void
    let onSave: (ManualTimeDraft) -> Void

    init(store: TimeTrackerStore, initialDraft: ManualTimeDraft, onCancel: @escaping () -> Void, onSave: @escaping (ManualTimeDraft) -> Void) {
        self.store = store
        self.initialDraft = initialDraft
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        let now = Date()
        let validation = trackedTimeValidation(at: now)
        let noteError = noteValidationMessage

        NavigationStack {
            Form {
                Section(AppStrings.localized("segment.assignment")) {
                    Picker(AppStrings.localized("segment.task"), selection: taskBinding) {
                        Text(.app("segment.choose")).tag(Optional<UUID>.none)
                        ForEach(availableTasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(
                        AppStrings.localized("segment.start"),
                        selection: $draft.startedAt,
                        in: ...now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    DatePicker(
                        AppStrings.localized("segment.end"),
                        selection: $draft.endedAt,
                        in: ...now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    LabeledContent(AppStrings.localized("segment.duration")) {
                        Text(DurationFormatter.compact(TrackedTimePolicy.elapsedSeconds(
                            startedAt: draft.startedAt,
                            endedAt: draft.endedAt,
                            now: now
                        )))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(validation == .valid ? Color.primary : Color.red)
                    }
                    validationMessage(for: validation)
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(
                        AppStrings.localized("manual.note.placeholder"),
                        text: $draft.note,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .accessibilityIdentifier("manualTime.note")
                    if let noteError {
                        noteValidationLabel(noteError)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppStrings.localized("manual.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        requestCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.taskID == nil || validation != .valid || noteError != nil)
                }
            }
        }
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: draft != initialDraft,
            discard: onCancel
        )
    }

    private func requestCancel() {
        if draft == initialDraft {
            onCancel()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private func trackedTimeValidation(at now: Date) -> TrackedTimePolicy.WriteValidation {
        TrackedTimePolicy.validateWrite(
            startedAt: draft.startedAt,
            endedAt: draft.endedAt,
            now: now
        )
    }

    @ViewBuilder
    private func validationMessage(for validation: TrackedTimePolicy.WriteValidation) -> some View {
        switch validation {
        case .valid:
            EmptyView()
        case .invalidRange:
            timeValidationLabel(key: "segment.error.endAfterStart")
        case .futureTime:
            timeValidationLabel(key: "segment.error.timeNotFuture")
        }
    }

    private func timeValidationLabel(key: String) -> some View {
        Label(AppStrings.localized(key), systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityAddTraits(.isStaticText)
    }

    private var noteValidationMessage: String? {
        do {
            _ = try LedgerPersistencePolicy.prepareNote(draft.note)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func noteValidationLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityAddTraits(.isStaticText)
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }

    private var availableTasks: [TaskNode] {
        store.tasks.filter(store.isTaskAvailableForTracking)
    }
}
