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
        PhoneDestinationDeck(store: store, selectedDestination: chrome.selectedDestination)
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

private struct PhoneDestinationDeck: View {
    @ObservedObject var store: TimeTrackerStore
    let selectedDestination: TimeTrackerStore.DesktopDestination
    @State private var cachedDestinations: Set<TimeTrackerStore.DesktopDestination> = [.today]
    var body: some View {
        ZStack {
            ForEach(TimeTrackerStore.DesktopDestination.phoneDestinations) { destination in
                if cachedDestinations.contains(destination) {
                    PhoneDestinationStack(
                        store: store,
                        destination: destination,
                        isActive: destination == selectedDestination
                    )
                    .opacity(destination == selectedDestination ? 1 : 0)
                    .allowsHitTesting(destination == selectedDestination)
                    .accessibilityHidden(destination != selectedDestination)
                }
            }
        }
        .onAppear {
            cache(selectedDestination)
        }
        .onChange(of: selectedDestination) { _, destination in
            cache(destination)
            store.prewarmDestinationCache(for: destination)
        }
        .task {
            await prewarmDestinations()
        }
    }

    private func cache(_ destination: TimeTrackerStore.DesktopDestination) {
        cachedDestinations.insert(destination)
    }

    private func prewarmDestinations() async {
        for destination in TimeTrackerStore.DesktopDestination.phoneDestinations where !cachedDestinations.contains(destination) {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            store.prewarmDestinationCache(for: destination)
            cache(destination)
        }
    }
}

private struct PhoneDestinationStack: View {
    @ObservedObject var store: TimeTrackerStore
    let destination: TimeTrackerStore.DesktopDestination
    let isActive: Bool

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
                AnalyticsView(store: store, isActive: isActive)
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
