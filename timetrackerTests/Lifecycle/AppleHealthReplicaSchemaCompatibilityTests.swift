import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct AppleHealthReplicaSchemaCompatibilityTests {
    @Test @MainActor
    func v1StoreReopensWithCurrentSchemaAndRemainsWritable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "AppleHealthReplicaV1-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        // SwiftData may close SQLite sidecars asynchronously. Keep this unique
        // store in the sandbox temp directory for operating-system cleanup.
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let storeURL = directory.appending(path: "health-replica.store")
        let workoutID = UUID()

        try autoreleasepool {
            let container = try AppleHealthReplicaModelContainerFactory
                .makePersistentContainer(
                    at: storeURL,
                    name: "AppleHealthReplicaV1"
                )
            let repository = SwiftDataAppleHealthReplicaRepository(
                container: container
            )
            try repository.apply(
                AppleHealthReplicaChangeBatch(
                    workouts: [
                        appleHealthWorkout(
                            id: workoutID,
                            kind: .cycling,
                            start: 100,
                            end: 200
                        ),
                    ],
                    deletedWorkoutIDs: [],
                    workoutAnchor: Data("v1-workout".utf8),
                    sleep: [],
                    deletedSleepIDs: [],
                    sleepAnchor: Data("v1-sleep".utf8)
                ),
                syncedAt: Date(timeIntervalSince1970: 300)
            )
        }

        try autoreleasepool {
            let container = try AppleHealthReplicaModelContainerFactory
                .makePersistentContainer(
                    at: storeURL,
                    name: "AppleHealthReplicaV1"
                )
            let repository = SwiftDataAppleHealthReplicaRepository(
                container: container
            )
            let reopened = try repository.allSamples()
            #expect(reopened.samples.workouts.map(\.id) == [workoutID])
            #expect(reopened.samples.workouts.first?.kind == .cycling)
            #expect(try repository.anchors().workout == Data("v1-workout".utf8))

            try repository.apply(
                AppleHealthReplicaChangeBatch(
                    workouts: [
                        appleHealthWorkout(
                            id: UUID(),
                            kind: .running,
                            start: 400,
                            end: 500
                        ),
                    ],
                    deletedWorkoutIDs: [],
                    workoutAnchor: Data("v1-workout-2".utf8),
                    sleep: [],
                    deletedSleepIDs: [],
                    sleepAnchor: Data("v1-sleep-2".utf8)
                ),
                syncedAt: Date(timeIntervalSince1970: 600)
            )
            #expect(try repository.allSamples().recordCount == 2)
        }
    }
}
