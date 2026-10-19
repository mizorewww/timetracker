import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
struct RemoteChangeHistoryCursorTests {
    @Test
    func catchUpRefreshesOnlyScopesOfModelsChangedSinceThePreviousCall() throws {
        let container = try makeFileBackedContainer()
        let readerContext = ModelContext(container)
        let cursor = RemoteChangeHistoryCursor(baselineDate: Date())

        let writerContext = ModelContext(container)
        writerContext.insert(CountdownEvent(title: "Launch", date: Date(), deviceID: "remote"))
        try writerContext.save()
        #expect(cursor.scopesSinceLastCatchUp(in: readerContext) == [.countdown])

        #expect(cursor.scopesSinceLastCatchUp(in: readerContext).isEmpty)

        writerContext.insert(SyncedPreference(key: "Example", valueJSON: "1", deviceID: "remote"))
        try writerContext.save()
        #expect(cursor.scopesSinceLastCatchUp(in: readerContext) == [.preferences])
    }

    @Test
    func catchUpSkipsThisProcessesStoreMutationsButNotOtherWriters() throws {
        let container = try makeFileBackedContainer()
        let readerContext = ModelContext(container)
        let cursor = RemoteChangeHistoryCursor(baselineDate: Date())

        let localContext = ModelContext(container)
        try localContext.performAtomicMutation(author: .localMutation) {
            localContext.insert(CountdownEvent(title: "Local", date: Date(), deviceID: "local"))
        }
        #expect(cursor.scopesSinceLastCatchUp(in: readerContext).isEmpty)

        let otherProcessContext = ModelContext(container)
        otherProcessContext.author = "me.mezorewww.timetracker.local-mutation.v1.other-process"
        otherProcessContext.insert(SyncedPreference(key: "Example", valueJSON: "1", deviceID: "widget"))
        try otherProcessContext.save()
        #expect(cursor.scopesSinceLastCatchUp(in: readerContext) == [.preferences])
    }

    @Test
    func everyCurrentModelMapsToANarrowerScopeThanFullRefresh() {
        for model in TimeTrackerModelRegistry.currentModels {
            let scopes = RemoteChangeHistoryCursor.scopes(
                forChangedEntityNames: [RemoteChangeHistoryCursor.entityName(of: model)]
            )
            #expect(scopes.isEmpty == false)
            #expect(scopes != StoreRefreshScope.full, "\(model) has no remote refresh mapping")
        }
    }

    @Test
    func unknownEntityFallsBackToFullRefresh() {
        #expect(
            RemoteChangeHistoryCursor.scopes(forChangedEntityNames: ["RetiredModel"])
                == StoreRefreshScope.full
        )
    }

    private func makeFileBackedContainer() throws -> ModelContainer {
        // SwiftData may close SQLite sidecars asynchronously; the sandbox temp
        // directory is left to operating-system cleanup.
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "RemoteChangeHistoryCursorTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "RemoteChangeHistoryCursorTests-\(UUID().uuidString)",
            schema: schema,
            url: directory.appending(path: "history.store"),
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
