import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreInboxStoreTests {
    @Test @MainActor
    func tiedInboxOrderingUsesUUIDAcrossDomainAndDisplayStores() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let timestamp = Date(timeIntervalSinceReferenceDate: 100)
        let first = InboxItem(title: "First", sortOrder: 10, deviceID: "test")
        first.id = firstID
        first.createdAt = timestamp
        let second = InboxItem(title: "Second", sortOrder: 10, deviceID: "test")
        second.id = secondID
        second.createdAt = timestamp

        var domainStore = InboxStore()
        domainStore.refresh(items: [second, first], suggestions: [])
        #expect(domainStore.items.map(\.id) == [firstID, secondID])

        let store = makeTestStore()
        store.inboxItems = [second, first]
        #expect(store.openInboxItems.map(\.id) == [firstID, secondID])

        domainStore.refresh(items: [first, second], suggestions: [])
        store.inboxItems = [first, second]
        #expect(domainStore.items.map(\.id) == [firstID, secondID])
        #expect(store.openInboxItems.map(\.id) == [firstID, secondID])
    }

    @Test @MainActor
    func captureDraftClearsOnlyAfterTheStoreCommits() {
        var blankDraft = InboxCaptureDraft(title: " \n ")
        var blankWriteAttempts = 0
        #expect(
            !blankDraft.submit { _ in
                blankWriteAttempts += 1
                return true
            }
        )
        #expect(blankDraft.title == " \n ")
        #expect(blankWriteAttempts == 0)

        var draft = InboxCaptureDraft(title: "  Keep this thought  ")
        var attemptedTitles: [String] = []

        let failed = draft.submit { title in
            attemptedTitles.append(title)
            return false
        }

        #expect(!failed)
        #expect(draft.title == "  Keep this thought  ")
        #expect(attemptedTitles == ["Keep this thought"])

        let store = makeTestStore()
        let storeFailed = draft.submit(using: store.addInboxItem(title:))
        #expect(!storeFailed)
        #expect(draft.title == "  Keep this thought  ")
        #expect(store.inboxItems.isEmpty)

        let committed = draft.submit { title in
            attemptedTitles.append(title)
            return true
        }
        #expect(committed)
        #expect(draft.title.isEmpty)
        #expect(attemptedTitles == ["Keep this thought", "Keep this thought"])
    }

    @Test @MainActor
    func automaticChecklistVisualSuggestionsKeepAThreeRequestPeak() async throws {
        let probe = LLMSuggestionConcurrencyProbe()
        let service = LLMChecklistVisualSuggestionService { request in
            await probe.beginRequest()
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                await probe.endRequest()
                throw error
            }
            await probe.endRequest()

            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                  ) else {
                throw InboxSuggestionTestError.invalidResponse
            }
            return (Data("{\"choices\":[]}".utf8), response)
        }
        let store = makeTestStore(
            llmCredentialStore: InboxTestCredentialStore(),
            inboxSuggestionService: LLMInboxSuggestionService(),
            checklistVisualSuggestionService: service
        )
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let items = (0..<8).map {
            ChecklistItem(taskID: task.id, title: "Checklist item \($0)", deviceID: "test")
        }
        store.tasks = [task]
        store.checklistItems = items
        store.preferences.llmEndpoint = "https://example.test/v1"
        store.preferences.llmAPIKey = "test-key"
        store.preferences.llmSelectedModel = "test-model"
        store.preferences.llmAutomaticSuggestionsEnabled = true

        store.autoSuggestChecklistVisualsIfNeeded()

        for _ in 0..<100 {
            if await probe.completedRequestCount == items.count,
               store.checklistVisualSuggestionInFlightIDs.isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(await probe.peakRequestCount == 3)
        #expect(await probe.completedRequestCount == items.count)
        #expect(store.checklistVisualSuggestionInFlightIDs.isEmpty)
    }

    @Test @MainActor
    func allInboxSuggestionEntryPointsShareTheThreeRequestLimit() async throws {
        let probe = LLMSuggestionConcurrencyProbe()
        let service = LLMInboxSuggestionService { request in
            await probe.beginRequest()
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                await probe.endRequest()
                throw error
            }
            await probe.endRequest()

            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                  ) else {
                throw InboxSuggestionTestError.invalidResponse
            }
            return (Data("{\"choices\":[]}".utf8), response)
        }
        let store = makeTestStore(
            llmCredentialStore: InboxTestCredentialStore(),
            inboxSuggestionService: service
        )
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let items = (0..<8).map { InboxItem(title: "Inbox item \($0)", deviceID: "test") }
        store.tasks = [task]
        store.inboxItems = items
        store.preferences.llmEndpoint = "https://example.test/v1"
        store.preferences.llmAPIKey = "test-key"
        store.preferences.llmSelectedModel = "test-model"
        store.preferences.llmAutomaticSuggestionsEnabled = true

        for item in items {
            store.suggestInboxItem(item, showsErrors: false)
        }
        items[0].title = "Inbox item 0, edited while generating"
        store.suggestInboxItem(items[0], showsErrors: false)
        let expectedRequestCount = items.count + 1

        for _ in 0..<100 {
            if await probe.completedRequestCount == expectedRequestCount,
               store.inboxSuggestionInFlightIDs.isEmpty,
               store.inboxSuggestionPendingIDs.isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(await probe.peakRequestCount == 3)
        #expect(await probe.completedRequestCount == expectedRequestCount)
        #expect(store.inboxSuggestionInFlightIDs.isEmpty)
        #expect(store.inboxSuggestionPendingIDs.isEmpty)
    }

    @Test @MainActor
    func automaticSuggestionsDoNotSendUserTextWithoutDeviceConsent() async throws {
        let probe = LLMSuggestionConcurrencyProbe()
        let service = LLMInboxSuggestionService { request in
            await probe.beginRequest()
            await probe.endRequest()
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                  ) else {
                throw InboxSuggestionTestError.invalidResponse
            }
            return (Data("{\"choices\":[]}".utf8), response)
        }
        let store = makeTestStore(
            llmCredentialStore: InboxTestCredentialStore(),
            inboxSuggestionService: service
        )
        let task = TaskNode(title: "Private task", parentID: nil, deviceID: "test")
        let item = InboxItem(title: "Private inbox text", deviceID: "test")
        store.tasks = [task]
        store.inboxItems = [item]
        store.preferences.llmEndpoint = "https://example.test/v1"
        store.preferences.llmAPIKey = "test-key"
        store.preferences.llmSelectedModel = "test-model"

        store.autoSuggestInboxItemsIfNeeded()
        store.suggestInboxItem(item, showsErrors: false)
        try await Task.sleep(for: .milliseconds(30))

        #expect(store.preferences.llmAutomaticSuggestionsEnabled == false)
        #expect(await probe.completedRequestCount == 0)
    }

    @Test @MainActor
    func staleLLMFailuresAreDiscardedAfterTheConfigurationChanges() async throws {
        let inboxService = LLMInboxSuggestionService { _ in
            try await Task.sleep(for: .milliseconds(60))
            throw InboxSuggestionTestError.invalidResponse
        }
        let checklistService = LLMChecklistVisualSuggestionService { _ in
            try await Task.sleep(for: .milliseconds(60))
            throw InboxSuggestionTestError.invalidResponse
        }
        let store = makeTestStore(
            llmCredentialStore: InboxTestCredentialStore(),
            inboxSuggestionService: inboxService,
            checklistVisualSuggestionService: checklistService
        )
        let task = TaskNode(title: "Private task", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Private inbox text", deviceID: "test")
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Private checklist text",
            deviceID: "test"
        )
        store.tasks = [task]
        store.inboxItems = [inboxItem]
        store.checklistItems = [checklistItem]
        store.preferences.llmEndpoint = "https://example.test/v1"
        store.preferences.llmAPIKey = "old-key"
        store.preferences.llmSelectedModel = "old-model"
        store.preferences.llmAutomaticSuggestionsEnabled = true

        store.suggestInboxItem(inboxItem, showsErrors: false)
        store.autoSuggestChecklistVisualsIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        store.preferences.llmSelectedModel = "new-model"
        store.preferences.llmAutomaticSuggestionsEnabled = false
        try await Task.sleep(for: .milliseconds(100))

        #expect(store.inboxSuggestionFailureByItemID[inboxItem.id] == nil)
        #expect(store.checklistVisualSuggestionFailureFingerprintByItemID[checklistItem.id] == nil)
        #expect(store.inboxSuggestionInFlightIDs.isEmpty)
        #expect(store.checklistVisualSuggestionInFlightIDs.isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func delayedChecklistVisualSuggestionCannotWriteIntoAnArchivedSubtree() async throws {
        let service = LLMChecklistVisualSuggestionService { request in
            try await Task.sleep(for: .milliseconds(60))
            let payload = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"iconName\\":\\"paintbrush\\",\\"colorHex\\":\\"16A34A\\",\\"reason\\":\\"design work\\"}"
                  }
                }
              ]
            }
            """
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                  ) else {
                throw InboxSuggestionTestError.invalidResponse
            }
            return (Data(payload.utf8), response)
        }
        let context = try makeTestContext()
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let item = ChecklistItem(taskID: child.id, title: "Polish spacing", deviceID: "test")
        context.insert(parent)
        context.insert(child)
        context.insert(item)
        try context.save()

        let store = makeTestStore(
            llmCredentialStore: InboxTestCredentialStore(),
            inboxSuggestionService: LLMInboxSuggestionService(),
            checklistVisualSuggestionService: service
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.tasks = [parent, child]
        store.checklistItems = [item]
        store.preferences.llmEndpoint = "https://example.test/v1"
        store.preferences.llmAPIKey = "test-key"
        store.preferences.llmSelectedModel = "test-model"
        store.preferences.llmAutomaticSuggestionsEnabled = true

        store.autoSuggestChecklistVisualsIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
        parent.status = .archived
        store.tasks = [parent, child]

        for _ in 0..<50 where !store.checklistVisualSuggestionInFlightIDs.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(store.checklistVisualSuggestionInFlightIDs.isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func inboxSuggestionStateHidesStaleSuggestionsAndAllowsRegeneration() {
        let service = InboxSuggestionStateService()
        let item = InboxItem(title: "Plan chemistry review", deviceID: "test")
        let taskID = UUID()

        #expect(service.state(for: item, suggestion: nil, isInFlight: false) == .eligible)
        #expect(service.shouldAutoSuggest(item: item, suggestion: nil, isInFlight: false))
        #expect(service.displaySuggestion(for: item, suggestion: nil) == nil)

        #expect(service.state(for: item, suggestion: nil, isInFlight: true) == .pending)
        #expect(service.shouldAutoSuggest(item: item, suggestion: nil, isInFlight: true) == false)

        let readySuggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: taskID,
            reason: "Matches study task",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: item.title,
            deviceID: "test"
        )
        #expect(service.state(for: item, suggestion: readySuggestion, isInFlight: false) == .ready)
        #expect(service.displaySuggestion(for: item, suggestion: readySuggestion)?.id == readySuggestion.id)

        item.suggestionGeneratedAt = Date(timeIntervalSince1970: 1_000)
        #expect(service.state(for: item, suggestion: nil, isInFlight: false) == .dismissed)
        #expect(service.shouldAutoSuggest(item: item, suggestion: nil, isInFlight: false) == false)

        item.title = "Plan physics review"
        #expect(service.state(for: item, suggestion: readySuggestion, isInFlight: false) == .stale)
        #expect(service.displaySuggestion(for: item, suggestion: readySuggestion) == nil)
        #expect(service.shouldAutoSuggest(item: item, suggestion: readySuggestion, isInFlight: false))
    }

    @Test @MainActor
    func storeDoesNotExposeStaleInboxSuggestionsToUI() {
        let item = InboxItem(title: "New title", deviceID: "test")
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let staleSuggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: task.id,
            reason: "Old title match",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: "Old title",
            deviceID: "test"
        )

        let store = makeTestStore()
        store.tasks = [task]
        store.inboxItems = [item]
        store.inboxSuggestions = [staleSuggestion]

        #expect(store.inboxSuggestion(for: item) == nil)
    }

    @Test @MainActor
    func storeExposesItemScopedInboxSuggestionFailuresOnlyWhenActionable() {
        let item = InboxItem(title: "Read HIG", deviceID: "test")
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let suggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: task.id,
            reason: "Study item",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: item.title,
            deviceID: "test"
        )
        let store = makeTestStore()
        store.tasks = [task]
        store.inboxItems = [item]
        store.inboxSuggestionFailureByItemID[item.id] = "Could not suggest"

        #expect(store.inboxSuggestionFailureMessage(for: item) == "Could not suggest")

        store.inboxSuggestionInFlightIDs.insert(item.id)
        #expect(store.inboxSuggestionFailureMessage(for: item) == nil)

        store.inboxSuggestionInFlightIDs.remove(item.id)
        store.inboxSuggestions = [suggestion]
        #expect(store.inboxSuggestionFailureMessage(for: item) == nil)
    }

    @Test @MainActor
    func storeCanClearItemScopedInboxSuggestionFailure() {
        let item = InboxItem(title: "Read HIG", deviceID: "test")
        let store = makeTestStore()
        store.inboxSuggestionFailureByItemID[item.id] = "Could not suggest"

        store.clearInboxSuggestionFailure(item)

        #expect(store.inboxSuggestionFailureByItemID[item.id] == nil)
    }

    @Test @MainActor
    func staleSuggestionCannotWriteIntoAChildOfAnArchivedTask() {
        let parent = TaskNode(title: "Archived parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Hidden child", parentID: parent.id, deviceID: "test")
        parent.status = .archived
        let item = InboxItem(title: "Should stay in inbox", deviceID: "test")
        let suggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: child.id,
            reason: "Generated before archive",
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            titleSnapshot: item.title,
            deviceID: "test"
        )
        let store = makeTestStore()
        store.tasks = [parent, child]
        store.inboxItems = [item]
        store.inboxSuggestions = [suggestion]

        store.applyInboxSuggestion(item)

        #expect(item.deletedAt == nil)
        #expect(store.checklistItems.isEmpty)
        #expect(store.errorMessage == AppStrings.localized("inbox.suggestion.error.noValidTask"))
    }

    @Test @MainActor
    func itemScopedSuggestionRefreshReplacesOnlyAffectedInboxSuggestion() {
        let affectedItemID = UUID()
        let unchangedItemID = UUID()
        let taskID = UUID()

        let affectedItem = InboxItem(title: "Affected", deviceID: "test")
        affectedItem.id = affectedItemID
        let unchangedItem = InboxItem(title: "Keep", sortOrder: 20, deviceID: "test")
        unchangedItem.id = unchangedItemID

        let oldAffectedSuggestion = InboxSuggestion(
            inboxItemID: affectedItemID,
            taskID: taskID,
            reason: "Old",
            iconName: "tray",
            colorHex: "8E8E93",
            titleSnapshot: "Affected",
            deviceID: "test"
        )
        let unchangedSuggestion = InboxSuggestion(
            inboxItemID: unchangedItemID,
            taskID: taskID,
            reason: "Keep",
            iconName: "book",
            colorHex: "1677FF",
            titleSnapshot: "Keep",
            deviceID: "test"
        )

        var store = InboxStore()
        store.refresh(
            items: [affectedItem, unchangedItem],
            suggestions: [oldAffectedSuggestion, unchangedSuggestion]
        )

        let updatedAffectedSuggestion = InboxSuggestion(
            inboxItemID: affectedItemID,
            taskID: taskID,
            reason: "Updated",
            iconName: "checkmark.circle",
            colorHex: "34C759",
            titleSnapshot: "Affected",
            deviceID: "test"
        )

        store.refreshSuggestionScoped(
            inboxItemIDs: [affectedItemID],
            suggestions: [updatedAffectedSuggestion]
        )

        #expect(store.items.map(\.id) == [affectedItemID, unchangedItemID])
        #expect(store.suggestions.first { $0.inboxItemID == affectedItemID }?.reason == "Updated")
        #expect(store.suggestions.first { $0.inboxItemID == unchangedItemID }?.reason == "Keep")
        #expect(store.suggestions.contains { $0.id == oldAffectedSuggestion.id } == false)
    }
}

private actor LLMSuggestionConcurrencyProbe {
    private var activeRequestCount = 0
    private(set) var peakRequestCount = 0
    private(set) var completedRequestCount = 0

    func beginRequest() {
        activeRequestCount += 1
        peakRequestCount = max(peakRequestCount, activeRequestCount)
    }

    func endRequest() {
        activeRequestCount -= 1
        completedRequestCount += 1
    }
}

private final class InboxTestCredentialStore: LLMCredentialStoring {
    func readAPIKey() throws -> String? { nil }
    func writeAPIKey(_ apiKey: String) throws {}
}

private enum InboxSuggestionTestError: Error {
    case invalidResponse
}
