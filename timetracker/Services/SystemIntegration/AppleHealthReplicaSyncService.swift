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
    private var latestRequestID = UUID()

    init(
        reader: any AppleHealthReplicaChangeReading,
        repository: any AppleHealthReplicaRepository
    ) {
        self.reader = reader
        self.repository = repository
    }

    func synchronize(
        at syncedAt: Date = Date()
    ) async throws -> AppleHealthReplicaSnapshot {
        let requestID = UUID()
        latestRequestID = requestID
        let anchors = try repository.anchors()
        let changes = try await reader.replicaChanges(after: anchors)
        try Task.checkCancellation()
        guard latestRequestID == requestID else {
            throw CancellationError()
        }
        try repository.apply(changes, syncedAt: syncedAt)
        return try repository.allSamples()
    }
}
