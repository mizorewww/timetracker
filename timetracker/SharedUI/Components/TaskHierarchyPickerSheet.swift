import SwiftUI

struct TaskHierarchyPickerSheet: View {
    let store: TimeTrackerStore
    let mode: TaskHierarchyPickerMode
    let onDismiss: () -> Void
    let onSelect: (UUID) -> Void
    let onCreateTask: (() -> Void)?

    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    init(
        store: TimeTrackerStore,
        mode: TaskHierarchyPickerMode,
        onDismiss: @escaping () -> Void,
        onSelect: @escaping (UUID) -> Void = { _ in },
        onCreateTask: (() -> Void)? = nil
    ) {
        self.store = store
        self.mode = mode
        self.onDismiss = onDismiss
        self.onSelect = onSelect
        self.onCreateTask = onCreateTask
    }

    var body: some View {
        NavigationStack {
            TaskHierarchyPicker(
                store: store,
                mode: mode,
                onDismiss: onDismiss,
                onSelect: onSelect,
                onCreateTask: onCreateTask
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
