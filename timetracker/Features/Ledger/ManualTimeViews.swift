import SwiftUI

struct ManualTimeSheet: View {
    @ObservedObject var store: TimeTrackerStore
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
                store.saveManualTimeDraft(draft)
                dismiss()
            }
        )
        .platformSheetFrame(width: 620, height: 560)
        .presentationDetents([.medium, .large])
    }
}

struct ManualTimePanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: ManualTimeDraft
    let onCancel: () -> Void
    let onSave: (ManualTimeDraft) -> Void

    init(store: TimeTrackerStore, initialDraft: ManualTimeDraft, onCancel: @escaping () -> Void, onSave: @escaping (ManualTimeDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
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
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(AppStrings.localized("segment.start"), selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(AppStrings.localized("segment.end"), selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                    LabeledContent(AppStrings.localized("segment.duration")) {
                        Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                    }
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(AppStrings.localized("manual.note.placeholder"), text: $draft.note)
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
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.taskID == nil || draft.endedAt <= draft.startedAt)
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
