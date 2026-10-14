import Foundation
import Testing
@testable import timetracker

@MainActor
struct LLMTaskWorkspacePlanningLoopTests {
    @Test
    func modelThatNeverFinalizesStopsAtTheRoundLimit() async throws {
        var requestCount = 0
        let service = LLMTaskWorkspacePlanningService { request in
            requestCount += 1
            let body = """
            {"choices":[{"index":0,"finish_reason":"tool_calls","message":{"role":"assistant","content":null,\
            "tool_calls":[{"id":"call-\(requestCount)","type":"function",\
            "function":{"name":"list_workspace","arguments":"{}"}}]}}]}
            """
            let response = try #require(
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            )
            return (Data(body.utf8), response)
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
                    reasoningEffort: .high
                )
            )
        }
        #expect(requestCount == LLMTaskWorkspacePlanningService.maximumToolRounds)
    }
}
