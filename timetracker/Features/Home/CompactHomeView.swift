import SwiftUI

/// Today at compact width: one grouped `List` of sections, as opposed to the
/// width-driven card canvas `DesktopMainView` draws when there is room for it.
struct CompactHomeView: View {
    let store: TimeTrackerStore
    let openSettings: () -> Void
    let openTask: (UUID) -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var clockNow = Date()

    var body: some View {
        // A ledger write can re-render the page between clock ticks; never
        // read a just-written stop date as a still-open future end.
        let now = max(clockNow, Date())
        let today = store.todaySnapshot(now: now)
        let content = today.content
        let startTimer: () -> Void = { presentationRouter.present(.startTaskPicker) }

        List {
            HomeNowSection(
                store: store,
                container: .listSection,
                segments: content.activeSegments,
                openTask: openTask,
                startTimer: startTimer
            )

            HomeOverviewSection(
                container: .listSection,
                metrics: today.live.metrics,
                showsWallTime: store.preferences.showGrossAndWallTogether
            )

            HomeWeeklyGrossTimeSection(
                store: store,
                container: .listSection,
                now: now
            )
            .homeVisualizationListSection()

            HomeActivityHeatmapSection(
                store: store,
                container: .listSection,
                now: now
            )
            .homeVisualizationListSection()

            HomeQuickStartSection(
                store: store,
                container: .listSection,
                tasks: content.quickStartTasks,
                openTask: openTask,
                startTimer: startTimer
            )

            HomeTimelineSection(
                store: store,
                container: .listSection,
                live: today.live,
                openTask: openTask
            )

            HomeForecastSection(
                store: store,
                container: .listSection,
                forecasts: content.forecasts,
                openTask: openTask
            )

            HomeCountdownSection(
                container: .listSection,
                events: content.countdownEvents
            )
        }
        // `.insetGrouped` and keyboard dismissal have no AppKit equivalent.
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        #else
        .listStyle(.inset)
        #endif
        .bottomScrollClearance()
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(AppStrings.today)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .accessibilityIdentifier("home.view")
        .liveClock($clockNow, until: LiveClockDeadline.next(after: now, isLive: today.live.isLive))
        .toolbar {
            // `.primaryAction` resolves to the navigation bar's trailing slot on
            // iOS and the window toolbar on macOS, so no branch is needed.
            ToolbarItem(placement: .primaryAction) {
                Button(action: openSettings) {
                    Label(AppStrings.settings, systemImage: "gearshape")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("settings.open")
            }
        }
    }
}
