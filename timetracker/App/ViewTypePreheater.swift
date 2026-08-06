import SwiftUI

/// Warms up Swift runtime type metadata AND SwiftUI layout descriptors for the
/// Tasks page before the user first switches to it.
///
/// Measured on the dense fixture: the first switch to Tasks spent ~500 ms in
/// lazy Swift protocol-conformance resolution and, after preheating that,
/// another ~300-400 ms in AttributeGraph LayoutDescriptor construction (Swift
/// metadata reflection over view fields), both one-time-per-process costs in
/// Debug and Release, independent of row count and row content.
///
/// The preheat mounts the Tasks tab inside a real TabView (same environment
/// shape as the compact shell, Tasks pre-selected) off-screen and removes it
/// after a layout pass. Earlier variants failed because:
/// - hidden standalone windows never run SwiftUI layout;
/// - an overlay-mounted page resolves metadata but not the TabView-path
///   layout descriptors (different environment → cache miss);
/// - opacity(0) makes the system skip the subtree entirely.
enum ViewTypePreheater {
    /// A minimal TabView with one page pre-selected, mounted off-screen by
    /// the caller. Mirrors the compact shell's environment so the layout
    /// descriptors built here are the ones the real switch will hit.
    struct PreheatTabHost: View {
        let store: TimeTrackerStore
        let preselected: TimeTrackerStore.DesktopDestination
        @State private var selection: TimeTrackerStore.DesktopDestination

        init(
            store: TimeTrackerStore,
            preselected: TimeTrackerStore.DesktopDestination
        ) {
            self.store = store
            self.preselected = preselected
            _selection = State(
                initialValue: preselected
            )
        }

        @ViewBuilder
        private func pageContent(
            _ destination: TimeTrackerStore.DesktopDestination
        ) -> some View {
            switch destination {
            case .today:
                Color.clear
            case .inbox:
                InboxView(store: store)
            case .tasks:
                TasksNavigationView(store: store)
            case .pomodoro:
                PomodoroView(store: store)
            case .analytics:
                AnalyticsView(store: store)
            case .settings:
                Color.clear
            }
        }

        var body: some View {
            TabView(selection: $selection) {
                Tab(value: .tasks) {
                    pageContent(.tasks)
                } label: {
                    Label(AppStrings.tasks, systemImage: "checklist")
                }

                Tab(value: .inbox) {
                    pageContent(.inbox)
                } label: {
                    Label(AppStrings.inbox, systemImage: "tray")
                }

                Tab(value: .pomodoro) {
                    pageContent(.pomodoro)
                } label: {
                    Label(AppStrings.focus, systemImage: "timer")
                }

                Tab(value: .analytics) {
                    pageContent(.analytics)
                } label: {
                    Label(AppStrings.analytics, systemImage: "chart.bar.xaxis")
                }
            }
        }
    }

    @MainActor
    static func preheatPage(
        destination: TimeTrackerStore.DesktopDestination,
        store: TimeTrackerStore,
        presentationRouter: AppPresentationRouter,
        feedbackRouter: AppSceneFeedbackRouter
    ) {
        #if os(iOS)
        let host = UIHostingController(
            rootView: PreheatTabHost(
                store: store,
                preselected: destination
            )
            .environment(presentationRouter)
            .environment(feedbackRouter)
            .environment(\.layoutShell, .compact)
        )
        host.view.frame = CGRect(x: 0, y: 10000, width: 390, height: 844)
        host.view.isHidden = false
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.keyWindow != nil })?
            .keyWindow
        else { return }
        window.addSubview(host.view)
        host.view.layoutIfNeeded()
        DispatchQueue.main.async {
            host.view.layoutIfNeeded()
            host.view.removeFromSuperview()
        }
        #endif
    }
}
