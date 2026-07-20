import SwiftUI

struct TaskCategoryPickerSheet: View {
    let store: TimeTrackerStore
    let selectedCategoryID: UUID?
    let context: TaskCategoryPickerSelectionContext
    let onDismiss: () -> Void
    let onSelect: (UUID) -> Void

    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    var body: some View {
        NavigationStack {
            TaskCategoryPicker(
                options: store.taskCategories.map {
                    TaskCategoryPickerOption(
                        id: $0.id,
                        title: $0.title,
                        iconName: $0.iconName ?? "square.grid.2x2",
                        colorHex: $0.colorHex
                    )
                },
                selectedCategoryID: selectedCategoryID,
                context: context,
                onDismiss: onDismiss,
                onSelect: onSelect
            )
        }
        #if os(iOS)
        .presentationDetents(
            dynamicTypeSize.isAccessibilitySize
                ? [.large]
                : [.medium, .large]
        )
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}
