import Foundation
import Security
import Testing
@testable import timetracker

struct LLMSettingsTests {
    @Test
    func keychainUpdatesUpgradeLegacyAccessibilityAndKeepSecretsDeviceLocal() throws {
        let service = "me.mezorewww.timetracker.tests.\(UUID().uuidString)"
        let account = "llm-api-key"
        let store = KeychainLLMCredentialStore(service: service, account: account)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        defer { try? store.writeAPIKey("") }

        var legacyItem = baseQuery
        legacyItem[kSecValueData as String] = Data("legacy-key".utf8)
        legacyItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #expect(SecItemAdd(legacyItem as CFDictionary, nil) == errSecSuccess)

        try store.writeAPIKey(" updated-key ")
        #expect(try store.readAPIKey() == "updated-key")

        #expect(
            KeychainLLMCredentialStore.credentialAccessibility as String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )

        var synchronizableQuery = baseQuery
        synchronizableQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue
        synchronizableQuery[kSecReturnData as String] = true
        synchronizableQuery[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(synchronizableQuery as CFDictionary, &result) == errSecItemNotFound)
    }

    @Test
    func configurationDraftNormalizesCredentialsAndRejectsStaleModelSelection() {
        let draft = LLMConfigurationDraft(
            endpoint: " https://example.test/v1 ",
            apiKey: " test-key ",
            selectedModel: "stale-model",
            availableModels: ["gpt-z", "gpt-a", "gpt-a"]
        ).normalized

        #expect(draft.endpoint == "https://example.test/v1")
        #expect(draft.apiKey == "test-key")
        #expect(draft.availableModels == ["gpt-a", "gpt-z"])
        #expect(draft.selectedModel.isEmpty)

        let validDraft = LLMConfigurationDraft(
            endpoint: " https://example.test/v1 ",
            apiKey: " test-key ",
            selectedModel: " gpt-a ",
            availableModels: [" gpt-a ", "", "   "]
        ).normalized
        #expect(validDraft.availableModels == ["gpt-a"])
        #expect(validDraft.selectedModel == "gpt-a")
    }

    @Test
    func taskPlanInstructionsUseTheSyncedValueBoundaryAndPreserveMultilineText() throws {
        let multiline = "Prefer concise categories.\n\tKeep checklist items actionable."
        #expect(
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions(multiline) ==
                multiline
        )

        let exactASCII = String(
            repeating: "a",
            count:
            AppPreferenceValueSanitizer
                .maximumLLMTaskPlanInstructionsByteCount - 2
        )
        #expect(
            AppPreferenceValueSanitizer
                .llmPromptInstructionsStoredByteCount(exactASCII) ==
                AppPreferenceValueSanitizer
                .maximumLLMTaskPlanInstructionsByteCount
        )
        #expect(
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions(exactASCII) ==
                exactASCII
        )

        let exactUnicode = String(repeating: "🧭", count: 16384)
        #expect(exactUnicode.utf8.count > 4 * 1024)
        #expect(
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions(exactUnicode) ==
                exactUnicode
        )

        let oversizedValue = exactASCII + "a"
        let oversizedStorageByteCount =
            AppPreferenceValueSanitizer
                .llmPromptInstructionsStoredByteCount(oversizedValue)
        #expect(throws: LLMTaskPlanInstructionsValidationError.byteLimitExceeded(
            actual: oversizedStorageByteCount,
            maximum: AppPreferenceValueSanitizer.maximumLLMTaskPlanInstructionsByteCount
        )) {
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions(
                oversizedValue
            )
        }

        #expect(throws: LLMTaskPlanInstructionsValidationError.controlCharacter) {
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions("Plan\u{0000}tasks")
        }
        #expect(
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions(" \n\t ") ==
                LLMTaskPlanPrompt.defaultInstructions
        )
    }

    @Test
    func taskPlanDefaultIsMarkdownAndDescribesCompleteDetailedPlans() {
        let instructions = LLMTaskPlanPrompt.defaultInstructions

        #expect(instructions.contains("##"))
        #expect(instructions.contains("**Checklist item**"))
        #expect(instructions.localizedCaseInsensitiveContains("quantity"))
        #expect(instructions.localizedCaseInsensitiveContains("daily"))
        #expect(
            AppPreferenceValueSanitizer
                .llmPromptInstructionsStoredByteCount(instructions) <=
                AppPreferenceValueSanitizer.maximumLLMTaskPlanInstructionsByteCount
        )
    }

    @Test
    func exactLegacyTaskPlanDefaultUpgradesWithoutOverwritingCustomization() throws {
        let legacy = LLMTaskPlanPrompt.legacyDefaultInstructions
        #expect(
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions(legacy) ==
                LLMTaskPlanPrompt.defaultInstructions
        )
        #expect(
            try AppPreferenceValueSanitizer.llmPromptInstructions(
                legacy,
                for: .taskPlan
            ) == LLMTaskPlanPrompt.defaultInstructions
        )

        let customized = legacy + "\n\nKeep this custom rule."
        #expect(
            try AppPreferenceValueSanitizer.llmTaskPlanInstructions(customized) ==
                customized
        )
    }

    @Test @MainActor
    func syncedLegacyTaskPlanDefaultIsReadAndRewrittenAsTheNewDefault() throws {
        let preference = SyncedPreference(
            key: AppPreferenceKey.llmTaskPlanInstructions.rawValue,
            valueJSON: PreferenceJSON.encode(
                LLMTaskPlanPrompt.legacyDefaultInstructions
            ),
            deviceID: "test"
        )
        let preferences = AppPreferences(syncedPreferences: [preference])

        #expect(
            preferences.llmTaskPlanInstructions ==
                LLMTaskPlanPrompt.defaultInstructions
        )
        #expect(
            preferences.valueJSON(for: .llmTaskPlanInstructions) ==
                PreferenceJSON.encode(LLMTaskPlanPrompt.defaultInstructions)
        )
        #expect(
            try PreferenceJSON.canonicalValueJSON(
                for: .llmTaskPlanInstructions,
                from: preference.valueJSON
            ) == PreferenceJSON.encode(LLMTaskPlanPrompt.defaultInstructions)
        )
    }

    @Test
    func everyPromptKindFallsBackToItsOwnDistinctDefault() throws {
        let defaults = try LLMPromptKind.allCases.map { kind in
            let resolved = try AppPreferenceValueSanitizer.llmPromptInstructions(
                " \n\t ",
                for: kind
            )
            #expect(resolved == kind.defaultInstructions)
            return resolved
        }

        #expect(Set(defaults).count == LLMPromptKind.allCases.count)
    }

    @Test
    func promptInstructionsUseTheSyncedPreferenceBoundaryNotALegacy4KiBWindow() throws {
        let instructions = String(
            repeating: "Keep this complete rule with JSON: {\"步骤\":\"完整\"}\n",
            count: 400
        )

        #expect(instructions.utf8.count > 4 * 1024)
        for kind in LLMPromptKind.allCases {
            #expect(
                try AppPreferenceValueSanitizer.llmPromptInstructions(
                    instructions,
                    for: kind
                ) == instructions.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        }
    }

    @Test
    func everyDefaultPromptIncludesATypedWorkedExample() {
        for kind in LLMPromptKind.allCases {
            let instructions = kind.defaultInstructions

            #expect(instructions.contains("### Worked example"))
            #expect(instructions.contains("Example input"))
            #expect(instructions.contains("Example output"))
        }
    }

    @Test
    func exactPreviousZeroShotDefaultsUpgradeWithoutReplacingCustomText() throws {
        for kind in LLMPromptKind.allCases {
            let previous = kind.previousDefaultInstructions

            #expect(
                try AppPreferenceValueSanitizer.llmPromptInstructions(
                    previous,
                    for: kind
                ) == kind.defaultInstructions
            )

            let customized = previous + "\n\nKeep my custom rule."
            #expect(
                try AppPreferenceValueSanitizer.llmPromptInstructions(
                    customized,
                    for: kind
                ) == customized
            )
        }
    }

    @Test
    func everyPromptDisclosesItsEffectiveRequestWithoutTheCredential() {
        for kind in LLMPromptKind.allCases {
            let disclosure = kind.effectiveRequestDisclosure

            #expect(disclosure.contains("POST"))
            #expect(disclosure.contains("messages"))
            #expect(disclosure.contains("model"))
            #expect(disclosure.contains("Authorization"))
            #expect(disclosure.contains("API key"))
            #expect(disclosure.contains("never enters the prompt"))
            #expect(
                disclosure.contains(
                    String(SymbolCatalog.symbolNames.count)
                )
            )
        }

        let planDisclosure =
            LLMPromptKind.taskPlan.effectiveRequestDisclosure
        for tool in AITaskWorkspaceToolName.allCases {
            #expect(planDisclosure.contains(tool.rawValue))
        }
        #expect(planDisclosure.contains("reasoning_effort"))
        #expect(planDisclosure.contains("thinking"))
        #expect(planDisclosure.contains("tool_choice"))
        #expect(planDisclosure.contains("\"parameters\""))
        #expect(planDisclosure.contains("\"additionalProperties\" : false"))
    }

    @Test @MainActor
    func taskPlanInstructionsRoundTripAsANonSensitiveSyncedPreference() throws {
        let instructions = "Use one category per durable area.\n\tPrefer small tasks."
        let valueJSON = try PreferenceJSON.canonicalValueJSON(
            for: .llmTaskPlanInstructions,
            from: PreferenceJSON.encode(instructions)
        )
        let preference = SyncedPreference(
            key: AppPreferenceKey.llmTaskPlanInstructions.rawValue,
            valueJSON: valueJSON,
            deviceID: "test"
        )
        let preferences = AppPreferences(syncedPreferences: [preference])

        #expect(preferences.llmTaskPlanInstructions == instructions)
        #expect(SyncedPreferenceService.shouldSyncKey(preference.key))
        #expect(!SyncedPreferenceService.isSensitiveKey(preference.key))
        #expect(!SyncedPreferenceService.isDeviceLocalKey(preference.key))
        #expect(
            preferences.valueJSON(for: .llmTaskPlanInstructions) ==
                PreferenceJSON.encode(instructions)
        )
    }

    @Test @MainActor
    func inboxAndChecklistInstructionsRoundTripAsIndependentSyncedPreferences() throws {
        let inboxInstructions = "Prefer the narrowest existing destination."
        let checklistInstructions = "Prefer calm colors and familiar symbols."
        let values: [(AppPreferenceKey, String)] = [
            (.llmInboxSuggestionInstructions, inboxInstructions),
            (.llmChecklistVisualInstructions, checklistInstructions),
        ]
        let stored = try values.map { key, value in
            try SyncedPreference(
                key: key.rawValue,
                valueJSON: PreferenceJSON.canonicalValueJSON(
                    for: key,
                    from: PreferenceJSON.encode(value)
                ),
                deviceID: "test"
            )
        }
        let preferences = AppPreferences(syncedPreferences: stored)

        #expect(preferences.llmInboxSuggestionInstructions == inboxInstructions)
        #expect(preferences.llmChecklistVisualInstructions == checklistInstructions)
        #expect(preferences.llmTaskPlanInstructions == LLMPromptKind.taskPlan.defaultInstructions)
        for preference in stored {
            #expect(SyncedPreferenceService.shouldSyncKey(preference.key))
            #expect(!SyncedPreferenceService.isSensitiveKey(preference.key))
            #expect(!SyncedPreferenceService.isDeviceLocalKey(preference.key))
        }
        #expect(
            preferences.valueJSON(for: .llmInboxSuggestionInstructions) ==
                PreferenceJSON.encode(inboxInstructions)
        )
        #expect(
            preferences.valueJSON(for: .llmChecklistVisualInstructions) ==
                PreferenceJSON.encode(checklistInstructions)
        )
    }

    @Test
    func modelListRequestUsesOpenAICompatibleModelsEndpoint() throws {
        let service = LLMModelService()
        let request = try service.modelListRequest(
            endpoint: " https://api.openai.com/v1 ",
            apiKey: " test-key "
        )

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test
    func modelListRequestDoesNotAppendModelsTwice() throws {
        let url = try #require(LLMModelService.modelsURL(endpoint: "https://example.test/v1/models"))
        #expect(url.absoluteString == "https://example.test/v1/models")
    }

    @Test
    func modelEndpointRejectsPlainHTTPExceptForLoopbackDevelopment() throws {
        #expect(LLMModelService.modelsURL(endpoint: "http://example.test/v1") == nil)
        #expect(LLMInboxSuggestionService.chatCompletionsURL(endpoint: "http://example.test/v1") == nil)
        #expect(LLMModelService.modelsURL(endpoint: "http://127.evil.test/v1") == nil)
        #expect(LLMModelService.modelsURL(endpoint: "http://127.0.0.999/v1") == nil)
        #expect(LLMModelService.modelsURL(endpoint: "https://user:password@example.test/v1") == nil)

        let localModels = try #require(LLMModelService.modelsURL(endpoint: "http://127.0.0.1:11434/v1"))
        let localChat = try #require(LLMInboxSuggestionService.chatCompletionsURL(endpoint: "http://localhost:11434/v1"))
        let ipv6Models = try #require(LLMModelService.modelsURL(endpoint: "http://[0:0:0:0:0:0:0:1]:11434/v1"))
        #expect(localModels.absoluteString == "http://127.0.0.1:11434/v1/models")
        #expect(localChat.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(ipv6Models.absoluteString == "http://[0:0:0:0:0:0:0:1]:11434/v1/models")
    }

    @Test
    func modelRedirectsStayWithinTheValidatedOrigin() throws {
        let source = try #require(URL(string: "https://example.test/v1/models"))
        let sameOrigin = try #require(URL(string: "https://example.test:443/v2/models"))
        let otherHost = try #require(URL(string: "https://api.example.test/v2/models"))
        let otherPort = try #require(URL(string: "https://example.test:8443/v2/models"))
        let downgrade = try #require(URL(string: "http://example.test/v2/models"))

        #expect(LLMModelService.isSafeRedirect(from: source, to: sameOrigin))
        #expect(!LLMModelService.isSafeRedirect(from: source, to: otherHost))
        #expect(!LLMModelService.isSafeRedirect(from: source, to: otherPort))
        #expect(!LLMModelService.isSafeRedirect(from: source, to: downgrade))
    }

    @Test
    func fetchModelsDecodesUniqueSortedModelIDs() async throws {
        let service = LLMModelService { request in
            #expect(request.url?.absoluteString == "https://example.test/v1/models")
            let data = Data("""
            {
              "object": "list",
              "data": [
                { "id": " gpt-z ", "object": "model" },
                { "id": "gpt-a", "object": "model" },
                { "id": "gpt-a", "object": "model" },
                { "id": "   ", "object": "model" }
              ]
            }
            """.utf8)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }

        let models = try await service.fetchModels(endpoint: "https://example.test/v1", apiKey: "key")

        #expect(models == ["gpt-a", "gpt-z"])
    }

    @Test
    func modelListResponseKeepsTheExactMaximumModelCount() throws {
        let modelIDs = (0 ..< AppPreferenceValueSanitizer.maximumLLMModelCount).map {
            String(format: "model-%03d", $0)
        }

        #expect(try decodedModelIDs(modelIDs) == modelIDs)
    }

    @Test
    func modelListResponseTruncatesToTheSortedPreferenceBoundary() throws {
        let limit = AppPreferenceValueSanitizer.maximumLLMModelCount
        let modelIDs = (1 ... limit).map {
            String(format: "model-%03d", $0)
        } + ["model-999", "model-000"]

        let decoded = try decodedModelIDs(modelIDs)

        #expect(decoded.count == limit)
        #expect(decoded.first == "model-000")
        #expect(decoded.last == String(format: "model-%03d", limit - 1))
        #expect(!decoded.contains(String(format: "model-%03d", limit)))
        #expect(!decoded.contains("model-999"))
        #expect(decoded == AppPreferenceValueSanitizer.llmModelIDs(modelIDs))
    }

    @Test
    func modelListResponsePreservesValidUnicodeAndFiltersDuplicateOrInvalidIDs() throws {
        let exactByteBoundary = String(
            repeating: "m",
            count: AppPreferenceValueSanitizer.maximumLLMModelIDByteCount
        )
        let exactUnicodeByteBoundary = String(repeating: "🧭", count: 64)
        let oversizedUnicode = String(repeating: "🧭", count: 65)
        let modelIDs = [
            "  模型-α  ",
            "gpt-z",
            "gpt-z",
            "model\u{0000}suffix",
            oversizedUnicode,
            "   ",
            exactByteBoundary,
            exactUnicodeByteBoundary,
        ]

        let decoded = try decodedModelIDs(modelIDs)

        #expect(decoded == [
            exactByteBoundary,
            exactUnicodeByteBoundary,
            "gpt-z",
            "模型-α",
        ].sorted())
        #expect(decoded == AppPreferenceValueSanitizer.llmModelIDs(modelIDs))
    }

    @Test
    func fetchModelsReportsHTTPFailures() async throws {
        let service = LLMModelService { request in
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (Data(), response)
        }

        do {
            _ = try await service.fetchModels(endpoint: "https://example.test/v1", apiKey: "key")
            Issue.record("Expected unauthorized response to throw")
        } catch let error as LLMModelServiceError {
            #expect(error == .responseStatus(401))
        }
    }

    private func decodedModelIDs(_ modelIDs: [String]) throws -> [String] {
        let payload = [
            "data": modelIDs.map { ["id": $0] },
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(LLMModelListResponse.self, from: data).modelIDs
    }

    @Test
    func inboxSuggestionRequestUsesOpenAICompatibleChatEndpoint() throws {
        let service = LLMInboxSuggestionService()
        let candidate = LLMTaskCandidate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Design",
            path: "Work / Design",
            iconName: "paintbrush",
            colorHex: "1677FF"
        )

        let request = try service.suggestionRequest(
            inboxTitle: "Polish spacing",
            taskCandidates: [candidate],
            categoryCandidates: [],
            endpoint: " https://api.openai.com/v1 ",
            apiKey: " test-key ",
            modelID: "gpt-test"
        )

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.httpBody?.isEmpty == false)
    }

    @Test
    func inboxSuggestionSanitizesWrongSymbolAndColor() throws {
        let taskID = UUID()
        let result = try LLMInboxSuggestionService.sanitize(
            payload: InboxSuggestionPayload(
                destinationKind: InboxSuggestionDestinationKind.checklist.rawValue,
                destinationID: taskID.uuidString,
                reason: "  related to design ",
                iconName: "not.a.real.symbol",
                colorHex: "BADBAD"
            ),
            taskCandidates: [
                LLMTaskCandidate(
                    id: taskID,
                    title: "Design",
                    path: "Work / Design",
                    iconName: "paintbrush",
                    colorHex: "16A34A"
                ),
            ],
            categoryCandidates: [],
            modelID: "gpt-test"
        )

        #expect(result.destination == .checklist(taskID: taskID))
        #expect(result.reason == "related to design")
        #expect(result.iconName == ChecklistVisualSanitizer.defaultIcon)
        #expect(result.colorHex == "16A34A")
    }

    @Test
    func inboxSuggestionRejectsInvalidTaskIDs() throws {
        let taskID = UUID()
        let candidates = [
            LLMTaskCandidate(
                id: taskID,
                title: "Design",
                path: "Work / Design",
                iconName: "paintbrush",
                colorHex: "16A34A"
            ),
        ]

        do {
            _ = try LLMInboxSuggestionService.sanitize(
                payload: InboxSuggestionPayload(
                    destinationKind: InboxSuggestionDestinationKind.checklist.rawValue,
                    destinationID: UUID().uuidString,
                    reason: "wrong task",
                    iconName: "book",
                    colorHex: "16A34A"
                ),
                taskCandidates: candidates,
                categoryCandidates: [],
                modelID: "gpt-test"
            )
            Issue.record("Expected unknown task ID to be rejected")
        } catch let error as LLMInboxSuggestionServiceError {
            #expect(error == .noValidTask)
        }

        do {
            _ = try LLMInboxSuggestionService.sanitize(
                payload: InboxSuggestionPayload(
                    destinationKind: InboxSuggestionDestinationKind.checklist.rawValue,
                    destinationID: "not-a-uuid",
                    reason: "bad task ID",
                    iconName: "book",
                    colorHex: "16A34A"
                ),
                taskCandidates: candidates,
                categoryCandidates: [],
                modelID: "gpt-test"
            )
            Issue.record("Expected malformed task ID to be rejected")
        } catch let error as LLMInboxSuggestionServiceError {
            #expect(error == .noValidTask)
        }
    }

    @Test
    func fetchInboxSuggestionReportsMalformedContentAsInvalidResponse() async throws {
        let taskID = UUID()
        let service = LLMInboxSuggestionService { request in
            let payload = """
            {
              "choices": [
                { "message": { "content": "not json" } }
              ]
            }
            """
            let data = Data(payload.utf8)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }

        do {
            _ = try await service.suggest(
                inboxTitle: "Read HIG",
                taskCandidates: [
                    LLMTaskCandidate(
                        id: taskID,
                        title: "Study",
                        path: "Study / UX",
                        iconName: "book",
                        colorHex: "16A34A"
                    ),
                ],
                categoryCandidates: [],
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "gpt-test"
            )
            Issue.record("Expected malformed content to throw")
        } catch let error as LLMInboxSuggestionServiceError {
            #expect(error == .invalidResponse)
        }
    }

    @Test
    func fetchInboxSuggestionReportsMissingFieldsAsInvalidResponse() async throws {
        let taskID = UUID()
        let service = LLMInboxSuggestionService { request in
            let payload = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"destinationID\\":\\"\(taskID.uuidString)\\"}"
                  }
                }
              ]
            }
            """
            let data = Data(payload.utf8)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }

        do {
            _ = try await service.suggest(
                inboxTitle: "Read HIG",
                taskCandidates: [
                    LLMTaskCandidate(
                        id: taskID,
                        title: "Study",
                        path: "Study / UX",
                        iconName: "book",
                        colorHex: "16A34A"
                    ),
                ],
                categoryCandidates: [],
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "gpt-test"
            )
            Issue.record("Expected missing content fields to throw")
        } catch let error as LLMInboxSuggestionServiceError {
            #expect(error == .invalidResponse)
        }
    }

    @Test
    func fetchInboxSuggestionDecodesChatCompletionContent() async throws {
        let taskID = UUID()
        let service = LLMInboxSuggestionService { request in
            #expect(request.url?.absoluteString == "https://example.test/v1/chat/completions")
            let payload = """
            {
              "choices": [
                {
                  "message": {
                    "content": "{\\"destinationKind\\":\\"checklist\\",\\"destinationID\\":\\"\(taskID.uuidString)\\",\\"reason\\":\\"same project\\",\\"iconName\\":\\"book\\",\\"colorHex\\":\\"16A34A\\"}"
                  }
                }
              ]
            }
            """
            let data = Data(payload.utf8)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }

        let result = try await service.suggest(
            inboxTitle: "Read HIG",
            taskCandidates: [
                LLMTaskCandidate(
                    id: taskID,
                    title: "Study",
                    path: "Study / UX",
                    iconName: "book",
                    colorHex: "16A34A"
                ),
            ],
            categoryCandidates: [],
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "gpt-test"
        )

        #expect(result.destination == .checklist(taskID: taskID))
        #expect(result.iconName == "book")
        #expect(result.colorHex == "16A34A")
        #expect(result.reason == "same project")
    }

    @Test
    func checklistVisualSuggestionRequestUsesTheCompleteSymbolCatalog() throws {
        let service = LLMChecklistVisualSuggestionService()
        let request = try service.suggestionRequest(
            checklistTitle: "Polish spacing",
            taskTitle: "Design",
            taskPath: "Work / Design",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "gpt-test"
        )
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })

        #expect(request.url?.absoluteString == "https://example.test/v1/chat/completions")
        #expect(body.contains("allowedSymbols"))
        if let lastSymbol = SymbolCatalog.symbolNames.last {
            #expect(body.contains(lastSymbol))
        }
        #expect(SymbolCatalog.symbolNames.count > 1000)
        #expect(body.contains("prefix(400)") == false)
    }

    @Test
    func checklistVisualSuggestionSanitizesWrongSymbolAndColor() {
        let result = LLMChecklistVisualSuggestionService.sanitize(
            payload: ChecklistVisualSuggestionPayload(
                iconName: "fake.symbol",
                colorHex: "BADBAD",
                reason: "  visual match "
            ),
            modelID: "gpt-test"
        )

        #expect(result.iconName == ChecklistVisualSanitizer.defaultIcon)
        #expect(result.colorHex == ChecklistVisualSanitizer.defaultColor)
        #expect(result.reason == "visual match")
    }

    @Test
    func fetchChecklistVisualSuggestionDecodesChatCompletionContent() async throws {
        let service = LLMChecklistVisualSuggestionService { request in
            #expect(request.url?.absoluteString == "https://example.test/v1/chat/completions")
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
            let data = Data(payload.utf8)
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            return (data, response)
        }

        let result = try await service.suggest(
            checklistTitle: "Polish spacing",
            taskTitle: "Design",
            taskPath: "Work / Design",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "gpt-test"
        )

        #expect(result.iconName == "paintbrush")
        #expect(result.colorHex == "16A34A")
        #expect(result.reason == "design work")
    }

    @Test @MainActor
    func checklistVisualSuggestionPolicyUsesTitleSnapshotAndManualEdits() {
        let item = ChecklistItem(taskID: UUID(), title: "Draft launch copy", deviceID: "test")
        let policy = ChecklistVisualSuggestionPolicy()

        #expect(policy.shouldSuggest(item: item, visual: nil))

        let defaultVisual = ChecklistItemVisual(checklistItemID: item.id, deviceID: "test")
        #expect(policy.shouldSuggest(item: item, visual: defaultVisual))

        defaultVisual.suggestionTitleSnapshot = "Draft launch copy"
        defaultVisual.suggestionGeneratedAt = Date()
        #expect(policy.shouldSuggest(item: item, visual: defaultVisual) == false)

        item.title = "Draft pricing copy"
        #expect(policy.shouldSuggest(item: item, visual: defaultVisual))

        defaultVisual.userEditedAt = Date()
        #expect(policy.shouldSuggest(item: item, visual: defaultVisual) == false)

        let customLegacyVisual = ChecklistItemVisual(
            checklistItemID: item.id,
            iconName: "book",
            colorHex: "16A34A",
            deviceID: "test"
        )
        #expect(policy.shouldSuggest(item: item, visual: customLegacyVisual) == false)
    }
}
