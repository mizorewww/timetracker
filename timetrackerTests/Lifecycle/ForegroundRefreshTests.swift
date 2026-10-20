import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
struct ForegroundRefreshTests {
    @Test
    func returningToTheForegroundShowsAnotherProcessesWrite() async throws {
        let container = try makeHistoryBackedContainer()
        let store = makeTestStore()
        try store.configureIfNeeded(context: ModelContext(container))

        let widgetContext = ModelContext(container)
        widgetContext.author = "me.mezorewww.timetracker.local-mutation.v1.widget-process"
        widgetContext.insert(
            CountdownEvent(title: "Launch", date: Date().addingTimeInterval(86400), deviceID: "widget")
        )
        try widgetContext.save()

        await store.refreshForForeground()

        #expect(store.countdownEvents.map(\.title) == ["Launch"])
    }

    /// Persistent history needs a store on disk.
    private func makeHistoryBackedContainer() throws -> ModelContainer {
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = try ModelConfiguration(
            "ForegroundRefreshTests-\(UUID().uuidString)",
            schema: schema,
            url: makeStoreDirectory().appending(path: "foreground.store"),
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
