import SwiftUI

/// Warms up Swift runtime type metadata for the tab pages' view hierarchies
/// after launch.
///
/// Measured on the dense fixture (1,200 tasks): first switches spent
/// ~500 ms (Tasks) / 100-200 ms (other pages) of main-thread time in lazy
/// Swift protocol-conformance and type-metadata resolution
/// (`swift_conformsToProtocolMaybeInstantiateSuperclasses`), independent of
/// row count and row content, in Debug and Release. `ContentView` mounts each
/// page once off-screen inside its own hierarchy (complete environment,
/// correct layout) and removes it right after; first switches then pay only
/// layout, not metadata resolution.
enum ViewTypePreheater {
    static let phaseCount = 1

    @ViewBuilder
    static func preheaterView(
        phase: Int,
        store: TimeTrackerStore
    ) -> some View {
        switch phase {
        case 0:
            TasksNavigationView(store: store)
        case 1:
            InboxView(store: store)
        case 2:
            PomodoroView(store: store)
        case 3:
            AnalyticsView(store: store)
        default:
            EmptyView()
        }
    }
}
