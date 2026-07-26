import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLLMTaskWorkspacePlanningServiceTests {
    @MainActor
    @Test
    func toolLoopReceivesStableWorkspaceAndReusesExistingCategory() async throws {
        let categoryID = Self.id(1)
        let taskID = Self.id(2)
        let snapshot = AITaskWorkspaceSnapshot(
            categories: [
                Self.category(id: categoryID, title: "a"),
            ],
            tasks: [],
            checklistItems: []
        )
        let transport = try ScriptedWorkspacePlanningTransport(
            responses: [
                Self.toolResponse(
                    reasoning: "Reuse the exact existing category identity.",
                    calls: [
                        (
                            "call_reuse",
                            "use_existing_category",
                            #"{"title":"a"}"#
                        ),
                        (
                            "call_task",
                            "create_task",
                            Self.arguments([
                                "title": "Use existing a",
                                "parentID": NSNull(),
                                "categoryID": categoryID.uuidString,
                                "notes": "",
                                "estimatedMinutes": NSNull(),
                                "dueAt": NSNull(),
                                "iconName": "checkmark.circle",
                                "colorHex": "1677FF",
                            ])
                        ),
                    ]
                ),
                Self.toolResponse(
                    calls: [
                        ("call_finalize", "finalize_plan", "{}"),
                    ]
                ),
            ],
            generatedIDs: [taskID]
        )
        let service = LLMTaskWorkspacePlanningService(
            transport: transport.data(for:)
        )

        let plan = try await service.generate(
            request: "Add one task under a",
            instructions: "Reuse existing facts whenever possible.",
            workspace: snapshot,
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1",
            makeID: transport.nextGeneratedID
        )

        #expect(plan.originalSnapshot == snapshot)
        #expect(plan.resultingSnapshot.categories.map(\.id) == [categoryID])
        #expect(plan.resultingSnapshot.tasks.map(\.id) == [taskID])
        #expect(plan.resultingSnapshot.tasks.first?.categoryID == categoryID)
        #expect(
            plan.operations.contains(.useExistingCategory(categoryID: categoryID))
        )
        #expect(
            plan.operations.contains {
                guard case let .createTask(task) = $0 else { return false }
                return task.id == taskID && task.categoryID == categoryID
            }
        )

        let requests = transport.requests
        #expect(requests.count == 2)
        let firstBody = try Self.requestJSONObject(requests[0])
        let firstMessages = try #require(
            firstBody["messages"] as? [[String: Any]]
        )
        let userContent = try #require(firstMessages.last?["content"] as? String)
        #expect(userContent.contains(categoryID.uuidString))
        #expect(userContent.contains(#""title":"a""#))
        #expect(userContent.contains("clientMutationID") == false)
        #expect(firstBody["tools"] != nil)
        #expect(firstBody["response_format"] == nil)

        let secondBody = try Self.requestJSONObject(requests[1])
        let secondMessages = try #require(
            secondBody["messages"] as? [[String: Any]]
        )
        let assistant = try #require(
            secondMessages.first { ($0["role"] as? String) == "assistant" }
        )
        #expect(
            assistant["reasoning_content"] as? String ==
                "Reuse the exact existing category identity."
        )
        let toolMessages = secondMessages.filter {
            ($0["role"] as? String) == "tool"
        }
        #expect(
            Set(toolMessages.compactMap { $0["tool_call_id"] as? String }) ==
                ["call_reuse", "call_task"]
        )
    }

    @MainActor
    @Test
    func fullWorkspaceRequestIsNotSilentlyCappedAtLegacyBodyBudget() async throws {
        let tasks = (0 ..< 300).map { index in
            AITaskWorkspaceTask(
                id: Self.id(10000 + index),
                title: "Task \(index)",
                parentID: nil,
                categoryID: nil,
                path: "Task \(index)",
                notes: String(repeating: "\(index)-context-", count: 48),
                estimatedMinutes: nil,
                dueAt: nil,
                iconName: "checkmark.circle",
                colorHex: "1677FF",
                sortOrder: Double(index * 10),
                isArchived: false
            )
        }
        let snapshot = AITaskWorkspaceSnapshot(
            categories: [],
            tasks: tasks,
            checklistItems: []
        )
        let transport = try ScriptedWorkspacePlanningTransport(
            responses: [
                Self.toolResponse(
                    calls: [
                        ("call_finalize", "finalize_plan", "{}"),
                    ]
                ),
            ]
        )
        let service = LLMTaskWorkspacePlanningService(
            transport: transport.data(for:)
        )

        let plan = try await service.generate(
            request: "Review the complete workspace",
            instructions: "",
            workspace: snapshot,
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1"
        )

        let request = try #require(transport.requests.first)
        let body = try #require(request.httpBody)
        #expect(body.count > LLMSuggestionInputPolicy.maximumRequestBodyByteCount)
        #expect(String(decoding: body, as: UTF8.self).contains(tasks.last!.id.uuidString))
        #expect(plan.resultingSnapshot.tasks.count == tasks.count)
        #expect(plan.operations.isEmpty)
    }

    @MainActor
    @Test
    func unknownToolAndContentOnlyFallbackFailExplicitly() async throws {
        let empty = AITaskWorkspaceSnapshot(
            categories: [],
            tasks: [],
            checklistItems: []
        )
        let unknownTransport = try ScriptedWorkspacePlanningTransport(
            responses: [
                Self.toolResponse(
                    calls: [
                        ("call_unknown", "make_everything", "{}"),
                    ]
                ),
            ]
        )

        await #expect(
            throws: LLMTaskWorkspacePlanningError.unknownTool(
                "make_everything"
            )
        ) {
            _ = try await LLMTaskWorkspacePlanningService(
                transport: unknownTransport.data(for:)
            ).generate(
                request: "Plan",
                instructions: "",
                workspace: empty,
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model-1"
            )
        }

        let contentOnlyTransport = try ScriptedWorkspacePlanningTransport(
            responses: [
                JSONSerialization.data(withJSONObject: [
                    "choices": [[
                        "index": 0,
                        "finish_reason": "stop",
                        "message": [
                            "role": "assistant",
                            "content": #"{"categories":[]}"#,
                        ],
                    ]],
                ]),
            ]
        )
        await #expect(
            throws: LLMTaskWorkspacePlanningError.toolCallRequired
        ) {
            _ = try await LLMTaskWorkspacePlanningService(
                transport: contentOnlyTransport.data(for:)
            ).generate(
                request: "Plan",
                instructions: "",
                workspace: empty,
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model-1"
            )
        }
    }
}

