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
}
