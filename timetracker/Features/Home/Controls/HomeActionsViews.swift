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
