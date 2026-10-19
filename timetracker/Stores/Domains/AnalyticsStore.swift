import Foundation

nonisolated struct AnalyticsStore {
    static let maximumTaskSnapshotCount = 24

    struct TaskSnapshotCacheKey: Hashable {
        let taskID: UUID
        let range: AnalyticsRange
        let evaluationKey: AnalyticsEvaluationCacheKey
    }

    var snapshots: [AnalyticsRange: AnalyticsSnapshot] = [:]
    var snapshotEvaluationKeys: [AnalyticsRange: AnalyticsEvaluationCacheKey] = [:]
    var taskSnapshots: [TaskSnapshotCacheKey: TaskAnalyticsSnapshot] = [:]
    /// Insertion order of `taskSnapshots`, oldest first, for eviction.
    var taskSnapshotOrder: [TaskSnapshotCacheKey] = []

    mutating func storeSnapshot(
        _ snapshot: AnalyticsSnapshot,
        evaluationKey: AnalyticsEvaluationCacheKey
    ) {
        snapshots[snapshot.range] = snapshot
        snapshotEvaluationKeys[snapshot.range] = evaluationKey
    }
}
