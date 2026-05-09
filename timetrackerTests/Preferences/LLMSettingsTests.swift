import Foundation
import Testing
@testable import timetracker

struct LLMSettingsTests {
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
    func fetchModelsDecodesUniqueSortedModelIDs() async throws {
        let service = LLMModelService { request in
            #expect(request.url?.absoluteString == "https://example.test/v1/models")
            let data = Data("""
            {
              "object": "list",
              "data": [
                { "id": "gpt-z", "object": "model" },
                { "id": "gpt-a", "object": "model" },
                { "id": "gpt-a", "object": "model" }
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
            candidates: [candidate],
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
                taskID: taskID.uuidString,
                reason: "  related to design ",
                iconName: "not.a.real.symbol",
                colorHex: "BADBAD"
            ),
            candidates: [
                LLMTaskCandidate(
                    id: taskID,
                    title: "Design",
                    path: "Work / Design",
                    iconName: "paintbrush",
                    colorHex: "16A34A"
                )
            ],
            modelID: "gpt-test"
        )

        #expect(result.taskID == taskID)
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
            )
        ]

        do {
            _ = try LLMInboxSuggestionService.sanitize(
                payload: InboxSuggestionPayload(
                    taskID: UUID().uuidString,
                    reason: "wrong task",
                    iconName: "book",
                    colorHex: "16A34A"
                ),
                candidates: candidates,
                modelID: "gpt-test"
            )
            Issue.record("Expected unknown task ID to be rejected")
        } catch let error as LLMInboxSuggestionServiceError {
            #expect(error == .noValidTask)
        }

        do {
            _ = try LLMInboxSuggestionService.sanitize(
                payload: InboxSuggestionPayload(
                    taskID: "not-a-uuid",
                    reason: "bad task ID",
                    iconName: "book",
                    colorHex: "16A34A"
                ),
                candidates: candidates,
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
                candidates: [
                    LLMTaskCandidate(
                        id: taskID,
                        title: "Study",
                        path: "Study / UX",
                        iconName: "book",
                        colorHex: "16A34A"
                    )
                ],
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
                    "content": "{\\"taskID\\":\\"\(taskID.uuidString)\\"}"
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
                candidates: [
                    LLMTaskCandidate(
                        id: taskID,
                        title: "Study",
                        path: "Study / UX",
                        iconName: "book",
                        colorHex: "16A34A"
                    )
                ],
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
                    "content": "{\\"taskID\\":\\"\(taskID.uuidString)\\",\\"reason\\":\\"same project\\",\\"iconName\\":\\"book\\",\\"colorHex\\":\\"16A34A\\"}"
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
            candidates: [
                LLMTaskCandidate(
                    id: taskID,
                    title: "Study",
                    path: "Study / UX",
                    iconName: "book",
                    colorHex: "16A34A"
                )
            ],
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "gpt-test"
        )

        #expect(result.taskID == taskID)
        #expect(result.iconName == "book")
        #expect(result.colorHex == "16A34A")
        #expect(result.reason == "same project")
    }

    @Test
    func checklistVisualSuggestionRequestUsesAllAvailableSymbols() throws {
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
