import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLLMTaskPlanStreamingTests {
    @Test
    func streamingAccumulatesContentReasoningAndUsageIntoDraft() async throws {
        let content = try Self.minimalPlanContent()
        let midpoint = content.index(content.startIndex, offsetBy: content.count / 2)
        let events: [LLMGenerationStreamEvent] = [
            .reasoningDelta("需要先拆分类"),
            .reasoningDelta("再列任务"),
            .contentDelta(String(content[..<midpoint])),
            .contentDelta(String(content[midpoint...])),
            .usage(.init(prompt_tokens: 100, completion_tokens: 42, total_tokens: 142)),
        ]
        var progressSnapshots: [LLMGenerationProgress] = []
        let service = LLMTaskPlanService(streamTransport: Self.scriptedStream(events))

        let draft = try await service.generateStreaming(
            request: "Plan reading",
            instructions: "",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1",
            onProgress: { progressSnapshots.append($0) }
        )

        #expect(draft.tasks.map(\.title) == ["Plan release"])
        #expect(draft.reasoningContent == "需要先拆分类再列任务")
        #expect(draft.rawResponseContent == content)
        #expect(progressSnapshots.isEmpty == false)
        #expect(progressSnapshots.last?.reportedCompletionTokens == 42)
        #expect(progressSnapshots.last?.displayedOutputTokens == 42)
    }

    @Test
    func streamingProgressEstimateCountsCharactersBeforeUsageArrives() async throws {
        let content = try Self.minimalPlanContent()
        let events: [LLMGenerationStreamEvent] = [
            .contentDelta(content),
        ]
        var progressSnapshots: [LLMGenerationProgress] = []
        let service = LLMTaskPlanService(streamTransport: Self.scriptedStream(events))

        _ = try await service.generateStreaming(
            request: "Plan reading",
            instructions: "",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1",
            onProgress: { progressSnapshots.append($0) }
        )

        let progress = try #require(progressSnapshots.last)
        #expect(progress.contentCharacterCount == content.count)
        #expect(progress.reportedCompletionTokens == nil)
        #expect(progress.displayedOutputTokens == content.count / 4)
    }

    @Test
    func streamingRequestOptsIntoServerSentEvents() throws {
        let service = LLMTaskPlanService()

        let request = try service.generationRequest(
            request: "Plan reading",
            instructions: "",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1",
            stream: true
        )

        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.timeoutInterval == 90)
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["stream"] as? Bool == true)
        #expect((json["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true)
    }

    @Test
    func bufferedRequestOmitsStreamingFields() throws {
        let service = LLMTaskPlanService()

        let request = try service.generationRequest(
            request: "Plan reading",
            instructions: "",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1"
        )

        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == 45)
        let body = try #require(request.httpBody)
        let json = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["stream"] == nil)
        #expect(json["stream_options"] == nil)
    }

    @Test
    func bufferedGenerateCapturesReasoningContent() async throws {
        let content = try Self.minimalPlanContent()
        let responseData = try JSONSerialization.data(withJSONObject: [
            "choices": [
                [
                    "message": [
                        "content": content,
                        "reasoning_content": "buffered reasoning",
                    ],
                ],
            ],
        ])
        let service = LLMTaskPlanService { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.test")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (responseData, response)
        }

        let draft = try await service.generate(
            request: "Plan reading",
            instructions: "",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1"
        )

        #expect(draft.reasoningContent == "buffered reasoning")
        #expect(draft.rawResponseContent == content)
    }

    @Test
    func streamingPropagatesTransportErrors() async {
        let service = LLMTaskPlanService(
            streamTransport: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: LLMModelServiceError.timeout)
                }
            }
        )

        await #expect(throws: LLMModelServiceError.self) {
            _ = try await service.generateStreaming(
                request: "Plan reading",
                instructions: "",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model-1"
            )
        }
    }

    @Test
    func streamingRejectsOversizedContentMidStream() async {
        let oversized = String(repeating: "a", count: LLMTaskPlanService.maximumResponseContentByteCount + 1)
        let service = LLMTaskPlanService(
            streamTransport: Self.scriptedStream([.contentDelta(oversized)])
        )

        await #expect(throws: LLMTaskPlanServiceError.responseContentTooLarge) {
            _ = try await service.generateStreaming(
                request: "Plan reading",
                instructions: "",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model-1"
            )
        }
    }

    @Test
    func streamingRejectsNonJSONContentAfterCompletion() async {
        let service = LLMTaskPlanService(
            streamTransport: Self.scriptedStream([.contentDelta("definitely not json")])
        )

        await #expect(throws: LLMTaskPlanServiceError.invalidResponse) {
            _ = try await service.generateStreaming(
                request: "Plan reading",
                instructions: "",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model-1"
            )
        }
    }

    @Test
    func streamingRejectsEmptyContent() async {
        let service = LLMTaskPlanService(
            streamTransport: Self.scriptedStream([.reasoningDelta("only reasoning")])
        )

        await #expect(throws: LLMTaskPlanServiceError.invalidResponse) {
            _ = try await service.generateStreaming(
                request: "Plan reading",
                instructions: "",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model-1"
            )
        }
    }

    private static func scriptedStream(
        _ events: [LLMGenerationStreamEvent]
    ) -> LLMTaskPlanService.StreamingTransport {
        { _ in
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    private static func minimalPlanContent() throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "categories": [],
            "tasks": [
                [
                    "reference": "root",
                    "categoryReference": NSNull(),
                    "parentReference": NSNull(),
                    "title": "Plan release",
                    "notes": NSNull(),
                    "estimatedMinutes": NSNull(),
                    "iconName": "target",
                    "colorHex": "34C759",
                ],
            ],
            "checklistItems": [],
        ])
        return try #require(String(data: data, encoding: .utf8))
    }
}

