import Foundation

nonisolated struct TaskDraftRecoveryPersistenceTicket: Sendable {
    fileprivate let draft: TaskEditorDraft
    fileprivate let sourceTaskID: UUID
    fileprivate let hasUnsavedChanges: Bool
    fileprivate let revision: UUID
}

nonisolated enum TaskDraftRecoveryControllerError: Error, Equatable, Sendable {
    case removalSuperseded
}

nonisolated final class TaskDraftRecoveryController: @unchecked Sendable {
    private let store: TaskDraftRecoveryStore
    private let gate: TaskDraftRecoveryOperationGate
    private let worker: TaskDraftRecoveryWorker

    init(store: TaskDraftRecoveryStore = TaskDraftRecoveryStore()) {
        self.store = store
        let gate = TaskDraftRecoveryOperationGate()
        self.gate = gate
        worker = TaskDraftRecoveryWorker(store: store, gate: gate)
    }

    func load(
        for sourceTaskID: UUID,
        currentDraft: TaskEditorDraft
    ) async throws -> TaskEditorDraft? {
        try await worker.load(
            for: sourceTaskID,
            currentDraft: currentDraft
        )
    }

    func recoverableRecords() async throws -> [TaskDraftRecoveryRecord] {
        try await worker.recoverableRecords()
    }

    func makePersistenceTicket(
        _ draft: TaskEditorDraft,
        for sourceTaskID: UUID,
        hasUnsavedChanges: Bool
    ) -> TaskDraftRecoveryPersistenceTicket? {
        guard draft.taskID == sourceTaskID else { return nil }
        let revision = gate.issueRevision(for: sourceTaskID)
        return TaskDraftRecoveryPersistenceTicket(
            draft: draft,
            sourceTaskID: sourceTaskID,
            hasUnsavedChanges: hasUnsavedChanges,
            revision: revision
        )
    }

    func persist(_ ticket: TaskDraftRecoveryPersistenceTicket) async {
        await worker.persist(ticket)
    }

    func removeExpired() async {
        await worker.removeExpired()
    }

    func invalidatePendingPersistence(for sourceTaskID: UUID) {
        let revision = gate.issueRevision(for: sourceTaskID)
        gate.performIfCurrent(
            sourceTaskID: sourceTaskID,
            revision: revision
        ) {}
    }

    func flush(
        _ draft: TaskEditorDraft,
        for sourceTaskID: UUID,
        hasUnsavedChanges: Bool
    ) {
        guard draft.taskID == sourceTaskID else { return }
        let revision = gate.issueRevision(for: sourceTaskID)
        gate.performIfCurrent(
            sourceTaskID: sourceTaskID,
            revision: revision
        ) {
            if hasUnsavedChanges {
                try? store.save(draft, for: sourceTaskID)
            } else {
                try? store.remove(for: sourceTaskID)
            }
        }
    }

    func remove(for sourceTaskID: UUID) throws {
        let revision = gate.issueRevision(for: sourceTaskID)
        let didRemove = try gate.performIfCurrent(
            sourceTaskID: sourceTaskID,
            revision: revision
        ) {
            try store.remove(for: sourceTaskID)
        }
        guard didRemove else {
            throw TaskDraftRecoveryControllerError.removalSuperseded
        }
    }

    func removeInBackground(for sourceTaskID: UUID) async throws {
        let revision = gate.issueRevision(for: sourceTaskID)
        let didRemove = try await worker.remove(
            for: sourceTaskID,
            revision: revision
        )
        guard didRemove else {
            throw TaskDraftRecoveryControllerError.removalSuperseded
        }
    }
}

private actor TaskDraftRecoveryWorker {
    let store: TaskDraftRecoveryStore
    let gate: TaskDraftRecoveryOperationGate

    init(
        store: TaskDraftRecoveryStore,
        gate: TaskDraftRecoveryOperationGate
    ) {
        self.store = store
        self.gate = gate
    }

    func load(
        for sourceTaskID: UUID,
        currentDraft: TaskEditorDraft
    ) throws -> TaskEditorDraft? {
        try Task.checkCancellation()
        return try gate.perform {
            try store.load(
                for: sourceTaskID,
                currentDraft: currentDraft
            )
        }
    }

    func recoverableRecords() throws -> [TaskDraftRecoveryRecord] {
        try Task.checkCancellation()
        return try gate.perform {
            try store.recoverableRecords()
        }
    }

    func remove(
        for sourceTaskID: UUID,
        revision: UUID
    ) throws -> Bool {
        try gate.performIfCurrent(
            sourceTaskID: sourceTaskID,
            revision: revision
        ) {
            try store.remove(for: sourceTaskID)
        }
    }

    func persist(
        _ ticket: TaskDraftRecoveryPersistenceTicket
    ) {
        guard ticket.draft.taskID == ticket.sourceTaskID else { return }
        gate.performIfCurrent(
            sourceTaskID: ticket.sourceTaskID,
            revision: ticket.revision
        ) {
            if ticket.hasUnsavedChanges {
                try? store.save(
                    ticket.draft,
                    for: ticket.sourceTaskID
                )
            } else {
                try? store.remove(for: ticket.sourceTaskID)
            }
        }
    }

    func removeExpired() {
        guard Task.isCancelled == false else { return }
        gate.perform {
            _ = try? store.removeExpired()
        }
    }
}

nonisolated final class TaskDraftRecoveryOperationGate:
    @unchecked Sendable {
    private let revisionLock = NSLock()
    private let operationLock = NSLock()
    private var revisionsByTaskID: [UUID: UUID] = [:]

    func issueRevision(for sourceTaskID: UUID) -> UUID {
        revisionLock.withLock {
            let revision = UUID()
            revisionsByTaskID[sourceTaskID] = revision
            return revision
        }
    }

    @discardableResult
    func performIfCurrent(
        sourceTaskID: UUID,
        revision: UUID,
        operation: () throws -> Void
    ) rethrows -> Bool {
        try operationLock.withLock {
            let isCurrent = revisionLock.withLock {
                revisionsByTaskID[sourceTaskID] == revision
            }
            guard isCurrent else { return false }
            try operation()
            return revisionLock.withLock {
                revisionsByTaskID[sourceTaskID] == revision
            }
        }
    }

    func perform<Result>(
        operation: () throws -> Result
    ) rethrows -> Result {
        try operationLock.withLock {
            try operation()
        }
    }
}
