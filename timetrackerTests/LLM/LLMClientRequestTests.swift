import Foundation
import OpenAI
import Testing
@testable import timetracker

struct LLMClientRequestTests {
    @Test
    func endpointAcceptsPastedBaseOrOperationURLs() throws {
        let deepSeek = try #require(LLMClient.configuration(endpoint: "https://api.deepseek.com", apiKey: "k"))
        #expect(deepSeek.host == "api.deepseek.com")
        #expect(deepSeek.basePath == "")

        let pasted = try #require(
            LLMClient.configuration(endpoint: "https://example.test/v1/chat/completions/", apiKey: "k")
        )
        #expect(pasted.basePath == "/v1")

        let local = try #require(LLMClient.configuration(endpoint: "http://localhost:11434/v1/models", apiKey: "k"))
        #expect(local.port == 11434)
        #expect(local.basePath == "/v1")
    }

    @Test
    func endpointRejectsPlainHTTPToRemoteHostsAndEmbeddedCredentials() {
        #expect(LLMClient.isValidEndpoint("http://example.test/v1") == false)
        #expect(LLMClient.isValidEndpoint("https://user:pass@example.test") == false)
        #expect(LLMClient.isValidEndpoint("https://example.test/v1?key=1") == false)
        #expect(LLMClient.isValidEndpoint("http://127.0.0.1:8080"))
    }

    @Test @MainActor
    func planningQueryLeavesToolChoiceAndReasoningToTheProviderByDefault() throws {
        let body = try wireJSON(LLMTaskWorkspacePlanningService.query(
            modelID: "deepseek-flash",
            messages: [.user(.init(content: .string("plan")))],
            reasoningEffort: .automatic
        ))
        #expect(body["tool_choice"] == nil)
        #expect(body["temperature"] == nil)
        #expect(body["reasoning_effort"] == nil)
        #expect((body["tools"] as? [Any])?.count == AITaskWorkspaceToolName.allCases.count)
    }

    @Test @MainActor
    func selectedEffortAndEchoedReasoningReachTheWire() throws {
        let body = try wireJSON(LLMTaskWorkspacePlanningService.query(
            modelID: "deepseek-flash",
            messages: [.assistant(.init(
                reasoningContent: "thinking",
                toolCalls: [.init(id: "c1", function: .init(arguments: "{}", name: "list_workspace"))]
            ))],
            reasoningEffort: .max
        ))
        #expect(body["reasoning_effort"] as? String == "max")
        let assistant = try #require((body["messages"] as? [[String: Any]])?.first)
        #expect(assistant["reasoning_content"] as? String == "thinking")
    }

    private func wireJSON(_ query: ChatQuery) throws -> [String: Any] {
        let data = try JSONEncoder().encode(query)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