@Suite(.serialized)
struct CoreLLMServerSentEventParserTests {
    @Test
    func framesCompleteOnBlankLines() {
        var parser = LLMServerSentEventParser()

        let payloads = feed("data: first\n\ndata: second\n\n", into: &parser)

        #expect(payloads == ["first", "second"])
    }

    @Test
    func multipleDataLinesJoinWithNewlines() {
        var parser = LLMServerSentEventParser()

        let payloads = feed("data: line one\ndata: line two\n\n", into: &parser)

        #expect(payloads == ["line one\nline two"])
    }

    @Test
    func commentAndKeepaliveLinesAreIgnored() {
        var parser = LLMServerSentEventParser()

        let payloads = feed(": keepalive\n\ndata: real\n\n", into: &parser)

        #expect(payloads == ["real"])
    }

    @Test
    func carriageReturnLineEndingsAreAccepted() {
        var parser = LLMServerSentEventParser()

        let payloads = feed("data: windows\r\n\r\ndata: next\r\n\r\n", into: &parser)

        #expect(payloads == ["windows", "next"])
    }

    @Test
    func multibyteUTF8SurvivesByteByByteDelivery() {
        var parser = LLMServerSentEventParser()

        let payloads = feed("data: 思考 🤔\n\n", into: &parser)

        #expect(payloads == ["思考 🤔"])
    }

    @Test
    func trailingFrameWithoutTerminatorFlushesOnFinish() {
        var parser = LLMServerSentEventParser()

        let payloads = feed("data: [DONE]", into: &parser)
        let flushed = parser.finish()

        #expect(payloads == [])
        #expect(flushed == ["[DONE]"])
    }

    @Test
    func emptyFramesProduceNoPayload() {
        var parser = LLMServerSentEventParser()

        let payloads = feed("\n\ndata: kept\n\n", into: &parser)

        #expect(payloads == ["kept"])
    }

    private func feed(
        _ text: String,
        into parser: inout LLMServerSentEventParser
    ) -> [String] {
        var payloads: [String] = []
        for byte in text.utf8 {
            payloads.append(contentsOf: parser.append(byte))
        }
        return payloads
    }
}
