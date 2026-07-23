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
                        category: category,
                        canMoveUp: category.id != orderedCategories.first?.id,
                        canMoveDown: category.id != orderedCategories.last?.id,
                        moveUp: {
                            moveCategory(category.id, offset: -1)
                        },
                        moveDown: {
                            moveCategory(category.id, offset: 1)
                        }
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

    private func moveCategory(_ categoryID: UUID, offset: Int) {
        guard let sourceIndex = orderedCategories.firstIndex(
            where: { $0.id == categoryID }
        ) else {
            return
        }
        let destinationIndex = sourceIndex + offset
        guard orderedCategories.indices.contains(destinationIndex) else {
            return
        }
        orderedCategories.swapAt(sourceIndex, destinationIndex)
    }
}

private struct TaskCategoryOrderingRow: View {
    let category: TaskCategoryOrderingItem
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(category.title)
                    .lineLimit(nil)
            } icon: {
                Image(systemName: category.iconName)
                    .foregroundStyle(Color(hex: category.colorHex) ?? .secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                        .frame(
                            width: AppLayout.minimumInteractiveTarget,
                            height: AppLayout.minimumInteractiveTarget
                        )
                }
                .disabled(canMoveUp == false)
                .accessibilityLabel(AppStrings.localized("common.moveUp"))
                .accessibilityIdentifier(
                    "taskCategory.sort.moveUp.\(category.id.uuidString)"
                )

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                        .frame(
                            width: AppLayout.minimumInteractiveTarget,
                            height: AppLayout.minimumInteractiveTarget
                        )
                }
                .disabled(canMoveDown == false)
                .accessibilityLabel(AppStrings.localized("common.moveDown"))
                .accessibilityIdentifier(
                    "taskCategory.sort.moveDown.\(category.id.uuidString)"
                )
            }
            .buttonStyle(.borderless)
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
