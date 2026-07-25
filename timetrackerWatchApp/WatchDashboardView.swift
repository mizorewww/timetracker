import SwiftUI

enum WatchDashboardPage: Hashable {
    case activeTimers
    case quickStart
    case allTasks

    var titleKey: LocalizedStringKey {
        switch self {
        case .activeTimers:
            "watch.active.title"
        case .quickStart:
            "watch.quickStart.title"
        case .allTasks:
            "watch.tasks.all"
        }
    }
}

struct WatchDashboardView: View {
    private static let quickStartTaskLimit =
        WatchTransportLimits.legacyQuickStartTaskLimit

    @State private var selectedPage: WatchDashboardPage = .activeTimers
    @State private var hasSelectedInitialPage = false

    let snapshot: WatchStateSnapshot
    let isReachable: Bool
    let hasReceivedSnapshot: Bool
    let pendingCommands: [WatchTimerCommand]
    let failedCommands: [WatchFailedCommand]
    let isSnapshotStale: Bool
    let hasConnectivityError: Bool
    let onStopTimer: (UUID) -> Void
    let onStartTask: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void
    let onDiscardCommand: (UUID) -> Void

    var body: some View {
        let commandIndex = WatchCommandPresentationIndex(
            pendingCommands: pendingCommands,
            failedCommands: failedCommands
        )
        let activeTaskIDs = Set(snapshot.activeTimers.map(\.taskID))

        NavigationStack {
            TabView(selection: $selectedPage) {
                WatchActiveTimersPage(
                    timers: snapshot.activeTimers,
                    snapshotFreshness: snapshotFreshness,
                    generatedAt: snapshot.generatedAt,
                    hasReceivedSnapshot: hasReceivedSnapshot,
                    status: status,
                    failures: failureItems,
                    commandIndex: commandIndex,
                    onStopTimer: onStopTimer,
                    onRetryCommand: onRetryCommand,
                    onDiscardCommand: onDiscardCommand
                )
                .tag(WatchDashboardPage.activeTimers)
                .accessibilityIdentifier("watch.page.active")

                WatchTaskListView(
                    kind: .quickStart,
                    tasks: quickStartTasks(activeTaskIDs: activeTaskIDs),
                    activeTaskIDs: activeTaskIDs,
                    hasReceivedSnapshot: hasReceivedSnapshot,
                    commandIndex: commandIndex,
                    onStartTask: onStartTask,
                    onRetryCommand: onRetryCommand,
                    onShowActiveTimers: showActiveTimers
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    attentionButton
                }
                .tag(WatchDashboardPage.quickStart)
                .accessibilityIdentifier("watch.page.quickStart")

                WatchTaskListView(
                    kind: .allTasks,
                    tasks: snapshot.allTasksByUsage,
                    activeTaskIDs: activeTaskIDs,
                    hasReceivedSnapshot: hasReceivedSnapshot,
                    commandIndex: commandIndex,
                    onStartTask: onStartTask,
                    onRetryCommand: onRetryCommand,
                    onShowActiveTimers: showActiveTimers
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    attentionButton
                }
                .tag(WatchDashboardPage.allTasks)
                .accessibilityIdentifier("watch.page.allTasks")
            }
            .tabViewStyle(.verticalPage)
            .navigationTitle(selectedPage.titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectInitialPageIfNeeded()
            }
            .onChange(of: hasReceivedSnapshot) {
                selectInitialPageIfNeeded()
            }
        }
    }

    private var snapshotFreshness: WatchSnapshotFreshness {
        isSnapshotStale ? .stale : snapshot.freshness(at: Date())
    }

    private func quickStartTasks(activeTaskIDs: Set<UUID>) -> [WatchRecentTaskSnapshot] {
        let availableTasks = snapshot.recentTasks.filter {
            !activeTaskIDs.contains($0.taskID)
        }
        let pinnedTasks = availableTasks
            .filter { $0.quickStartRank != nil }
            .sorted {
                ($0.quickStartRank ?? .max) < ($1.quickStartRank ?? .max)
            }
        let pinnedTaskIDs = Set(pinnedTasks.map(\.taskID))
        let frequentFillTasks = availableTasks.filter {
            !pinnedTaskIDs.contains($0.taskID)
        }
        return Array(
            (pinnedTasks + frequentFillTasks)
                .prefix(Self.quickStartTaskLimit)
        )
    }

    private var failureItems: [WatchCommandFailurePresentation] {
        failedCommands.map {
            WatchCommandFailurePresentation(failure: $0, title: failureTitle(for: $0))
        }
    }

    private var status: WatchSyncStatus? {
        if !hasReceivedSnapshot {
            return hasConnectivityError ? .connectionError : .waitingForFirstSnapshot
        }
        if !pendingCommands.isEmpty {
            return isReachable && !hasConnectivityError ? .sending : .queued
        }
        if hasConnectivityError {
            return .connectionError
        }
        if isSnapshotStale {
            return .stale
        }
        return nil
    }

    private func showActiveTimers() {
        selectedPage = .activeTimers
    }

    @ViewBuilder
    private var attentionButton: some View {
        if status != nil || failureItems.isEmpty == false {
            HStack {
                Button(action: showActiveTimers) {
                    Label(
                        "watch.attention.open",
                        systemImage: attentionSystemImage
                    )
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(failureItems.isEmpty ? status?.tint ?? .orange : .orange)
                .accessibilityHint(Text("watch.attention.hint"))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
        }
    }

    private var attentionSystemImage: String {
        if failureItems.isEmpty == false {
            return "exclamationmark.triangle.fill"
        }
        return status?.systemImage ?? "exclamationmark.circle"
    }

    private func selectInitialPageIfNeeded() {
        guard hasReceivedSnapshot, hasSelectedInitialPage == false else { return }
        #if DEBUG
        selectedPage = auditInitialPage ?? preferredInitialPage
        #else
        selectedPage = preferredInitialPage
        #endif
        hasSelectedInitialPage = true
    }

    #if DEBUG
    private var auditInitialPage: WatchDashboardPage? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--watch-ui-audit-page-active") {
            return .activeTimers
        }
        if arguments.contains("--watch-ui-audit-page-quick") {
            return .quickStart
        }
        if arguments.contains("--watch-ui-audit-page-all") {
            return .allTasks
        }
        return nil
    }
    #endif

    private var preferredInitialPage: WatchDashboardPage {
        if snapshot.activeTimers.isEmpty == false ||
            status != nil ||
            failureItems.isEmpty == false
        {
            return .activeTimers
        }
        return .quickStart
    }

    private func failureTitle(for failure: WatchFailedCommand) -> String {
        switch failure.command.type {
        case .startTask:
            snapshot.recentTasks.first { $0.taskID == failure.command.taskID }?.title
                ?? String(localized: "watch.command.startFallback")
        case .stopSegment:
            snapshot.activeTimers.first { $0.id == failure.command.segmentID }?.title
                ?? String(localized: "watch.command.stopFallback")
        }
    }
}
