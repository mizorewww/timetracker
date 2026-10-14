import Foundation
import SwiftData

@MainActor
struct WatchCommandMutationOutcome {
    let result: WatchCommandProcessingResult
    let events: Set<StoreDomainEvent>
}

@MainActor
struct WatchCommandProcessor {
    let writeAuthorization: StoreWriteAuthorization

    init(writeAuthorization: StoreWriteAuthorization = .applicationState) {
        self.writeAuthorization = writeAuthorization
    }

    func processWithMutationOutcome(
        _ command: WatchTimerCommand,
        context: ModelContext,
        now: Date = Date()
    ) throws -> WatchCommandMutationOutcome {
        guard command.isValid(at: now) else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }

        switch command.type {
        case .startTask:
            return try startTask(command, context: context)
        case .stopSegment:
            return try stopSegment(command, context: context)
        }
    }

    private func startTask(
        _ command: WatchTimerCommand,
        context: ModelContext
    ) throws -> WatchCommandMutationOutcome {
        guard let taskID = command.taskID else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }
        let outcome: StoreScopedTimerCommandOutcome
        do {
            outcome = try SystemActionCommandHandler(
                writeAuthorization: writeAuthorization
            ).startTimerMutation(
                taskID: taskID,
                source: .watch,
                container: context.container
            )
        } catch SystemActionCommandError.taskNotFound {
            return WatchCommandMutationOutcome(
                result: .missingTask(taskID),
                events: []
            )
        }
        guard let segmentID = outcome.subjectSegmentID else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }
        return WatchCommandMutationOutcome(
            result: .started(segmentID),
            events: outcome.events
        )
    }

    private func stopSegment(
        _ command: WatchTimerCommand,
        context: ModelContext
    ) throws -> WatchCommandMutationOutcome {
        guard let segmentID = command.segmentID else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }
        let outcome = try SystemActionCommandHandler(
            writeAuthorization: writeAuthorization
        ).stopTimerMutation(
            segmentID: segmentID,
            container: context.container
        )
        guard outcome.subjectSegmentID == segmentID else {
            return WatchCommandMutationOutcome(
                result: .missingSegment(segmentID),
                events: []
            )
        }
        return WatchCommandMutationOutcome(
            result: .stopped(segmentID),
            events: outcome.events
        )
    }
}
