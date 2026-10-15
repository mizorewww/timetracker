import Foundation
import OpenAI
import Testing
@testable import timetracker

@MainActor
struct LLMTaskWorkspacePlanningLoopTests {
    @Test
    func modelThatNeverFinalizesStopsAtTheRoundLimit() async throws {
        var requestCount = 0
        let service = LLMTaskWorkspacePlanningService { _, _ in
            requestCount += 1
            let body = """
            {"id":"r\(requestCount)","object":"chat.completion","created":0,"model":"model",\
            "choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,\
            "tool_calls":[{"id":"call-\(requestCount)","type":"function",\
            "function":{"name":"list_workspace","arguments":"{}"}}]}}]}
            """
            return try JSONDecoder().decode(ChatResult.self, from: Data(body.utf8))
        }

        await #expect(
            throws: LLMTaskWorkspacePlanningError.toolRoundLimitExceeded(
                LLMTaskWorkspacePlanningService.maximumToolRounds
            )
        ) {
            _ = try await service.generate(
                request: "Plan my week",
                instructions: "",
                workspace: AITaskWorkspaceSnapshot(categories: [], tasks: [], checklistItems: []),
                configuration: LLMRequestConfiguration(
                    endpoint: "https://example.test/v1",
                    apiKey: "key",
                    modelID: "model",
                    reasoningEffort: .automatic
                )
            )
        }
        #expect(requestCount == LLMTaskWorkspacePlanningService.maximumToolRounds)
    }
}
