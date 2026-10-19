import Foundation
import SwiftData
import Testing
@testable import timetracker

struct LegacySchemaMigrationTests {
    @Test @MainActor
    func versionEightStoreMigratesToCurrentSchemaWithoutTheLegacyDailySummaryCache() throws {
        let fixture = try LegacyV8DailySummaryStoreFixture.create()

        try fixture.withCurrentContext { context in
            let taskIDs = try context.fetch(FetchDescriptor<TaskNode>()).map(\.id)
            #expect(taskIDs == [fixture.taskID])
            #expect(TimeTrackerModelRegistry.currentSchema.entity(for: DailySummary.self) == nil)
        }
    }

    @Test @MainActor
    func versionNineStoreMigratesInboxSuggestionIdentityAndDismissalState() throws {
        let fixture = try LegacyV9InboxStoreFixture.create()

        try fixture.withCurrentContext { context in
            let items = try context.fetch(FetchDescriptor<InboxItem>())
            let suggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
            let dismissedItem = try #require(items.first { $0.id == fixture.dismissedItemID })
            let readyItem = try #require(items.first { $0.id == fixture.readyItemID })
            let suggestion = try #require(suggestions.first { $0.id == fixture.suggestionID })

            #expect(dismissedItem.suggestionContextID == fixture.dismissedItemID)
            #expect(dismissedItem.suggestionRevisionID == fixture.dismissedItemID)
            #expect(dismissedItem.dismissedSuggestionRevisionID == fixture.dismissedItemID)
            #expect(
                InboxSuggestionStateService.state(
                    for: dismissedItem,
                    suggestion: nil,
                    isInFlight: false
                ) == .dismissed
            )
            #expect(readyItem.suggestionContextID == fixture.readyItemID)
            #expect(readyItem.suggestionRevisionID == fixture.readyItemID)
            #expect(readyItem.dismissedSuggestionRevisionID == nil)
            #expect(suggestion.inboxItemContextID == fixture.readyItemID)
            #expect(suggestion.inboxItemRevisionID == fixture.readyItemID)
            #expect(suggestion.belongs(to: readyItem))
        }
    }
}
