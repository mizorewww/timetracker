import SwiftUI

struct PomodoroFocusTaskPickerSheet: View {
    let store: TimeTrackerStore
    let selectedTaskID: UUID?
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    var body: some View {
        NavigationStack {
            TaskHierarchyPicker(
                store: store,
                mode: .singleSelection(selectedTaskID: selectedTaskID),
                onDismiss: onCancel,
                onSelect: onSelect,
                onCreateTask: nil
            )
        }
        #if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        #else
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}
