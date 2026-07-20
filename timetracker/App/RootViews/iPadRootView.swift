import SwiftUI

#if os(iOS)
struct iPadRootView: View {
    let store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
    private let layout = SplitColumnLayoutPolicy.iPad

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            SidebarView(store: store) {
                preferredCompactColumn = .detail
            }
            .navigationSplitViewColumnWidth(
                min: layout.sidebar.min,
                ideal: layout.sidebar.ideal,
                max: layout.sidebar.max ?? layout.sidebar.ideal
            )
        } detail: {
            DesktopContentView(store: store)
                .navigationSplitViewColumnWidth(
                    min: layout.detail.min,
                    ideal: layout.detail.ideal
                )
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("ipad.splitNavigation")
        .onChange(of: store.desktopDestination) { _, _ in
            preferredCompactColumn = .detail
        }
    }
}
#endif
