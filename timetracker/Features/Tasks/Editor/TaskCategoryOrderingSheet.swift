import SwiftUI

struct TaskCategoryOrderingSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var baseline: TaskCategoryOrderMutationBaseline
    @State private var orderedCategories: [TaskCategoryOrderingItem]

    init(store: TimeTrackerStore) {
        self.store = store
        let categories = store.taskCategories
        _baseline = State(
            initialValue: TaskCategoryOrderMutationBaseline(
                categories: categories
            )
        )
        _orderedCategories = State(
            initialValue: categories.map {
                TaskCategoryOrderingItem(category: $0)
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedCategories) { category in
                    TaskCategoryOrderingRow(
                        category: category
                    )
                    .accessibilityIdentifier(
                        "taskCategory.sort.row.\(category.id.uuidString)"
                    )
                }
                .onMove(perform: moveCategories)
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle(AppStrings.localized("taskCategory.sort"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .accessibilityIdentifier("taskCategory.sorter")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppStrings.cancel) {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("taskCategory.sort.cancel")
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppStrings.done) {
                            if store.reorderTaskCategories(
                                orderedCategoryIDs: orderedCategories.map(\.id),
                                baseline: baseline
                            ) {
                                dismiss()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("taskCategory.sort.done")
                    }
                }
        }
        .platformSheetFrame(width: 480, height: 520)
    }

    private func moveCategories(
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        orderedCategories.move(
            fromOffsets: source,
            toOffset: destination
        )
    }
}

private struct TaskCategoryOrderingRow: View {
    let category: TaskCategoryOrderingItem

    var body: some View {
        Label {
            Text(category.title)
                .lineLimit(nil)
        } icon: {
            Image(systemName: category.iconName)
                .foregroundStyle(Color(hex: category.colorHex) ?? .secondary)
        }
        .frame(minHeight: AppLayout.minimumInteractiveTarget)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(category.title)
    }
}

private struct TaskCategoryOrderingItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let iconName: String
    let colorHex: String?

    init(category: TaskCategory) {
        id = category.id
        title = category.title
        iconName = category.iconName ?? "square.grid.2x2"
        colorHex = category.colorHex
    }
}
