import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct LLMSuggestionCancellationTests {
    @Test @MainActor
    func invalidChecklistItemsArePrunedFromFailureMetadata() {
        let task = TaskNode(title: "Design", parentID: nil, deviceID: "test")
        let currentItem = ChecklistItem(
            taskID: task.id,
            title: "Align controls",
            deviceID: "test"
        )
        let staleIDs = Set((0 ..< 10000).map { _ in UUID() })
        let store = makeTestStore()
        store.tasks = [task]
        store.taskByID = [task.id: task]
        store.checklistItems = [currentItem]
        store.checklistVisualSuggestionFailureFingerprintByItemID =
            Dictionary(uniqueKeysWithValues: staleIDs.map { ($0, "failed") })
        store.checklistVisualSuggestionRetryAfterByItemID =
            Dictionary(uniqueKeysWithValues: staleIDs.map { ($0, Date.distantFuture) })
        store.checklistVisualSuggestionFailureFingerprintByItemID[currentItem.id] =
            "current"
        store.checklistVisualSuggestionRetryAfterByItemID[currentItem.id] =
            .distantFuture

        store.cancelInvalidChecklistVisualSuggestionRequests()

        #expect(
            Set(store.checklistVisualSuggestionFailureFingerprintByItemID.keys)
                == [currentItem.id]
        )
        #expect(
            Set(store.checklistVisualSuggestionRetryAfterByItemID.keys)
                == [currentItem.id]
        )
    }

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
        let previousAutomaticSuggestionsValue = AppDefaults.shared.object(
            forKey: automaticSuggestionsKey
        )
        defer {
            if let previousAutomaticSuggestionsValue {
                AppDefaults.shared.set(previousAutomaticSuggestionsValue, forKey: automaticSuggestionsKey)
            } else {
                AppDefaults.shared.removeObject(forKey: automaticSuggestionsKey)
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
    func checklistVisualSuggestionWaitsForLatestStableTitleAndCancelsSupersededWork() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Release", parentID: nil, deviceID: "test")
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Prepare notes",
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

        try Self.saveChecklistTitle(
            "Prepare release notes",
            taskID: task.id,
            store: store
        )
        #expect(store.checklistVisualSuggestionInFlightIDs.isEmpty)
        await gate.resumeRequest(at: 0)
        #expect(await Self.eventually { await gate.cancelledRequestCount == 1 })

        try Self.saveChecklistTitle(
            "Prepare release notes carefully",
            taskID: task.id,
            store: store
        )
        try Self.saveChecklistTitle(
            "Prepare final release notes",
            taskID: task.id,
            store: store
        )

        try await Task.sleep(for: .milliseconds(100))
        #expect(await gate.requestCount == 1)
        #expect(await Self.eventually { await gate.requestCount == 2 })
        #expect(
            await gate.requestBody(at: 1)?
                .contains("Prepare final release notes") == true
        )

        await gate.resumeRequest(at: 1)
        #expect(await Self.eventually {
            guard let currentItem = store.checklistItems(for: task.id).first else {
                return false
            }
            return store.checklistVisualSuggestionInFlightIDs.isEmpty &&
                store.checklistVisual(for: currentItem)?
                .suggestionTitleSnapshot == "Prepare final release notes"
        })
        try await Task.sleep(for: .milliseconds(500))
        #expect(await gate.requestCount == 2)
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
        let previousAutomaticSuggestionsValue = AppDefaults.shared.object(
            forKey: automaticSuggestionsKey
        )
        AppDefaults.shared.set(true, forKey: automaticSuggestionsKey)
        defer {
            if let previousAutomaticSuggestionsValue {
                AppDefaults.shared.set(previousAutomaticSuggestionsValue, forKey: automaticSuggestionsKey)
            } else {
                AppDefaults.shared.removeObject(forKey: automaticSuggestionsKey)
            }
        }

        store.suggestInboxItem(inboxItem, showsErrors: false)
        #expect(await Self.eventually { await gate.requestCount == 1 })

        #expect(
            store.setLLMConfiguration(
                endpoint: "https://new.example.test/v1",
                apiKey: "new-key",
                selectedModel: "new-model",
                availableModelIDs: ["new-model"],
                reasoningEffort: .max
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
    func inboxPromptChangeOnlyReplacesInboxRequestAndRejectsOldCompletion() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Planning", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Prepare launch plan", deviceID: "test")
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Review launch copy",
            deviceID: "test"
        )
        context.insert(task)
        context.insert(inboxItem)
        context.insert(checklistItem)
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmEndpoint.rawValue,
            valueJSON: PreferenceJSON.encode("https://example.test/v1"),
            deviceID: "test"
        ))
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmSelectedModel.rawValue,
            valueJSON: PreferenceJSON.encode("test-model"),
            deviceID: "test"
        ))
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmAvailableModelIDs.rawValue,
            valueJSON: PreferenceJSON.encode(["test-model"]),
            deviceID: "test"
        ))
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
        let previousAutomaticSuggestionsValue = AppDefaults.shared.object(
            forKey: automaticSuggestionsKey
        )
        AppDefaults.shared.set(true, forKey: automaticSuggestionsKey)
        defer {
            if let previousAutomaticSuggestionsValue {
                AppDefaults.shared.set(
                    previousAutomaticSuggestionsValue,
                    forKey: automaticSuggestionsKey
                )
            } else {
                AppDefaults.shared.removeObject(forKey: automaticSuggestionsKey)
            }
        }

        store.autoSuggestInboxItemsIfNeeded()
        store.autoSuggestChecklistVisualsIfNeeded()
        #expect(await Self.eventually {
            let inboxRequestCount = await inboxGate.requestCount
            let checklistRequestCount = await checklistGate.requestCount
            return inboxRequestCount == 1 && checklistRequestCount == 1
        })

        let updatedInstructions = "Prefer checklist destinations for concrete steps."
        #expect(
            store.setLLMPromptInstructions(
                updatedInstructions,
                for: .inboxRouting
            )
        )
        #expect(await Self.eventually { await inboxGate.requestCount == 2 })
        #expect(await checklistGate.requestCount == 1)
        #expect(store.preferences.llmInboxSuggestionInstructions == updatedInstructions)
        #expect(store.checklistVisualSuggestionInFlightIDs == [checklistItem.id])

        await inboxGate.resumeRequest(at: 0)
        #expect(await Self.eventually { await inboxGate.cancelledRequestCount == 1 })
        #expect(store.inboxSuggestionInFlightIDs == [inboxItem.id])
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)

        await inboxGate.resumeRequest(at: 1)
        await checklistGate.resumeRequest(at: 0)
        #expect(await Self.eventually {
            store.inboxSuggestionInFlightIDs.isEmpty &&
                store.checklistVisualSuggestionInFlightIDs.isEmpty
        })
        #expect(store.inboxSuggestion(for: inboxItem) != nil)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).count == 1)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func checklistPromptChangeOnlyReplacesChecklistRequestAndRejectsOldCompletion() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Design", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Prepare the visual review", deviceID: "test")
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Choose the review icon",
            deviceID: "test"
        )
        context.insert(task)
        context.insert(inboxItem)
        context.insert(checklistItem)
        Self.insertLLMConfiguration(into: context)
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
        let previousAutomaticSuggestionsValue = AppDefaults.shared.object(
            forKey: automaticSuggestionsKey
        )
        AppDefaults.shared.set(true, forKey: automaticSuggestionsKey)
        defer {
            if let previousAutomaticSuggestionsValue {
                AppDefaults.shared.set(
                    previousAutomaticSuggestionsValue,
                    forKey: automaticSuggestionsKey
                )
            } else {
                AppDefaults.shared.removeObject(forKey: automaticSuggestionsKey)
            }
        }

        store.autoSuggestInboxItemsIfNeeded()
        store.autoSuggestChecklistVisualsIfNeeded()
        #expect(await Self.eventually {
            let inboxRequestCount = await inboxGate.requestCount
            let checklistRequestCount = await checklistGate.requestCount
            return inboxRequestCount == 1 && checklistRequestCount == 1
        })

        let updatedInstructions = "Prefer literal symbols and calm colors."
        #expect(
            store.setLLMPromptInstructions(
                updatedInstructions,
                for: .checklistVisual
            )
        )
        #expect(await Self.eventually { await checklistGate.requestCount == 2 })
        #expect(await inboxGate.requestCount == 1)
        #expect(store.preferences.llmChecklistVisualInstructions == updatedInstructions)
        #expect(store.inboxSuggestionInFlightIDs == [inboxItem.id])

        await checklistGate.resumeRequest(at: 0)
        #expect(await Self.eventually { await checklistGate.cancelledRequestCount == 1 })
        #expect(store.checklistVisualSuggestionInFlightIDs == [checklistItem.id])
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)

        await checklistGate.resumeRequest(at: 1)
        await inboxGate.resumeRequest(at: 0)
        #expect(await Self.eventually {
            store.inboxSuggestionInFlightIDs.isEmpty &&
                store.checklistVisualSuggestionInFlightIDs.isEmpty
        })
        #expect(store.inboxSuggestion(for: inboxItem) != nil)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).count == 1)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func syncedPromptRefreshReplacesOnlyRequestsUsingChangedPrompts() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Launch", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Route launch notes", deviceID: "test")
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Review launch icon",
            deviceID: "test"
        )
        context.insert(task)
        context.insert(inboxItem)
        context.insert(checklistItem)
        Self.insertLLMConfiguration(into: context)
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
        let previousAutomaticSuggestionsValue = AppDefaults.shared.object(
            forKey: automaticSuggestionsKey
        )
        AppDefaults.shared.set(true, forKey: automaticSuggestionsKey)
        defer {
            if let previousAutomaticSuggestionsValue {
                AppDefaults.shared.set(
                    previousAutomaticSuggestionsValue,
                    forKey: automaticSuggestionsKey
                )
            } else {
                AppDefaults.shared.removeObject(forKey: automaticSuggestionsKey)
            }
        }

        store.autoSuggestInboxItemsIfNeeded()
        store.autoSuggestChecklistVisualsIfNeeded()
        #expect(await Self.eventually {
            let inboxRequestCount = await inboxGate.requestCount
            let checklistRequestCount = await checklistGate.requestCount
            return inboxRequestCount == 1 && checklistRequestCount == 1
        })

        let remoteInboxInstructions = "Prefer the closest existing task."
        let remoteChecklistInstructions = "Prefer simple symbols and blue tones."
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmInboxSuggestionInstructions.rawValue,
            valueJSON: PreferenceJSON.encode(remoteInboxInstructions),
            deviceID: "remote"
        ))
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmChecklistVisualInstructions.rawValue,
            valueJSON: PreferenceJSON.encode(remoteChecklistInstructions),
            deviceID: "remote"
        ))
        try context.save()
        try store.refresh(plan: StoreRefreshPlan(scopes: [.preferences]))

        #expect(store.preferences.llmInboxSuggestionInstructions == remoteInboxInstructions)
        #expect(
            store.preferences.llmChecklistVisualInstructions ==
                remoteChecklistInstructions
        )
        #expect(await Self.eventually {
            let inboxRequestCount = await inboxGate.requestCount
            let checklistRequestCount = await checklistGate.requestCount
            return inboxRequestCount == 2 && checklistRequestCount == 2
        })

        await inboxGate.resumeRequest(at: 0)
        await checklistGate.resumeRequest(at: 0)
        #expect(await Self.eventually {
            let inboxCancellationCount = await inboxGate.cancelledRequestCount
            let checklistCancellationCount = await checklistGate.cancelledRequestCount
            return inboxCancellationCount == 1 && checklistCancellationCount == 1
        })
        #expect(store.inboxSuggestionInFlightIDs == [inboxItem.id])
        #expect(store.checklistVisualSuggestionInFlightIDs == [checklistItem.id])
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)

        await inboxGate.resumeRequest(at: 1)
        await checklistGate.resumeRequest(at: 1)
        #expect(await Self.eventually {
            store.inboxSuggestionInFlightIDs.isEmpty &&
                store.checklistVisualSuggestionInFlightIDs.isEmpty
        })
        #expect(store.inboxSuggestion(for: inboxItem) != nil)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).count == 1)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func titleRoundTripRejectsResultFromPreviousSuggestionRevision() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Planning", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Draft launch plan", deviceID: "test")
        context.insert(task)
        context.insert(inboxItem)
        try context.save()

        let gate = ControlledLLMTransport(payload: .inbox(taskID: task.id))
        let store = Self.configuredStore(
            context: context,
            task: task,
            inboxItems: [inboxItem],
            checklistItems: [],
            inboxGate: gate
        )
        store.preferences.llmAutomaticSuggestionsEnabled = false
        let requestedRevisionID = inboxItem.effectiveSuggestionRevisionID

        store.suggestInboxItem(inboxItem, showsErrors: true)
        #expect(await Self.eventually { await gate.requestCount == 1 })

        store.updateInboxItemTitle(inboxItem, title: "Draft launch checklist")
        store.updateInboxItemTitle(inboxItem, title: "Draft launch plan")
        #expect(inboxItem.effectiveSuggestionRevisionID != requestedRevisionID)

        await gate.resumeRequest(at: 0)
        #expect(await Self.eventually { store.inboxSuggestionInFlightIDs.isEmpty })

        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
        #expect(store.inboxSuggestion(for: inboxItem) == nil)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func titleRoundTripRejectsFailureAndStartsQueuedCurrentRevisionRequest() async throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Planning", parentID: nil, deviceID: "test")
        let inboxItem = InboxItem(title: "Draft launch plan", deviceID: "test")
        context.insert(task)
        context.insert(inboxItem)
        try context.save()

        let gate = ControlledLLMTransport(payload: .failureThenInbox(taskID: task.id))
        let store = Self.configuredStore(
            context: context,
            task: task,
            inboxItems: [inboxItem],
            checklistItems: [],
            inboxGate: gate
        )
        store.preferences.llmAutomaticSuggestionsEnabled = true
        let requestedRevisionID = inboxItem.effectiveSuggestionRevisionID

        store.suggestInboxItem(inboxItem, showsErrors: true)
        #expect(await Self.eventually { await gate.requestCount == 1 })

        store.updateInboxItemTitle(inboxItem, title: "Draft launch checklist")
        store.updateInboxItemTitle(inboxItem, title: "Draft launch plan")
        #expect(inboxItem.effectiveSuggestionRevisionID != requestedRevisionID)
        #expect(store.inboxSuggestionPendingIDs == [inboxItem.id])

        await gate.resumeRequest(at: 0)
        #expect(await Self.eventually { await gate.requestCount == 2 })
        #expect(store.inboxSuggestionFailureByItemID[inboxItem.id] == nil)
        #expect(store.errorMessage == nil)

        await gate.resumeRequest(at: 1)
        #expect(await Self.eventually {
            store.inboxSuggestionInFlightIDs.isEmpty && store.inboxSuggestion(for: inboxItem) != nil
        })
        #expect(store.inboxSuggestionFailureByItemID[inboxItem.id] == nil)
        #expect(store.errorMessage == nil)
    }

    @Test @MainActor
    func inFlightRequestDoesNotRetainStoreAndIsCancelledOnDeinit() async {
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
    private static func saveChecklistTitle(
        _ title: String,
        taskID: UUID,
        store: TimeTrackerStore
    ) throws {
        let task = try #require(store.task(for: taskID))
        var draft = store.editorDraft(for: task)
        let index = try #require(draft.checklistItems.indices.first)
        draft.checklistItems[index].title = title
        #expect(store.saveTaskDraft(draft))
    }

    @MainActor
    private static func insertLLMConfiguration(into context: ModelContext) {
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmEndpoint.rawValue,
            valueJSON: PreferenceJSON.encode("https://example.test/v1"),
            deviceID: "test"
        ))
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmSelectedModel.rawValue,
            valueJSON: PreferenceJSON.encode("test-model"),
            deviceID: "test"
        ))
        context.insert(SyncedPreference(
            key: AppPreferenceKey.llmAvailableModelIDs.rawValue,
            valueJSON: PreferenceJSON.encode(["test-model"]),
            deviceID: "test"
        ))
    }

    @MainActor
    private static func eventually(
        timeout: Duration = .seconds(2),
        condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

private actor ControlledLLMTransport {
    enum Payload: Sendable {
        case inbox(taskID: UUID)
        case checklist
        case failureThenInbox(taskID: UUID)
    }

    private let payload: Payload
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var requestBodies: [String] = []
    private(set) var requestCount = 0
    private(set) var cancelledRequestCount = 0

    init(payload: Payload) {
        self.payload = payload
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let requestIndex = requestCount
        requestCount += 1
        requestBodies.append(
            request.httpBody.flatMap {
                String(data: $0, encoding: .utf8)
            } ?? ""
        )
        await withCheckedContinuation { continuation in
            continuations[requestIndex] = continuation
        }
        if withUnsafeCurrentTask(body: { $0?.isCancelled }) == true {
            cancelledRequestCount += 1
        }

        if case .failureThenInbox = payload, requestIndex == 0 {
            throw ControlledLLMTransportError.intentionalFailure
        }

        let content = switch payload {
        case let .inbox(taskID):
            """
            {"destinationKind":"checklist","destinationID":"\(taskID.uuidString)","reason":"Matched","iconName":"checkmark.circle","colorHex":"1677FF"}
            """
        case let .failureThenInbox(taskID):
            """
            {"destinationKind":"checklist","destinationID":"\(taskID.uuidString)","reason":"Matched","iconName":"checkmark.circle","colorHex":"1677FF"}
            """
        case .checklist:
            """
            {"iconName":"paintbrush","colorHex":"16A34A","reason":"Visual match"}
            """
        }
        let data = try JSONSerialization.data(
            withJSONObject: [
                "choices": [
                    ["message": ["content": content]],
                ],
            ]
        )
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: nil
              )
        else {
            throw ControlledLLMTransportError.invalidResponse
        }
        return (data, response)
    }

    func resumeRequest(at index: Int) {
        continuations.removeValue(forKey: index)?.resume()
    }

    func requestBody(at index: Int) -> String? {
        requestBodies.indices.contains(index) ? requestBodies[index] : nil
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
    case intentionalFailure
}
