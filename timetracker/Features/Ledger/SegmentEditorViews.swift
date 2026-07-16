import SwiftUI

struct SegmentEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: SegmentEditorDraft

    var body: some View {
        SegmentEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                dismiss()
            },
            onSave: { draft in
                if store.saveSegmentDraft(draft) {
                    dismiss()
                }
            },
            onDelete: { draft in
                if store.deleteSegment(draft.segmentID, fallbackTaskID: draft.taskID) {
                    dismiss()
                }
            }
        )
        .platformSheetFrame(width: 620, height: 620)
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorPanel: View {
    let store: TimeTrackerStore
    @State private var draft: SegmentEditorDraft
    @State private var isDiscardConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    let initialDraft: SegmentEditorDraft
    let onCancel: () -> Void
    let onSave: (SegmentEditorDraft) -> Void
    let onDelete: (SegmentEditorDraft) -> Void

    init(
        store: TimeTrackerStore,
        initialDraft: SegmentEditorDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SegmentEditorDraft) -> Void,
        onDelete: @escaping (SegmentEditorDraft) -> Void
    ) {
        self.store = store
        self.initialDraft = initialDraft
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
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

                    LabeledContent(AppStrings.localized("segment.source"), value: draft.source.displayName)
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(
                        AppStrings.localized("segment.start"),
                        selection: $draft.startedAt,
                        in: ...now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    if draft.wasActive {
                        Toggle(AppStrings.localized("segment.active"), isOn: $draft.isActive)
                    } else {
                        LabeledContent(
                            AppStrings.localized("segment.status"),
                            value: AppStrings.localized("segment.finished")
                        )
                    }
                    if !draft.isActive {
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
                    }
                    validationMessage(for: validation)
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(
                        AppStrings.localized("segment.note.placeholder"),
                        text: $draft.note,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                    .accessibilityIdentifier("segmentEditor.note")
                    if let noteError {
                        noteValidationLabel(noteError)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Label(AppStrings.localized("segment.softDelete"), systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppStrings.localized("segment.edit.title"))
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
        .confirmationDialog(
            AppStrings.localized("segment.delete.confirm.title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppStrings.localized("segment.softDelete"), role: .destructive) {
                onDelete(draft)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("segment.delete.confirm.message"))
        }
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
            endedAt: draft.isActive ? nil : draft.endedAt,
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
            timeValidationLabel(
                key: draft.isActive ? "segment.error.startNotFuture" : "segment.error.timeNotFuture"
            )
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
        store.tasks.filter { task in
            store.isTaskAvailableForTracking(task) || task.id == initialDraft.taskID
        }
    }
}
