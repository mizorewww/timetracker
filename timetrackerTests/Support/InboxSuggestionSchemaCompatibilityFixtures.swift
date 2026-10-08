import Foundation
import SwiftData
@testable import timetracker

@MainActor
struct LegacyV11InboxSuggestionStoreFixture {
    let fixture: LegacyStoreFixture<(inboxItemID: UUID, suggestionID: UUID, taskID: UUID)>

    var storeURL: URL {
        fixture.storeURL
    }

    var inboxItemID: UUID {
        fixture.seed.inboxItemID
    }

    var suggestionID: UUID {
        fixture.seed.suggestionID
    }

    var taskID: UUID {
        fixture.seed.taskID
    }

    static func create() throws -> LegacyV11InboxSuggestionStoreFixture {
        try LegacyV11InboxSuggestionStoreFixture(
            fixture: LegacyStoreFixture.create(
                name: "LegacyV11",
                schema: TimeTrackerSchemaV11.self
            ) { context in
                let task = TaskNode(title: "Legacy destination", parentID: nil, deviceID: "legacy")
                let item = InboxItem(title: "Legacy suggestion", deviceID: "legacy")
                let suggestion = TimeTrackerSchemaV11.InboxSuggestion(
                    inboxItemID: item.id,
                    inboxItemContextID: item.effectiveSuggestionContextID,
                    inboxItemRevisionID: item.effectiveSuggestionRevisionID,
                    taskID: task.id,
                    reason: "V11 reason",
                    iconName: "archivebox",
                    colorHex: "FF9500",
                    modelID: "legacy-model",
                    titleSnapshot: item.title,
                    generatedAt: Date(timeIntervalSinceReferenceDate: 120_000),
                    deviceID: "legacy"
                )
                context.insert(task)
                context.insert(item)
                context.insert(suggestion)
                return (
                    inboxItemID: item.id,
                    suggestionID: suggestion.id,
                    taskID: task.id
                )
            }
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try fixture.withCurrentContext(body)
    }

    func remove() {
        fixture.remove()
    }
}
