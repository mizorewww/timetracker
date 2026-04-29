import SwiftUI

struct TaskEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskEditorDraft

    var body: some View {
        TaskEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.taskEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                if store.saveTaskDraft(draft) {
                    dismiss()
                }
            }
        )
        .platformSheetFrame(width: 520, height: 620)
        .presentationDetents([.large])
    }
}

struct TaskEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: TaskEditorDraft
    @State private var isSymbolPickerPresented = false
    @FocusState private var focusedChecklistDraftID: UUID?
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> Void

    private let colors = ["1677FF", "16A34A", "7C3AED", "F97316", "EF4444", "0EA5E9", "64748B"]

    init(store: TimeTrackerStore, initialDraft: TaskEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (TaskEditorDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section(AppStrings.localized("editor.task.info")) {
                        TextField(AppStrings.localized("editor.task.name"), text: $draft.title)

                        TaskStatusPicker(selection: $draft.status)

                        Picker(AppStrings.localized("editor.task.parent"), selection: parentBinding) {
                            Text(.app("editor.task.rootLevel")).tag(Optional<UUID>.none)
                            ForEach(store.validParentTasks(for: draft.taskID), id: \.id) { task in
                                Text(indentedTitle(task)).tag(Optional(task.id))
                            }
                        }

                        HStack {
                            Text(.app("editor.task.symbolColor"))
                            Spacer()
                            Button {
                                isSymbolPickerPresented = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: draft.iconName)
                                        .foregroundStyle(Color(hex: draft.colorHex) ?? .blue)
                                    Text(.app("common.choose"))
                                }
                            }
                            #if os(macOS)
                            .popover(isPresented: $isSymbolPickerPresented) {
                                SymbolAndColorPicker(
                                    symbols: SymbolCatalog.symbolNames,
                                    searchKeywords: SymbolCatalog.searchKeywords,
                                    colors: colors,
                                    symbolName: $draft.iconName,
                                    colorHex: $draft.colorHex
                                )
                                .frame(width: 460, height: 520)
                            }
                            #endif
                        }
                    }

                    Section(AppStrings.localized("editor.task.plan")) {
                        Stepper(value: estimatedMinutesBinding, in: 0...600, step: 15) {
                            LabeledContent(AppStrings.localized("editor.task.estimate"), value: draft.estimatedMinutes.map { String(format: AppStrings.localized("common.minutes"), $0) } ?? AppStrings.localized("editor.task.notSet"))
                        }

                        Toggle(AppStrings.localized("editor.task.setDue"), isOn: $draft.hasDueDate)
                        if draft.hasDueDate {
                            DatePicker(AppStrings.localized("editor.task.due"), selection: $draft.dueAt, displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    Section {
                        if draft.checklistItems.isEmpty {
                            Text(.app("editor.checklist.empty"))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(orderedChecklistIndices.enumerated()), id: \.element) { visualIndex, index in
                            ChecklistEditorRow(
                                item: $draft.checklistItems[index],
                                canMoveUp: visualIndex > 0,
                                canMoveDown: visualIndex < orderedChecklistIndices.count - 1,
                                moveUp: { moveChecklistItem(atVisualIndex: visualIndex, direction: -1) },
                                moveDown: { moveChecklistItem(atVisualIndex: visualIndex, direction: 1) },
                                delete: { draft.checklistItems.remove(at: index) },
                                focus: $focusedChecklistDraftID,
                                submit: { addChecklistItem(afterVisualIndex: visualIndex) }
                            )
                        }

                        Button {
                            addChecklistItem()
                        } label: {
                            Label(AppStrings.localized("editor.checklist.add"), systemImage: "plus")
                        }
                    } header: {
                        Text(.app("editor.checklist.title"))
                    } footer: {
                        Text(.app("editor.checklist.footer"))
                    }

                    Section(AppStrings.localized("editor.task.notes")) {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 88)
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle(draft.taskID == nil ? AppStrings.localized("editor.task.newTitle") : AppStrings.localized("editor.task.editTitle"))
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
                    .disabled(!canSave)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $isSymbolPickerPresented) {
                NavigationStack {
                    SymbolAndColorPicker(
                        symbols: SymbolCatalog.symbolNames,
                        searchKeywords: SymbolCatalog.searchKeywords,
                        colors: colors,
                        symbolName: $draft.iconName,
                        colorHex: $draft.colorHex
                    )
                    .navigationTitle(AppStrings.localized("editor.symbol.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppStrings.done) {
                                isSymbolPickerPresented = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
            #endif
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var orderedChecklistIndices: [Int] {
        draft.checklistItems.indices.sorted { lhs, rhs in
            let left = draft.checklistItems[lhs]
            let right = draft.checklistItems[rhs]
            if left.isCompleted != right.isCompleted {
                return !left.isCompleted
            }
            return lhs < rhs
        }
    }

    private var parentTitle: String {
        guard let parentID = draft.parentID, let task = store.task(for: parentID) else {
            return AppStrings.localized("editor.task.rootTitle")
        }
        return store.path(for: task)
    }

    private var parentBinding: Binding<UUID?> {
        Binding {
            draft.parentID
        } set: { value in
            draft.parentID = value
        }
    }

    private var estimatedMinutesBinding: Binding<Int> {
        Binding {
            draft.estimatedMinutes ?? 0
        } set: { value in
            draft.estimatedMinutes = value == 0 ? nil : value
        }
    }

    private func indentedTitle(_ task: TaskNode) -> String {
        String(repeating: "  ", count: task.depth) + task.title
    }

    private func moveChecklistItem(from source: Int, to destination: Int) {
        guard draft.checklistItems.indices.contains(source),
              draft.checklistItems.indices.contains(destination) else {
            return
        }
        draft.checklistItems.swapAt(source, destination)
    }

    private func moveChecklistItem(atVisualIndex visualIndex: Int, direction: Int) {
        let ordered = orderedChecklistIndices
        let targetVisualIndex = visualIndex + direction
        guard ordered.indices.contains(visualIndex),
              ordered.indices.contains(targetVisualIndex) else {
            return
        }
        moveChecklistItem(from: ordered[visualIndex], to: ordered[targetVisualIndex])
    }

    private func addChecklistItem(afterVisualIndex visualIndex: Int? = nil) {
        let newItem = ChecklistEditorDraft()
        if let visualIndex {
            let insertionIndex = min(visualIndex + 1, draft.checklistItems.count)
            draft.checklistItems.insert(newItem, at: insertionIndex)
        } else {
            draft.checklistItems.append(newItem)
        }
        focusedChecklistDraftID = newItem.id
    }
}
