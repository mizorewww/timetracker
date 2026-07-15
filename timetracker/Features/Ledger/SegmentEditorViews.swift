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
                store.segmentEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                if store.saveSegmentDraft(draft) {
                    dismiss()
                }
            },
            onDelete: { segmentID in
                if store.deleteSegment(segmentID) {
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
    let onDelete: (UUID) -> Void

    init(
        store: TimeTrackerStore,
        initialDraft: SegmentEditorDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SegmentEditorDraft) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.initialDraft = initialDraft
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
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
                    if draft.isActive {
                        DatePicker(
                            AppStrings.localized("segment.start"),
                            selection: $draft.startedAt,
                            in: ...Date(),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } else {
                        DatePicker(
                            AppStrings.localized("segment.start"),
                            selection: $draft.startedAt,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                    Toggle(AppStrings.localized("segment.active"), isOn: $draft.isActive)
                    if !draft.isActive {
                        DatePicker(AppStrings.localized("segment.end"), selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                        LabeledContent(AppStrings.localized("segment.duration")) {
                            Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                        }
                        if draft.endedAt <= draft.startedAt {
                            Label(AppStrings.localized("segment.error.endAfterStart"), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else if draft.startedAt > Date() {
                        Label(AppStrings.localized("segment.error.startNotFuture"), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(AppStrings.localized("segment.note.placeholder"), text: $draft.note)
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
                    .disabled(
                        draft.taskID == nil ||
                            (draft.isActive ? draft.startedAt > Date() : draft.endedAt <= draft.startedAt)
                    )
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
                onDelete(draft.segmentID)
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
