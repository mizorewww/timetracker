import SwiftUI

struct QuickStartSection: View {
    let store: TimeTrackerStore
    let tasks: [TaskNode]
    let openTask: (UUID) -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppStrings.quickStart)
                    .font(.headline)
                    .accessibilityIdentifier("home.quickStart")
                Spacer()
                HomeSectionInformationButton.quickStart
                Button {
                    presentationRouter.presentQuickStartEditor(using: store)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(AppStrings.localized("quickStart.edit"))
                .accessibilityIdentifier("home.quickStart.edit")
                .help(AppStrings.localized("quickStart.edit"))
            }

            if tasks.isEmpty {
                ContentUnavailableView(
                    AppStrings.localized("quickStart.empty.title"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(.app("quickStart.empty.description"))
                )
                .frame(maxWidth: .infinity, minHeight: 104)
            } else {
                QuickStartTaskGroup(
                    tasks: tasks,
                    store: store,
                    openTask: openTask
                )
            }
        }
    }
}
