import SwiftUI

struct TaskCategoryEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskCategoryEditorDraft
    @State private var draft: TaskCategoryEditorDraft

    init(store: TimeTrackerStore, initialDraft: TaskCategoryEditorDraft) {
        self.store = store
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("taskCategory.editor.info")) {
                    TextField(AppStrings.localized("taskCategory.name"), text: $draft.title)
                    SymbolColorPickerRow(
                        colors: TaskColorPalette.hexValues,
                        symbolName: $draft.iconName,
                        colorHex: $draft.colorHex
                    )
                }

                Section {
                    Toggle(isOn: $draft.includesInForecast) {
                        Label(AppStrings.localized("taskCategory.includesForecast"), systemImage: "chart.line.uptrend.xyaxis")
                    }
                } footer: {
                    Text(.app("taskCategory.includesForecast.footer"))
                }

                if draft.categoryID != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteCategory()
                        } label: {
                            Label(AppStrings.localized("taskCategory.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(initialDraft.categoryID == nil ? AppStrings.localized("taskCategory.new") : AppStrings.localized("taskCategory.edit"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        store.taskCategoryEditorDraft = nil
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        if store.saveTaskCategoryDraft(draft) {
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .platformSheetFrame(width: 460, height: 440)
    }

    private func deleteCategory() {
        guard let categoryID = draft.categoryID,
              let category = store.taskCategory(for: categoryID) else {
            return
        }
        store.deleteTaskCategory(category)
        store.taskCategoryEditorDraft = nil
        dismiss()
    }
}
