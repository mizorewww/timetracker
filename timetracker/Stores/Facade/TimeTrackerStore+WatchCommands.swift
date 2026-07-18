import Foundation

extension TimeTrackerStore {
    @discardableResult
    func handleWatchCommand(_ command: WatchTimerCommand) -> WatchCommandResult {
        handleWatchCommand(command, recordingWith: syncConflictService)
    }

    @discardableResult
    func handleWatchCommand(
        _ command: WatchTimerCommand,
        recordingWith snapshotService: SyncConflictService
    ) -> WatchCommandResult {
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            let outcome = try WatchCommandProcessor(
                writeAuthorization: writeAuthorization
            ).processWithMutationOutcome(
                command,
                context: modelContext
            )
            let result = outcome.result
            let terminalResult = result.terminalResult(commandID: command.id)

            if result.isProcessed {
                var postCommitError: Error?
                do {
                    if outcome.events.isEmpty {
                        refreshStoreScopedTimerReadModels()
                    } else if let surfaceError = try refreshCommittedMutationSurfaces(
                        events: outcome.events
                    ) {
                        postCommitError = surfaceError
                    }
                } catch {
                    postCommitError = error
                }
                if outcome.events.isEmpty == false {
                    do {
                        let snapshotResult = try snapshotService.recordLocalMutation(
                            context: modelContext,
                            events: outcome.events
                        )
                        switch snapshotResult {
                        case let .recorded(prompt):
                            pendingSyncConflict = prompt
                        case .notRecorded:
                            pendingSyncConflict = try snapshotService.prompt()
                        }
                    } catch {
                        postCommitError = postCommitError ?? error
                    }
                }

                if let postCommitError {
                    errorMessage = String(
                        format: AppStrings.localized("error.savedRefreshFailed"),
                        postCommitError.localizedDescription
                    )
                }
            } else {
                switch result {
                case .duplicate, .missingTask:
                    refreshStoreScopedTimerReadModels(includingTasks: true)
                case .missingSegment:
                    refreshStoreScopedTimerReadModels()
                case .invalid:
                    break
                case .started, .stopped:
                    break
                }
            }

            // Always publish after a terminal outcome. This also covers duplicate,
            // missing, and invalid commands whose watch may hold a stale snapshot.
            syncWatchSnapshotIfAvailable()
            return terminalResult
        } catch {
            errorMessage = error.localizedDescription
            // A failed command still receives a terminal result and a best-effort
            // state refresh, allowing the watch row to unlock immediately.
            syncWatchSnapshotIfAvailable()
            return .failed(commandID: command.id)
        }
    }
}
