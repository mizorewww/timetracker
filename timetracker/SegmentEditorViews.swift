import SwiftUI

struct SegmentEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
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
                store.saveSegmentDraft(draft)
                dismiss()
            },
            onDelete: { segmentID in
                store.deleteSegment(segmentID)
                dismiss()
            }
        )
        .platformSheetFrame(width: 620, height: 620)
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: SegmentEditorDraft
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
                        ForEach(store.tasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }

                    LabeledContent(AppStrings.localized("segment.source"), value: draft.source.displayName)
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(AppStrings.localized("segment.start"), selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle(AppStrings.localized("segment.active"), isOn: $draft.isActive)
                    if !draft.isActive {
                        DatePicker(AppStrings.localized("segment.end"), selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                        LabeledContent(AppStrings.localized("segment.duration")) {
                            Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                        }
                    }
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(AppStrings.localized("segment.note.placeholder"), text: $draft.note)
                }

                Section {
                    Button(role: .destructive) {
                        onDelete(draft.segmentID)
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
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.taskID == nil || (!draft.isActive && draft.endedAt <= draft.startedAt))
                }
            }
        }
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }
}
