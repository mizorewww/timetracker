#if os(macOS)
import SwiftUI

/// The Mac app shell, chosen from measured width (AD-139): a window dragged
/// narrow gets the compact shell. iOS draws its shells in UIKit
/// (`ShellController`, AD-144).
struct AppRootView: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Only the shell is retained, not the raw width: a live window resize
    /// would otherwise invalidate the whole app shell on every frame.
    @State private var measuredShell: RootLayoutPolicy.Shell?

    var body: some View {
        let shell = RootLayoutPolicy.shell(
            measured: measuredShell,
            horizontalSizeClass: horizontalSizeClass
        )

        Group {
            switch shell {
            case .compact:
                CompactShellRootView(
                    store: store,
                    openSettings: { presentationRouter.present(.settings) }
                )
            case .regular:
                RegularShellRootView(store: store)
            }
        }
        // Nested views adapt from this instead of re-measuring or, worse,
        // asking what device they are running on.
        .environment(\.layoutShell, shell)
        .focusedSceneValue(\.timeTrackerStore, store)
        .focusedSceneValue(\.appPresentationRouter, presentationRouter)
        .onGeometryChange(for: RootLayoutPolicy.Shell.self) { proxy in
            RootLayoutPolicy.shell(forWidth: proxy.size.width)
        } action: { shell in
            measuredShell = shell
        }
    }
}

/// Sidebar plus detail, for widths that can hold both columns.
struct RegularShellRootView: View {
    let store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            // 220 + 420 keeps both columns usable down to
            // `RootLayoutPolicy.regularShellMinimumWidth`.
            DesktopContentView(store: store)
                .navigationSplitViewColumnWidth(min: 420, ideal: 760)
        }
        .navigationSplitViewStyle(.balanced)
        // Kept verbatim: this is the identifier the existing XCUITests select on.
        .accessibilityIdentifier("ipad.splitNavigation")
    }
}
#endif
