import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct LLMSuggestionCancellationTests {
    @Test @MainActor
    func disablingAutomaticSuggestionsCancelsInboxAndChecklistRequestsWithoutRetrying() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Design", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Polish the settings screen", deviceID: "test")
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Align the controls",
            deviceID: "test"
        )
        context.insert(task)
        context.insert(inboxItem)
        context.insert(checklistItem)
        try context.save()

        let inboxGate = ControlledLLMTransport(payload: .inbox(taskID: task.id))
        let checklistGate = ControlledLLMTransport(payload: .checklist)
        let store = Self.configuredStore(
            context: context,
            task: task,
            inboxItems: [inboxItem],
            checklistItems: [checklistItem],
            inboxGate: inboxGate,
            checklistGate: checklistGate
        )
        store.preferences.llmAutomaticSuggestionsEnabled = true
        let automaticSuggestionsKey = AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
        let previousAutomaticSuggestionsValue = UserDefaults.standard.object(
            forKey: automaticSuggestionsKey
        )
        defer {
            if let previousAutomaticSuggestionsValue {
                UserDefaults.standard.set(previousAutomaticSuggestionsValue, forKey: automaticSuggestionsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: automaticSuggestionsKey)
            }
        }

        store.autoSuggestInboxItemsIfNeeded()
        store.autoSuggestChecklistVisualsIfNeeded()
        #expect(await Self.eventually {
            let inboxRequestCount = await inboxGate.requestCount
            let checklistRequestCount = await checklistGate.requestCount
            return inboxRequestCount == 1 && checklistRequestCount == 1
        })

        store.setLLMAutomaticSuggestionsEnabled(false)

        #expect(store.inboxSuggestionInFlightIDs.isEmpty)
        #expect(store.checklistVisualSuggestionInFlightIDs.isEmpty)
        #expect(store.inboxSuggestionTasksByItemID.isEmpty)
        #expect(store.checklistVisualSuggestionTasksByItemID.isEmpty)

        await inboxGate.resumeAll()
        await checklistGate.resumeAll()
        #expect(await Self.eventually {
            let inboxCancellationCount = await inboxGate.cancelledRequestCount
            let checklistCancellationCount = await checklistGate.cancelledRequestCount
            return inboxCancellationCount == 1 && checklistCancellationCount == 1
        })

        #expect(await inboxGate.requestCount == 1)
        #expect(await checklistGate.requestCount == 1)
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
        #expect(store.inboxSuggestionFailureByItemID[inboxItem.id] == nil)
        #expect(store.checklistVisualSuggestionFailureFingerprintByItemID[checklistItem.id] == nil)
        #expect(store.checklistVisualSuggestionRetryAfterByItemID[checklistItem.id] == nil)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func deletingInboxItemsCancelsAutomaticAndManualRequestsWithoutPersistingResults() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let automaticItem = InboxItem(title: "Review chapter one", deviceID: "test")
        let manualItem = InboxItem(title: "Review chapter two", sortOrder: 20, deviceID: "test")
        context.insert(task)
        context.insert(automaticItem)
        context.insert(manualItem)
        try context.save()

        let gate = ControlledLLMTransport(payload: .inbox(taskID: task.id))
        let store = Self.configuredStore(
            context: context,
            task: task,
            inboxItems: [automaticItem, manualItem],
            checklistItems: [],
            inboxGate: gate
        )
        store.preferences.llmAutomaticSuggestionsEnabled = true

        store.suggestInboxItem(automaticItem, showsErrors: false)
        store.suggestInboxItem(manualItem, showsErrors: true)
        #expect(await Self.eventually { await gate.requestCount == 2 })

        store.deleteInboxItem(automaticItem)
        store.deleteInboxItem(manualItem)

        #expect(store.inboxSuggestionInFlightIDs.isEmpty)
        #expect(store.inboxSuggestionTasksByItemID.isEmpty)
        await gate.resumeAll()
        #expect(await Self.eventually { await gate.cancelledRequestCount == 2 })

        #expect(await gate.requestCount == 2)
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
        #expect(store.inboxSuggestionFailureByItemID[automaticItem.id] == nil)
        #expect(store.inboxSuggestionFailureByItemID[manualItem.id] == nil)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func deletingChecklistDraftCancelsItsVisualRequestWithoutRetrying() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Release", parentID: nil, deviceID: "test")
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Prepare release notes",
            deviceID: "test"
        )
        context.insert(task)
        context.insert(checklistItem)
        try context.save()

        let gate = ControlledLLMTransport(payload: .checklist)
        let store = Self.configuredStore(
            context: context,
            task: task,
            inboxItems: [],
            checklistItems: [checklistItem],
            checklistGate: gate
        )
        store.preferences.llmAutomaticSuggestionsEnabled = true

        store.autoSuggestChecklistVisualsIfNeeded()
        #expect(await Self.eventually { await gate.requestCount == 1 })

        var draft = store.editorDraft(for: task)
        draft.checklistItems = []
        #expect(store.saveTaskDraft(draft))

        #expect(store.checklistVisualSuggestionInFlightIDs.isEmpty)
        #expect(store.checklistVisualSuggestionTasksByItemID.isEmpty)
        await gate.resumeAll()
        #expect(await Self.eventually { await gate.cancelledRequestCount == 1 })

        #expect(await gate.requestCount == 1)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
        #expect(store.checklistVisualSuggestionFailureFingerprintByItemID[checklistItem.id] == nil)
        #expect(store.checklistVisualSuggestionRetryAfterByItemID[checklistItem.id] == nil)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func configurationChangeCancelsOldRequestWithoutLettingItsCleanupRemoveTheReplacement() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Planning", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Prepare quarterly plan", deviceID: "test")
        context.insert(task)
        context.insert(inboxItem)
        try context.save()

        let credentialStore = InMemoryLLMCredentialStore(apiKey: "old-key")
        let gate = ControlledLLMTransport(payload: .inbox(taskID: task.id))
        let store = Self.configuredStore(
            context: context,
            task: task,
            inboxItems: [inboxItem],
            checklistItems: [],
            inboxGate: gate,
            credentialStore: credentialStore
        )
        store.preferences.llmAutomaticSuggestionsEnabled = true
        let automaticSuggestionsKey = AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
        let previousAutomaticSuggestionsValue = UserDefaults.standard.object(
            forKey: automaticSuggestionsKey
        )
        UserDefaults.standard.set(true, forKey: automaticSuggestionsKey)
        defer {
            if let previousAutomaticSuggestionsValue {
                UserDefaults.standard.set(previousAutomaticSuggestionsValue, forKey: automaticSuggestionsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: automaticSuggestionsKey)
            }
        }

        store.suggestInboxItem(inboxItem, showsErrors: false)
        #expect(await Self.eventually { await gate.requestCount == 1 })

        #expect(
            store.setLLMConfiguration(
                endpoint: "https://new.example.test/v1",
                apiKey: "new-key",
                selectedModel: "new-model",
                availableModelIDs: ["new-model"]
            )
        )
        #expect(await Self.eventually { await gate.requestCount == 2 })

        await gate.resumeRequest(at: 0)
        #expect(await Self.eventually { await gate.cancelledRequestCount == 1 })
        #expect(store.inboxSuggestionInFlightIDs == [inboxItem.id])
        #expect(store.inboxSuggestionTasksByItemID[inboxItem.id] != nil)
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)

        await gate.resumeRequest(at: 1)
        #expect(await Self.eventually {
            store.inboxSuggestionInFlightIDs.isEmpty && store.inboxSuggestion(for: inboxItem) != nil
        })

        let suggestion = try #require(store.inboxSuggestion(for: inboxItem))
        #expect(suggestion.modelID == "new-model")
        #expect(await gate.requestCount == 2)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func inFlightRequestDoesNotRetainStoreAndIsCancelledOnDeinit() async throws {
        let task = TaskNode(title: "Personal", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Plan the weekend", deviceID: "test")
        let gate = ControlledLLMTransport(payload: .inbox(taskID: task.id))
        var store: TimeTrackerStore? = makeTestStore(
            llmCredentialStore: InMemoryLLMCredentialStore(apiKey: "test-key"),
            inboxSuggestionService: LLMInboxSuggestionService { request in
                try await gate.send(request)
            }
        )
        store?.tasks = [task]
        store?.inboxItems = [inboxItem]
        store?.preferences.llmEndpoint = "https://example.test/v1"
        store?.preferences.llmAPIKey = "test-key"
        store?.preferences.llmSelectedModel = "test-model"

        store?.suggestInboxItem(inboxItem, showsErrors: true)
        #expect(await Self.eventually { await gate.requestCount == 1 })

        weak let weakStore = store
        store = nil

        #expect(weakStore == nil)
        await gate.resumeAll()
        #expect(await Self.eventually { await gate.cancelledRequestCount == 1 })
        #expect(await gate.requestCount == 1)
    }

    @MainActor
    private static func configuredStore(
        context: ModelContext,
        task: TaskNode,
        inboxItems: [InboxItem],
        checklistItems: [ChecklistItem],
        inboxGate: ControlledLLMTransport? = nil,
        checklistGate: ControlledLLMTransport? = nil,
        credentialStore: InMemoryLLMCredentialStore? = nil
    ) -> TimeTrackerStore {
        let inboxService = inboxGate.map { gate in
            LLMInboxSuggestionService { request in
                try await gate.send(request)
            }
        } ?? LLMInboxSuggestionService()
        let checklistService = checklistGate.map { gate in
            LLMChecklistVisualSuggestionService { request in
                try await gate.send(request)
            }
        } ?? LLMChecklistVisualSuggestionService()
        let store = makeTestStore(
            llmCredentialStore: credentialStore ?? InMemoryLLMCredentialStore(apiKey: "test-key"),
            inboxSuggestionService: inboxService,
            checklistVisualSuggestionService: checklistService
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.tasks = [task]
        store.inboxItems = inboxItems
        store.checklistItems = checklistItems
        store.preferences.llmEndpoint = "https://example.test/v1"
        store.preferences.llmAPIKey = "test-key"
        store.preferences.llmSelectedModel = "test-model"
        return store
    }

    @MainActor
    private static func eventually(
        timeout: Duration = .seconds(2),
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private actor ControlledLLMTransport {
    enum Payload: Sendable {
        case inbox(taskID: UUID)
        case checklist
    }

    private let payload: Payload
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var requestCount = 0
    private(set) var cancelledRequestCount = 0

    init(payload: Payload) {
        self.payload = payload
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let requestIndex = requestCount
        requestCount += 1
        await withCheckedContinuation { continuation in
            continuations[requestIndex] = continuation
        }
        if withUnsafeCurrentTask(body: { $0?.isCancelled }) == true {
            cancelledRequestCount += 1
        }

        let content: String
        switch payload {
        case let .inbox(taskID):
            content = """
            {"taskID":"\(taskID.uuidString)","reason":"Matched","iconName":"checkmark.circle","colorHex":"1677FF"}
            """
        case .checklist:
            content = """
            {"iconName":"paintbrush","colorHex":"16A34A","reason":"Visual match"}
            """
        }
        let data = try JSONSerialization.data(
            withJSONObject: [
                "choices": [
                    ["message": ["content": content]]
                ]
            ]
        )
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: nil
              ) else {
            throw ControlledLLMTransportError.invalidResponse
        }
        return (data, response)
    }

    func resumeRequest(at index: Int) {
        continuations.removeValue(forKey: index)?.resume()
    }

    func resumeAll() {
        let pendingContinuations = Array(continuations.values)
        continuations.removeAll(keepingCapacity: true)
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}

private final class InMemoryLLMCredentialStore: LLMCredentialStoring {
    private var apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func readAPIKey() throws -> String? {
        apiKey
    }

    func writeAPIKey(_ apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = normalized.isEmpty ? nil : normalized
    }
}

private enum ControlledLLMTransportError: Error {
    case invalidResponse
}
