#if os(iOS)
import SwiftUI

struct PhoneHomeView: View {
    let store: TimeTrackerStore
    let openSettings: () -> Void
    let openTask: (UUID) -> Void
    @State private var isTaskPickerPresented = false
    @State private var isQuickStartEditorPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let content = TodayHomeContent(store: store)

        List {
            PhoneNowSection(
                store: store,
                segments: content.activeSegments,
                allowsParallelTimers: store.preferences.allowParallelTimers,
                openTask: openTask,
                startTimer: { isTaskPickerPresented = true }
            )

            Section(AppStrings.localized("home.overview.title")) {
                PhoneTodaySummaryRow(store: store)
                    .accessibilityIdentifier("home.overview")
            }

            PhoneQuickStartSection(
                store: store,
                tasks: content.quickStartTasks,
                startTimer: { isTaskPickerPresented = true },
                editQuickStart: { isQuickStartEditorPresented = true }
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
        .sheet(isPresented: $isTaskPickerPresented) {
            TaskStartPickerSheet(store: store) {
                isTaskPickerPresented = false
            }
        }
        .sheet(isPresented: $isQuickStartEditorPresented) {
            QuickStartEditorSheet(
                store: store,
                selectedIDs: store.preferences.quickStartTaskIDs,
                onSave: store.setQuickStartTaskIDs
            )
        }
    }
}
#endif
