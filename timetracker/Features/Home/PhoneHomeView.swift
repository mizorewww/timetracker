#if os(iOS)
import SwiftUI

struct PhoneHomeView: View {
    let store: TimeTrackerStore
    let openSettings: () -> Void
    let openTask: (UUID) -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let content = TodayHomeContent(store: store)

        List {
            PhoneNowSection(
                store: store,
                segments: content.activeSegments,
                allowsParallelTimers: store.preferences.allowParallelTimers,
                openTask: openTask,
                startTimer: { presentationRouter.presentStartTaskPicker() }
            )

            Section(AppStrings.localized("home.overview.title")) {
                PhoneTodaySummaryRow(store: store)
                    .accessibilityIdentifier("home.overview")
            }

            PhoneQuickStartSection(
                store: store,
                tasks: content.quickStartTasks,
                startTimer: { presentationRouter.presentStartTaskPicker() },
                editQuickStart: { presentationRouter.presentQuickStartEditor(using: store) }
            )

            PhoneTimelineSection(
                store: store,
                segments: content.timelineSegments,
                openTask: openTask
            )

            if !content.forecasts.isEmpty {
                PhoneForecastSection(
                    store: store,
                    forecasts: content.forecasts,
                    openTask: openTask
                )
            }

            if !content.countdownEvents.isEmpty {
                PhoneCountdownSection(events: content.countdownEvents)
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.bottom, dynamicTypeSize.isAccessibilitySize ? 112 : 16, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(AppStrings.today)
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("home.view")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openSettings) {
                    Label(AppStrings.settings, systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("settings.open")
            }
        }
    }
}
#endif
