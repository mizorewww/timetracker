import SwiftUI

/// Today at compact width: one grouped `List` of sections, as opposed to the
/// width-driven card canvas `DesktopMainView` draws when there is room for it.
struct CompactHomeView: View {
    let store: TimeTrackerStore
    let openSettings: () -> Void
    let openTask: (UUID) -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        #if DEBUG
        let _ = PageSwitchTrace.mark("TODAY-BODY-START")
        #endif
        let content = store.todayHomeContent()
        #if DEBUG
        let _ = PageSwitchTrace.mark("TODAY-CONTENT-DONE")
        #endif

        List {
            CompactNowSection(
                store: store,
                segments: content.activeSegments,
                openTask: openTask,
                startTimer: { presentationRouter.presentStartTaskPicker() }
            )

            Section {
                CompactTodaySummaryRow(store: store)
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
                container: .listSection
            )
            .homeVisualizationListSection()

            HomeActivityHeatmapSection(
                store: store,
                container: .listSection
            )
            .homeVisualizationListSection()

            CompactQuickStartSection(
                store: store,
                tasks: content.quickStartTasks,
                startTimer: { presentationRouter.presentStartTaskPicker() },
                editQuickStart: { presentationRouter.presentQuickStartEditor(using: store) },
                openTask: openTask
            )

            CompactTimelineSection(
                store: store,
                segments: content.timelineSegments,
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
            .onAppear {
                #if DEBUG
                PageSwitchTrace.mark("APPEAR today")
                #endif
            }
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
