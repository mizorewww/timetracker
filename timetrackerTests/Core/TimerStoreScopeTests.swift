import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TimerStoreScopeTests {
    @Test
    func persistentContainerUsesItsConfiguredStoreURL() throws {
        let fixture = try PersistentStoreFixture()
        defer { fixture.remove() }
        let configuredURL = fixture.root.appendingPathComponent("timer.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "TimerStoreScopePersistent",
            schema: schema,
            url: configuredURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )

        let scope = try TimerStoreScope(container: container)

        #expect(scope.persistentStoreURL == configuredURL.standardizedFileURL)
        #expect(
            scope.mutationLockURL
                == configuredURL.deletingLastPathComponent().appendingPathComponent(
                    "timer.store.timer-mutations.lock"
                )
        )
    }

    @Test
    func inMemoryContainerRetainsOneScopeIdentityForItsLifetime() throws {
        let container = try makeInMemoryContainer(named: "Stable")

        let first = try TimerStoreScope(container: container)
        let second = try TimerStoreScope(container: container)

        #expect(first == second)
        #expect(first.persistentStoreURL == nil)
        #expect(first.mutationLockURL == second.mutationLockURL)
    }

    @Test
    func differentInMemoryContainersReceiveDifferentScopeIdentities() throws {
        let firstContainer = try makeInMemoryContainer(named: "First")
        let secondContainer = try makeInMemoryContainer(named: "Second")

        let first = try TimerStoreScope(container: firstContainer)
        let second = try TimerStoreScope(container: secondContainer)

        #expect(first != second)
        #expect(first.mutationLockURL != second.mutationLockURL)
    }

    @Test
    func multipleContainerConfigurationsAreRejectedAsAmbiguous() throws {
        let taskSchema = Schema([TaskNode.self])
        let segmentSchema = Schema([TimeSegment.self])
        let container = try ModelContainer(
            for: Schema([TaskNode.self, TimeSegment.self]),
            configurations: [
                ModelConfiguration(
                    "Tasks",
                    schema: taskSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                ),
                ModelConfiguration(
                    "Segments",
                    schema: segmentSchema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                ),
            ]
        )

        #expect(throws: TimerStoreScopeResolutionError.ambiguousConfigurations(2)) {
            try TimerStoreScope(container: container)
        }
    }

    private func makeInMemoryContainer(named name: String) throws -> ModelContainer {
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "TimerStoreScope\(name)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private struct PersistentStoreFixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TimeTrackerTimerStoreScopeTests-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
