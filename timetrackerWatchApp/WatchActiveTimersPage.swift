import SwiftUI

struct WatchActiveTimersPage: View {
    private static let failurePreviewLimit = 1

    let timers: [WatchActiveTimerSnapshot]
    let snapshotFreshness: WatchSnapshotFreshness
    let generatedAt: Date
    let hasReceivedSnapshot: Bool
    let status: WatchSyncStatus?
    let failures: [WatchCommandFailurePresentation]
    let commandIndex: WatchCommandPresentationIndex
    let onStopTimer: (UUID) -> Void
    let onRetryCommand: (UUID) -> Void
    let onDiscardCommand: (UUID) -> Void

    var body: some View {
        List {
            failureSection

            if let status {
                Section {
                    WatchStatusRow(status: status, snapshotDate: generatedAt)
                }
            }

            if hasReceivedSnapshot {
                timerSection
            }
        }
    }

    @ViewBuilder
    private var failureSection: some View {
        if !failures.isEmpty {
            let preview = Array(failures.prefix(Self.failurePreviewLimit))
            Section {
                ForEach(preview) { failure in
                    WatchCommandFailureActionRow(
                        failure: failure,
                        onRetryCommand: onRetryCommand,
                        onDiscardCommand: onDiscardCommand
                    )
                }

                if failures.count > preview.count {
                    NavigationLink {
                        WatchCommandFailuresView(
                            failures: failures,
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
                            Text(failures.count, format: .number)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.vertical, 4)
                    }
                    .accessibilityHint(Text("watch.commandFailures.allHint"))
                }
            } header: {
                Text("watch.commandFailures.title")
            } footer: {
                Text("watch.commandFailures.footer")
            }
        }
    }

    @ViewBuilder
    private var timerSection: some View {
        if timers.isEmpty {
            Section {
                WatchEmptyState(
                    title: String(localized: "watch.active.empty.title"),
                    message: String(localized: "watch.active.empty.message"),
                    systemImage: "timer"
                )
            }
        } else {
            Section {
                ForEach(timers) { timer in
                    let command = commandIndex.stopTimer(timer.id)
                    WatchActiveTimerRow(
                        timer: timer,
                        snapshotFreshness: snapshotFreshness,
                        generatedAt: generatedAt,
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
    }
}
