import SwiftUI

/// The app shell, chosen from measured width rather than from the device.
///
/// See `RootLayoutPolicy` for why width is the predicate. The practical effect
/// is that an iPad in Split View or Slide Over, and a Mac window dragged narrow,
/// both get the same compact shell an iPhone gets — instead of a split view
/// squeezed into a column too narrow to use.
struct AppRootView<SyncConflictContent: View>: View {
    let store: TimeTrackerStore
    let syncConflictContent: SyncConflictContent
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var measuredWidthBand: RootLayoutPolicy.WidthBand?
    @State private var lastContentDestination: TimeTrackerStore.DesktopDestination = .today

    init(
        store: TimeTrackerStore,
        @ViewBuilder syncConflictContent: () -> SyncConflictContent
    ) {
        self.store = store
        self.syncConflictContent = syncConflictContent()
    }

    private var layoutPolicy: RootLayoutPolicy {
        RootLayoutPolicy(
            measuredWidthBand: measuredWidthBand,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    var body: some View {
        let shell = layoutPolicy.shell

        Group {
            switch shell {
            case .compact:
                CompactShellRootView(
                    store: store,
                    syncConflictContent: syncConflictContent,
                    requestOpenSettings: presentSettings
                )
            case .regular:
                RegularShellRootView(store: store)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        syncConflictContent
                            .padding(8)
                    }
            }
        }
        // Nested views adapt from this instead of re-measuring or, worse,
        // asking what device they are running on.
        .environment(\.layoutShell, shell)
        #if os(macOS)
            .focusedSceneValue(\.timeTrackerStore, store)
            .focusedSceneValue(\.appPresentationRouter, presentationRouter)
        #endif
            .onGeometryChange(for: RootLayoutPolicy.WidthBand.self) { proxy in
                RootLayoutPolicy.WidthBand(width: proxy.size.width)
            } action: { widthBand in
                measuredWidthBand = widthBand
            }
            .onAppear {
                routeSettingsDestination(store.desktopDestination)
            }
            .onChange(of: store.desktopDestination) { _, destination in
                routeSettingsDestination(destination)
            }
            .onChange(of: presentationRouter.sheet?.id) { _, presentationID in
                guard presentationID == nil,
                      store.desktopDestination == .settings else { return }
                routeSettingsDestination(.settings)
            }
    }

    private func routeSettingsDestination(
        _ destination: TimeTrackerStore.DesktopDestination
    ) {
        guard destination == .settings else {
            lastContentDestination = destination
            return
        }
        guard presentSettings() else { return }
        store.desktopDestination = lastContentDestination
    }

    private func presentSettings() -> Bool {
        #if os(macOS)
        openSettings()
        return true
        #else
        return presentationRouter.presentSettings()
        #endif
    }
}

/// Sidebar plus detail, for widths that can hold both columns.
///
/// One view for iPad and Mac. They previously had near-identical copies that
/// differed only in their column-width preset; the remaining `#if os(macOS)`
/// blocks are scene plumbing that has no iOS equivalent, not layout.
struct RegularShellRootView: View {
    let store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
    private let layout = SplitColumnLayoutPolicy.standard

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
        // Kept verbatim: this is the identifier the existing XCUITests select on.
        .accessibilityIdentifier("ipad.splitNavigation")
        .onChange(of: store.desktopDestination) { _, _ in
            preferredCompactColumn = .detail
        }
    }
}
