import Foundation

@MainActor
protocol AppleHealthReplicaChangeReading: AnyObject {
    func replicaChanges(
        after anchors: AppleHealthReplicaAnchors
    ) async throws -> AppleHealthReplicaChangeBatch
}

@MainActor
final class AppleHealthReplicaSyncService {
    private let reader: any AppleHealthReplicaChangeReading
    private let repository: any AppleHealthReplicaRepository
    private var requestedGeneration = 1
    private var synchronizedGeneration = 0
    private var inFlightSynchronization: InFlightSynchronization?
    private var waiterIDsBySynchronizationID: [UUID: Set<UUID>] = [:]

    init(
        reader: any AppleHealthReplicaChangeReading,
        repository: any AppleHealthReplicaRepository
    ) {
        self.reader = reader
        self.repository = repository
    }

    func markNeedsSynchronization() {
        requestedGeneration &+= 1
    }

    func synchronize(
        at syncedAt: Date = Date()
    ) async throws -> AppleHealthReplicaSnapshot {
        markNeedsSynchronization()
        _ = try await synchronizeIfNeeded(at: syncedAt)
        return try repository.allSamples()
    }

    func synchronizeIfNeeded(
        at syncedAt: Date = Date()
    ) async throws -> Int {
        while synchronizedGeneration < requestedGeneration {
            try Task.checkCancellation()
            let synchronization = inFlightSynchronization
                ?? beginSynchronization(
                    generation: requestedGeneration,
                    syncedAt: syncedAt
                )
            let waiterID = registerWaiter(for: synchronization.id)
            defer {
                releaseWaiter(
                    waiterID,
                    for: synchronization.id,
                    cancelsFlightWhenLast: false
                )
            }
            do {
                try await withTaskCancellationHandler {
                    try await synchronization.task.value
                } onCancel: {
                    Task { @MainActor [weak self] in
                        self?.releaseWaiter(
                            waiterID,
                            for: synchronization.id,
                            cancelsFlightWhenLast: true
                        )
                    }
                }
                finishSynchronization(
                    synchronization,
                    succeeded: true
                )
                try Task.checkCancellation()
            } catch {
                finishSynchronization(
                    synchronization,
                    succeeded: false
                )
                throw error
            }
        }
        return synchronizedGeneration
    }

    private func beginSynchronization(
        generation: Int,
        syncedAt: Date
    ) -> InFlightSynchronization {
        let reader = reader
        let repository = repository
        let synchronization = InFlightSynchronization(
            id: UUID(),
            generation: generation,
            task: Task { @MainActor in
                let anchors = try repository.anchors()
                let changes = try await reader.replicaChanges(
                    after: anchors
                )
                try Task.checkCancellation()
                try repository.apply(changes, syncedAt: syncedAt)
            }
        )
        inFlightSynchronization = synchronization
        return synchronization
    }

    private func registerWaiter(for synchronizationID: UUID) -> UUID {
        let waiterID = UUID()
        waiterIDsBySynchronizationID[
            synchronizationID,
            default: []
        ].insert(waiterID)
        return waiterID
    }

    private func releaseWaiter(
        _ waiterID: UUID,
        for synchronizationID: UUID,
        cancelsFlightWhenLast: Bool
    ) {
        guard waiterIDsBySynchronizationID[
            synchronizationID
        ]?.remove(waiterID) != nil else {
            return
        }
        guard waiterIDsBySynchronizationID[
            synchronizationID
        ]?.isEmpty == true else {
            return
        }
        waiterIDsBySynchronizationID[synchronizationID] = nil
        if cancelsFlightWhenLast,
           inFlightSynchronization?.id == synchronizationID
        {
            inFlightSynchronization?.task.cancel()
        }
    }

    private func finishSynchronization(
        _ synchronization: InFlightSynchronization,
        succeeded: Bool
    ) {
        guard inFlightSynchronization?.id == synchronization.id else {
            return
        }
        inFlightSynchronization = nil
        if succeeded {
            synchronizedGeneration = max(
                synchronizedGeneration,
                synchronization.generation
            )
        }
    }
}

private extension AppleHealthReplicaSyncService {
    struct InFlightSynchronization {
        let id: UUID
        let generation: Int
        let task: Task<Void, Error>
    }
}
