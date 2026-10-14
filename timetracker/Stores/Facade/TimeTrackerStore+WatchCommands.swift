import Foundation

extension TimeTrackerStore {
    @discardableResult
    func handleWatchCommand(_ command: WatchTimerCommand) -> WatchCommandResult {
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

            if outcome.events.isEmpty == false {
                finishStoreScopedMutation(
                    events: outcome.events,
                    forcedSystemSinks: [.watch]
                )
            } else {
                if result.isProcessed {
                    refreshStoreScopedTimerReadModels()
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
                enqueueWatchCurrentStateProjection()
            }

            return terminalResult
        } catch {
            errorMessage = error.localizedDescription
            enqueueWatchCurrentStateProjection()
            return .failed(commandID: command.id)
        }
    }

    private func enqueueWatchCurrentStateProjection() {
        enqueueCommittedMutationSystemProjections(
            events: [],
            forcedSystemSinks: [.watch]
        )
    }
}
