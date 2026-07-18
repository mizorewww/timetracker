import SwiftUI

struct TodayTimerAction: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter

    var body: some View {
        startButton
    }

    @ViewBuilder
    private var startButton: some View {
        if store.activeSegments.isEmpty {
            startButtonContent
                .buttonStyle(.borderedProminent)
        } else {
            startButtonContent
                .buttonStyle(.bordered)
        }
    }

    private var startButtonContent: some View {
        Button {
            presentationRouter.presentStartTaskPicker()
        } label: {
            AppActionLabel(title: actionTitle, systemImage: actionSystemImage)
        }
        .controlSize(.large)
        .accessibilityIdentifier("home.startTimer")
    }

    private var actionTitle: String {
        store.timerPickerMode.title
    }

    private var actionSystemImage: String {
        store.timerPickerMode.systemImage
    }
}

struct TaskStartPickerSheet: View {
    let store: TimeTrackerStore
    let onDone: () -> Void
    let onCreateTask: () -> Void
#if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif

    var body: some View {
        NavigationStack {
            TaskHierarchyPicker(
                store: store,
                mode: .timer,
                onDismiss: onDone,
                onCreateTask: onCreateTask
            )
        }
#if os(iOS)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
#else
        .frame(minWidth: 420, minHeight: 520)
#endif
    }
}
