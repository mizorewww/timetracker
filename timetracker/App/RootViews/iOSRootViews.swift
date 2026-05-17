import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
struct iOSRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadRootView(store: store)
        } else {
            PhoneRootView(store: store)
        }
    }
}

struct PhoneRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @StateObject private var chrome = PhoneChromeCoordinator()
    @State private var isKeyboardVisible = false

    var body: some View {
        PhoneDestinationStack(store: store, destination: chrome.selectedDestination)
            .environmentObject(chrome)
            .transaction { transaction in
                transaction.animation = nil
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if !isKeyboardVisible {
                    PhonePagedBottomSelector(
                        chrome: chrome,
                        destinations: TimeTrackerStore.DesktopDestination.phoneDestinations
                    )
                }
            }
            .onAppear {
                chrome.select(store.desktopDestination)
            }
            .onChange(of: store.desktopDestination) { _, destination in
                guard chrome.selectedDestination != destination else { return }
                chrome.select(destination)
            }
            .onChange(of: chrome.selectedDestination) { _, destination in
                guard store.desktopDestination != destination else { return }
                store.desktopDestination = destination
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isKeyboardVisible = false
            }
    }
}

private struct PhoneDestinationStack: View {
    @ObservedObject var store: TimeTrackerStore
    let destination: TimeTrackerStore.DesktopDestination

    var body: some View {
        NavigationStack {
            switch destination {
            case .today:
                PhoneHomeView(store: store)
            case .inbox:
                InboxView(store: store)
            case .tasks:
                TasksView(store: store)
            case .pomodoro:
                PomodoroView(store: store)
            case .analytics:
                AnalyticsView(store: store)
            case .settings:
                SettingsView(store: store)
            }
        }
    }
}

struct iPadRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let layout = SplitColumnLayoutPolicy.iPad

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(
                    min: layout.sidebar.min,
                    ideal: layout.sidebar.ideal,
                    max: layout.sidebar.max ?? layout.sidebar.ideal
                )
        } detail: {
            DesktopContentView(store: store)
                .navigationSplitViewColumnWidth(min: layout.detail.min, ideal: layout.detail.ideal)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if columnVisibility == .detailOnly {
                            SidebarRevealButton {
                                columnVisibility = .all
                            }
                        }
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("ipad.splitNavigation")
    }
}
#endif
