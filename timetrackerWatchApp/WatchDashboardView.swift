import SwiftUI

struct WatchDashboardView: View {
    private static let quickStartTaskLimit = 4

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
        let inactiveTasks = inactiveRecentTasks
        let quickStartTasks = Array(inactiveTasks.prefix(Self.quickStartTaskLimit))

        NavigationStack {
            List {
                if !hasReceivedSnapshot, let status {
                    Section {
                        WatchStatusRow(status: status, snapshotDate: snapshot.generatedAt)
                    }
                }

                if !failedCommands.isEmpty {
                    Section {
                        ForEach(failedCommands) { failure in
                            WatchCommandFailureRow(
                                title: failureTitle(for: failure),
                                result: failure.result,
                                onRetry: { onRetryCommand(failure.id) },
                                onDiscard: { onDiscardCommand(failure.id) }
                            )
                        }
                    } header: {
                        Text("watch.commandFailures.title")
                    } footer: {
                        Text("watch.commandFailures.footer")
                    }
                }

                if hasReceivedSnapshot {
                    if !snapshot.activeTimers.isEmpty {
                        Section("watch.active.title") {
                            ForEach(snapshot.activeTimers) { timer in
                                let failedCommand = failedStopCommand(for: timer.id)
                                WatchActiveTimerRow(
                                    timer: timer,
                                    commandState: rowState(
                                        isPending: isStopPending(for: timer.id),
                                        hasFailed: failedCommand != nil
                                    ),
                                    action: {
                                        if let failedCommand {
                                            onRetryCommand(failedCommand.id)
                                        } else {
                                            onStopTimer(timer.id)
                                        }
                                    }
                                )
                            }
                        }
                    }

                    if !inactiveTasks.isEmpty {
                        Section("watch.quickStart.title") {
                            ForEach(quickStartTasks) { task in
                                WatchTaskActionRow(
                                    task: task,
                                    pendingCommands: pendingCommands,
                                    failedCommands: failedCommands,
                                    onStartTask: onStartTask,
                                    onRetryCommand: onRetryCommand
                                )
                            }

                            if inactiveTasks.count > quickStartTasks.count {
                                NavigationLink {
                                    WatchTaskListView(
                                        tasks: inactiveTasks,
                                        pendingCommands: pendingCommands,
                                        failedCommands: failedCommands,
                                        onStartTask: onStartTask,
                                        onRetryCommand: onRetryCommand
                                    )
                                } label: {
                                    Label("watch.tasks.all", systemImage: "list.bullet")
                                        .frame(
                                            maxWidth: .infinity,
                                            minHeight: 44,
                                            alignment: .leading
                                        )
                                }
                                .accessibilityHint(Text("watch.tasks.allHint"))
                            }
                        }
                    }

                    if snapshot.activeTimers.isEmpty && inactiveTasks.isEmpty {
                        Section {
                            WatchEmptyState(
                                title: String(localized: "watch.empty.title"),
                                message: String(localized: "watch.empty.message"),
                                systemImage: "timer"
                            )
                        }
                    }

                    if let status {
                        Section {
                            WatchStatusRow(status: status, snapshotDate: snapshot.generatedAt)
                        }
                    }
                }
            }
            .navigationTitle("watch.title")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var inactiveRecentTasks: [WatchRecentTaskSnapshot] {
        let activeTaskIDs = Set(snapshot.activeTimers.map(\.taskID))
        return snapshot.recentTasks.filter { !activeTaskIDs.contains($0.taskID) }
    }

    private var status: WatchSyncStatus? {
        if !hasReceivedSnapshot {
            return hasConnectivityError ? .connectionError : .waitingForFirstSnapshot
        }
        if !pendingCommands.isEmpty {
            return isReachable && !hasConnectivityError ? .sending : .queued
        }
        if hasConnectivityError { return .connectionError }
        if isSnapshotStale { return .stale }
        return nil
    }

    private func isStopPending(for segmentID: UUID) -> Bool {
        pendingCommands.contains { $0.type == .stopSegment && $0.segmentID == segmentID }
    }

    private func failedStopCommand(for segmentID: UUID) -> WatchFailedCommand? {
        failedCommands.first { $0.command.type == .stopSegment && $0.command.segmentID == segmentID }
    }

    private func rowState(isPending: Bool, hasFailed: Bool) -> WatchRowCommandState {
        if isPending { return .pending }
        if hasFailed { return .failed }
        return .idle
    }

    private func failureTitle(for failure: WatchFailedCommand) -> String {
        switch failure.command.type {
        case .startTask:
            return snapshot.recentTasks.first { $0.taskID == failure.command.taskID }?.title
                ?? String(localized: "watch.command.startFallback")
        case .stopSegment:
            return snapshot.activeTimers.first { $0.id == failure.command.segmentID }?.title
                ?? String(localized: "watch.command.stopFallback")
        }
    }
}
