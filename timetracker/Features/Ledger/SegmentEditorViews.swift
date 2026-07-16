import SwiftUI

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
        let validation = trackedTimeValidation(for: draft, at: now)
        let noteError = noteValidationMessage(for: draft)

        NavigationStack {
            Form {
                Section(AppStrings.localized("segment.assignment")) {
                    Picker(AppStrings.localized("segment.task"), selection: $draft.taskID) {
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
                    LabeledContent(
                        AppStrings.localized("segment.status"),
                        value: AppStrings.localized(
                            draft.isActive ? "segment.active" : "segment.finished"
                        )
                    )
                    if draft.wasActive && draft.isActive {
                        Button {
                            draft.endedAt = Date()
                            draft.isActive = false
                        } label: {
                            Label(
                                AppStrings.localized(endActionKey),
                                systemImage: "stop.circle"
                            )
                        }
                        .accessibilityIdentifier("segmentEditor.endNow")
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
                        if draft.wasActive {
                            Button(AppStrings.localized(keepRunningActionKey)) {
                                draft.isActive = true
                            }
                            .accessibilityIdentifier("segmentEditor.keepRunning")
                        }
                    }
                    validationMessage(
                        for: validation,
                        isActive: draft.isActive
                    )
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
                        Label(AppStrings.localized("timeline.deleteSegment"), systemImage: "trash")
                    }
                    .accessibilityIdentifier("segmentEditor.delete")
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("segmentEditor.view")
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
            deletionImpact.confirmationTitle,
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(deletionImpact.confirmationActionTitle, role: .destructive) {
                onDelete(draft)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(deletionImpact.confirmationMessage)
        }
    }

    private func requestCancel() {
        if draft == initialDraft {
            onCancel()
        } else {
            isDiscardConfirmationPresented = true
        }
    }
}
