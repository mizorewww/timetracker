import Foundation
import OSLog

private enum SyncConflictPromptRefreshDiagnostics {
    static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "SyncConflictPromptRefresh"
    )
}

extension TimeTrackerStore {
    func scheduleSyncConflictPromptRefresh() {
        syncConflictPromptRefreshRequestID = UUID()
        isSyncConflictPromptRefreshRequested = true
        startSyncConflictPromptRefreshIfNeeded()
    }

    private func startSyncConflictPromptRefreshIfNeeded() {
        guard syncConflictPromptRefreshTask == nil,
              isSyncConflictPromptRefreshRequested
        else {
            return
        }
        syncConflictPromptRefreshTask = Task {
            await runSyncConflictPromptRefreshLoop()
        }
    }

    private func runSyncConflictPromptRefreshLoop() async {
        defer {
            syncConflictPromptRefreshTask = nil
            startSyncConflictPromptRefreshIfNeeded()
        }

        while Task.isCancelled == false,
              isSyncConflictPromptRefreshRequested
        {
            isSyncConflictPromptRefreshRequested = false
            let requestID = syncConflictPromptRefreshRequestID
            switch await loadSyncConflictPrompt(
                requestID: requestID
            ) {
            case let .success(prompt):
                guard Task.isCancelled == false,
                      syncConflictPromptRefreshRequestID == requestID
                else {
                    continue
                }
                pendingSyncConflict = prompt
            case .cancelled:
                return
            case let .failure(error):
                SyncConflictPromptRefreshDiagnostics.logger.error(
                    "Could not refresh the sync-conflict prompt: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func loadSyncConflictPrompt(
        requestID: UUID
    ) async -> SyncConflictPromptLoadOutcome {
        let retryDelays: [Duration] = [
            .milliseconds(100),
            .milliseconds(300),
        ]
        var lastError: (any Error)?

        for attempt in 0 ... retryDelays.count {
            guard Task.isCancelled == false,
                  syncConflictPromptRefreshRequestID == requestID
            else {
                return .cancelled
            }
            do {
                return try await .success(
                    syncConflictPromptLoader()
                )
            } catch is CancellationError {
                return .cancelled
            } catch {
                lastError = error
                guard attempt < retryDelays.count else {
                    break
                }
                do {
                    try await Task.sleep(
                        for: retryDelays[attempt]
                    )
                } catch {
                    return .cancelled
                }
            }
        }

        return .failure(
            lastError ?? SyncConflictPromptRefreshError.loadFailed
        )
    }

    private enum SyncConflictPromptRefreshError:
        Error
    {
        case loadFailed
    }

    private enum SyncConflictPromptLoadOutcome {
        case success(SyncConflictPrompt?)
        case failure(any Error)
        case cancelled
    }

    /// Applies an authoritative MainActor transition and invalidates any
    /// sidecar read that started before it.
    func replacePendingSyncConflict(
        _ prompt: SyncConflictPrompt?
    ) {
        syncConflictPromptRefreshRequestID = UUID()
        isSyncConflictPromptRefreshRequested = false
        syncConflictPromptRefreshTask?.cancel()
        pendingSyncConflict = prompt
    }

    func waitForSyncConflictPromptRefresh() async {
        while let task = syncConflictPromptRefreshTask {
            await task.value
            await Task.yield()
        }
    }
}
