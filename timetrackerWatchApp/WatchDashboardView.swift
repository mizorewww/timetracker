import SwiftUI

struct WatchDashboardView: View {
    private static let quickStartTaskLimit = 4
    private static let failurePreviewLimit = 1

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
        let commandIndex = WatchCommandPresentationIndex(
            pendingCommands: pendingCommands,
            failedCommands: failedCommands
        )
        let failureItems = failedCommands.map {
            WatchCommandFailurePresentation(failure: $0, title: failureTitle(for: $0))
        }
        let failurePreview = Array(failureItems.prefix(Self.failurePreviewLimit))

        NavigationStack {
            List {
                if !hasReceivedSnapshot, let status {
                    Section {
                        WatchStatusRow(status: status, snapshotDate: snapshot.generatedAt)
                    }
                }

                if !failureItems.isEmpty {
                    Section {
                        ForEach(failurePreview) { failure in
                            WatchCommandFailureActionRow(
                                failure: failure,
                                onRetryCommand: onRetryCommand,
                                onDiscardCommand: onDiscardCommand
                            )
                        }

                        if failureItems.count > failurePreview.count {
                            NavigationLink {
                                WatchCommandFailuresView(
                                    failures: failureItems,
                                    onRetryCommand: onRetryCommand,
                                    onDiscardCommand: onDiscardCommand
                                )
                            } label: {
                                HStack {
                                    Label(
                                        "watch.commandFailures.all",
                                        systemImage: "exclamationmark.bubble"
                                    )
                                    Spacer(minLength: 4)
                                    Text(failureItems.count, format: .number)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .accessibilityHint(Text("watch.commandFailures.allHint"))
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
                                let command = commandIndex.stopTimer(timer.id)
                                WatchActiveTimerRow(
                                    timer: timer,
                                    commandState: command.state,
                                    action: {
                                        if let retryCommandID = command.retryCommandID {
                                            onRetryCommand(retryCommandID)
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
                                let command = commandIndex.startTask(task.taskID)
                                WatchTaskActionRow(
                                    task: task,
                                    command: command,
                                    onStartTask: onStartTask,
                                    onRetryCommand: onRetryCommand
                                )
                            }

                            if inactiveTasks.count > quickStartTasks.count {
                                NavigationLink {
                                    WatchTaskListView(
                                        tasks: inactiveTasks,
                                        commandIndex: commandIndex,
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
                                title: String(localized: "watch.tasks.empty.title"),
                                message: String(localized: "watch.tasks.empty.message"),
                                systemImage: "list.bullet"
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
