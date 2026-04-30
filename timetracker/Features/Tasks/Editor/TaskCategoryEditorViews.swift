import SwiftUI

struct TaskCategoryEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskCategoryEditorDraft
    @State private var draft: TaskCategoryEditorDraft

    private let colors = TaskColorPalette.hexValues
    private let symbols = [
        "briefcase", "house", "heart", "figure.run", "book", "graduationcap",
        "person.2", "paintpalette", "sparkles", "leaf", "cart", "square.grid.2x2"
    ]

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

                    Picker(AppStrings.localized("taskCategory.symbol"), selection: $draft.iconName) {
                        ForEach(symbols, id: \.self) { symbol in
                            Label(symbol, systemImage: symbol).tag(symbol)
                        }
                    }

                    colorGrid
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

    private var colorGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(.app("editor.symbol.color"))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28, maximum: 32), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        draft.colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if draft.colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: AppStrings.localized("editor.symbol.colorValue"), hex))
                }
            }
        }
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
