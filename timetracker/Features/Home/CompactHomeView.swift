import SwiftUI

/// Today at compact width: one grouped `List` of sections, as opposed to the
/// width-driven card canvas `DesktopMainView` draws when there is room for it.
struct CompactHomeView: View {
    let store: TimeTrackerStore
    let openSettings: () -> Void
    let openTask: (UUID) -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var clockNow = Date()

    var body: some View {
        // A ledger write can re-render the page between clock ticks; never
        // read a just-written stop date as a still-open future end.
        let now = max(clockNow, Date())
        let today = store.todaySnapshot(now: now)
        let content = today.content

        List {
            CompactNowSection(
                store: store,
                segments: content.activeSegments,
                openTask: openTask,
                startTimer: { presentationRouter.present(.startTaskPicker) }
            )

            Section {
                CompactTodaySummaryRow(store: store, metrics: today.live.metrics)
                    .accessibilityIdentifier("home.overview")
            } header: {
                HomeOverviewHeader(
                    container: .listSection,
                    showsWallTime: store.preferences.showGrossAndWallTogether
                )
                .textCase(nil)
            }

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

            CompactQuickStartSection(
                store: store,
                tasks: content.quickStartTasks,
                startTimer: { presentationRouter.present(.startTaskPicker) },
                editQuickStart: { presentationRouter.present(.quickStartEditor(selectedIDs: store.preferences.quickStartTaskIDs)) },
                openTask: openTask
            )

            CompactTimelineSection(
                store: store,
                live: today.live,
                openTask: openTask
            )

            if !content.forecasts.isEmpty {
                CompactForecastSection(
                    store: store,
                    forecasts: content.forecasts,
                    openTask: openTask
                )
            }

            if !content.countdownEvents.isEmpty {
                CompactCountdownSection(events: content.countdownEvents)
            }
        }
        // `.insetGrouped` and keyboard dismissal have no AppKit equivalent.
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        #else
        .listStyle(.inset)
        #endif
        .contentMargins(.bottom, dynamicTypeSize.isAccessibilitySize ? 112 : 16, for: .scrollContent)
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
