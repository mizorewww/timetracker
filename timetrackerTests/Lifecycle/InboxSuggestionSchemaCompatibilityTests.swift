import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct InboxSuggestionSchemaCompatibilityTests {
    @Test @MainActor
    func historicalSuggestionSchemasRemainFrozenBeforeDestinationKind() throws {
        let expectedLegacyAttributes: Set = [
            "id",
            "inboxItemID",
            "inboxItemContextID",
            "inboxItemRevisionID",
            "taskID",
            "reason",
            "iconName",
            "colorHex",
            "modelID",
            "titleSnapshot",
            "generatedAt",
            "createdAt",
            "updatedAt",
            "deletedAt",
            "deviceID",
            "clientMutationID",
        ]
        let v10Schema = Schema(versionedSchema: TimeTrackerSchemaV10.self)
        let v11Schema = Schema(versionedSchema: TimeTrackerSchemaV11.self)
        let v12Schema = Schema(versionedSchema: TimeTrackerSchemaV12.self)
        let v13Schema = Schema(versionedSchema: TimeTrackerSchemaV13.self)
        let v10Suggestion = try #require(
            v10Schema.entity(for: TimeTrackerSchemaV10.InboxSuggestion.self)
        )
        let v11Suggestion = try #require(
            v11Schema.entity(for: TimeTrackerSchemaV11.InboxSuggestion.self)
        )
        let v12Suggestion = try #require(v12Schema.entity(for: InboxSuggestion.self))
        let v13Suggestion = try #require(v13Schema.entity(for: InboxSuggestion.self))

        #expect(Set(v10Suggestion.attributesByName.keys) == expectedLegacyAttributes)
        #expect(Set(v11Suggestion.attributesByName.keys) == expectedLegacyAttributes)
        #expect(
            Set(v12Suggestion.attributesByName.keys)
                == expectedLegacyAttributes.union(["destinationKindRaw"])
        )
        #expect(
            Set(v13Suggestion.attributesByName.keys)
                == expectedLegacyAttributes.union(["destinationKindRaw"])
        )
    }

    @Test @MainActor
    func versionElevenSuggestionMigratesToChecklistDestination() throws {
        let fixture = try LegacyV11InboxSuggestionStoreFixture.create()
        defer { fixture.remove() }

        try fixture.withCurrentContext { context in
            let suggestion = try #require(
                try context.fetch(FetchDescriptor<InboxSuggestion>())
                    .first { $0.id == fixture.suggestionID }
            )

            #expect(suggestion.inboxItemID == fixture.inboxItemID)
            #expect(suggestion.taskID == fixture.taskID)
            #expect(suggestion.reason == "V11 reason")
            #expect(suggestion.iconName == "archivebox")
            #expect(suggestion.colorHex == "FF9500")
            #expect(suggestion.modelID == "legacy-model")
            #expect(suggestion.destinationKindRaw == InboxSuggestionDestinationKind.checklist.rawValue)
            #expect(suggestion.destinationKind == .checklist)
            #expect(
                TimeTrackerMigrationPlan.schemas.last?.versionIdentifier
                    == TimeTrackerSchemaV14.versionIdentifier
            )
        }
    }
}
