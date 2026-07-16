import Foundation

nonisolated enum StoreScopedPomodoroPhaseRejection: Hashable, Sendable {
    case stalePhase
}

nonisolated struct PomodoroPhaseEndMutationSnapshot: Hashable, Sendable {
    let previousPhase: PomodoroPhaseToken
    let taskID: UUID
    let sessionIDBefore: UUID?
    let resultingStateRaw: String
    let resultingMutationID: UUID
    let discardedRecord: Bool

    var referencedTaskIDs: Set<UUID> {
        [taskID]
    }

    @MainActor
    var events: Set<StoreDomainEvent> {
        var events: Set<StoreDomainEvent> = [
            .pomodoroChanged(
                runID: previousPhase.runID,
                sessionID: sessionIDBefore,
                taskID: taskID
            ),
        ]
        if sessionIDBefore != nil {
            events.insert(
                .ledgerChanged(
                    taskID: taskID,
                    dateInterval: nil,
                    isVisible: true
                )
            )
        }
        return events
    }
}

nonisolated enum StoreScopedPomodoroPhaseMutationOutcome: Hashable, Sendable {
    case mutated(PomodoroPhaseEndMutationSnapshot)
    case rejected(StoreScopedPomodoroPhaseRejection)
}

nonisolated struct StoreScopedPomodoroReconcileOutcome: Hashable, Sendable {
    let mutations: [PomodoroPhaseEndMutationSnapshot]

    var didMutate: Bool {
        mutations.isEmpty == false
    }

    var referencedTaskIDs: Set<UUID> {
        Set(mutations.map(\.taskID))
    }

    @MainActor
    var events: Set<StoreDomainEvent> {
        mutations.reduce(into: Set<StoreDomainEvent>()) { events, mutation in
            events.formUnion(mutation.events)
        }
    }
}
