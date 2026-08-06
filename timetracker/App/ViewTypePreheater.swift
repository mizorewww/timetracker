import SwiftUI

/// Warms up Swift runtime type metadata for the Tasks page's view hierarchy
/// after launch.
///
/// Measured on the dense fixture (1,200 tasks): the first switch to Tasks
/// spent ~500 ms of main-thread time in lazy Swift protocol-conformance and
/// type-metadata resolution, independent of row count and row content, in
/// Debug and Release. `ContentView` mounts the page once off-screen inside
/// its own hierarchy and removes it right after; first switches then pay only
/// layout, not metadata resolution.
///
/// Visibility requirements learned from failed variants:
/// - opacity(0) alone: the system skips the fully invisible subtree's
///   list-cell creation — nothing gets preheated.
/// - Hidden standalone window: never runs SwiftUI layout.
/// - Off-screen offset alone: one on-screen frame at mount (the overlay
///   centers before the offset applies).
/// The current variant combines a far off-screen offset with a near-zero
/// (non-zero) opacity, so the mount frame cannot be perceived and the
/// subtree still runs a real layout pass.
enum ViewTypePreheater {
    static func tasksPreheaterView(
        store: TimeTrackerStore,
        onFinished: @escaping @MainActor () -> Void
    ) -> some View {
        TasksNavigationView(store: store)
            .frame(width: 390, height: 844)
            .offset(y: 10000)
            .opacity(0.001)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                Task { @MainActor in
                    await Task.yield()
                    onFinished()
                }
            }
    }
}
