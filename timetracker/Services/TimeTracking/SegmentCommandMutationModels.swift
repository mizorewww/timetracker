import Foundation

enum SegmentMutationError: LocalizedError, Equatable {
    case staleDraft
    case inconsistentSession
    case activeTimerStartInFuture

    var errorDescription: String? {
        switch self {
        case .staleDraft:
            AppStrings.localized("segment.editor.staleDraft")
        case .inconsistentSession:
            AppStrings.localized("segment.editor.inconsistentSession")
        case .activeTimerStartInFuture:
            AppStrings.localized("segment.error.startNotFuture")
        }
    }
}

struct LedgerSegmentMutationSnapshot: Hashable {
    let segmentID: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let deletedAt: Date?

    init(segment: TimeSegment) {
        segmentID = segment.id
        sessionID = segment.sessionID
        taskID = segment.taskID
        startedAt = segment.startedAt
        endedAt = segment.endedAt
        deletedAt = segment.deletedAt
    }

    var isActive: Bool {
        endedAt == nil && deletedAt == nil
    }
}

struct LedgerSegmentMutationChange: Hashable {
    let before: LedgerSegmentMutationSnapshot
    let after: LedgerSegmentMutationSnapshot?
}

struct SegmentPomodoroMutationSnapshot: Hashable {
    let runID: UUID
    let sessionID: UUID?
    let taskID: UUID
    let stateRaw: String
    let mutationID: UUID
    let endedAt: Date?
    let deletedAt: Date?

    init(run: PomodoroRun) {
        runID = run.id
        sessionID = run.sessionID
        taskID = run.taskID
        stateRaw = run.stateRaw
        mutationID = run.clientMutationID
        endedAt = run.endedAt
        deletedAt = run.deletedAt
    }
}

struct SegmentPomodoroMutationChange: Hashable {
    let before: SegmentPomodoroMutationSnapshot
    let after: SegmentPomodoroMutationSnapshot?
}

struct StoreScopedSegmentMutationOutcome: Equatable {
    let subjectSegmentID: UUID
    let segmentChanges: [LedgerSegmentMutationChange]
    let pomodoroChanges: [SegmentPomodoroMutationChange]
    let referenceDate: Date

    var referencedTaskIDs: Set<UUID> {
        var taskIDs = Set<UUID>()
        for change in segmentChanges {
            taskIDs.insert(change.before.taskID)
            if let after = change.after {
                taskIDs.insert(after.taskID)
            }
        }
        for change in pomodoroChanges {
            taskIDs.insert(change.before.taskID)
            if let after = change.after {
                taskIDs.insert(after.taskID)
            }
        }
        return taskIDs
    }

    var events: Set<StoreDomainEvent> {
        var events = Set<StoreDomainEvent>()
        for change in segmentChanges {
            events.insert(ledgerEvent(for: change.before))
            if let after = change.after {
                events.insert(ledgerEvent(for: after))
            }
        }
        for change in pomodoroChanges {
            events.insert(pomodoroEvent(for: change.before))
            if let after = change.after {
                events.insert(pomodoroEvent(for: after))
            }
        }
        return events
    }

    private func ledgerEvent(
        for snapshot: LedgerSegmentMutationSnapshot
    ) -> StoreDomainEvent {
        let end = max(
            snapshot.startedAt,
            TrackedTimePolicy.boundedEnd(
                endedAt: snapshot.endedAt,
                now: referenceDate
            )
        )
        return .ledgerChanged(
            taskID: snapshot.taskID,
            dateInterval: StoreInvalidationRange(
                start: snapshot.startedAt,
                end: end
            ),
            isVisible: snapshot.isActive
        )
    }

    private func pomodoroEvent(
        for snapshot: SegmentPomodoroMutationSnapshot
    ) -> StoreDomainEvent {
        .pomodoroChanged(
            runID: snapshot.runID,
            sessionID: snapshot.sessionID,
            taskID: snapshot.taskID
        )
    }
}