@MainActor
private final class ScriptedWorkspacePlanningTransport {
    private var responses: [Data]
    private var generatedIDs: [UUID]
    private(set) var requests: [URLRequest] = []

    init(
        responses: [Data],
        generatedIDs: [UUID] = []
    ) {
        self.responses = responses
        self.generatedIDs = generatedIDs
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let data = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func nextGeneratedID() -> UUID {
        generatedIDs.removeFirst()
    }
}

private extension CoreLLMTaskWorkspacePlanningServiceTests {
    static func id(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    static func category(
        id: UUID,
        title: String
    ) -> AITaskWorkspaceCategory {
        AITaskWorkspaceCategory(
            id: id,
            title: title,
            iconName: "square.grid.2x2",
            colorHex: "1677FF",
            includesInForecast: true,
            sortOrder: 10
        )
    }

    static func toolResponse(
        reasoning: String? = nil,
        calls: [(id: String, name: String, arguments: String)]
    ) throws -> Data {
        var message: [String: Any] = [
            "role": "assistant",
            "content": NSNull(),
            "tool_calls": calls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": [
                        "name": call.name,
                        "arguments": call.arguments,
                    ],
                ]
            },
        ]
        if let reasoning {
            message["reasoning_content"] = reasoning
        }
        return try JSONSerialization.data(withJSONObject: [
            "choices": [[
                "index": 0,
                "finish_reason": "tool_calls",
                "message": message,
            ]],
        ])
    }

    static func arguments(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return try #require(String(data: data, encoding: .utf8))
    }

    static func requestJSONObject(
        _ request: URLRequest
    ) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }
}
