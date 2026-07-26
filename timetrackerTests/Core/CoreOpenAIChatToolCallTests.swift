import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreOpenAIChatToolCallTests {
    @Test
    func requestEncodesFunctionToolsAssistantToolCallsAndToolResponses() throws {
        let toolCall = OpenAIChatToolCall(
            id: "call_lookup",
            type: "function",
            function: .init(
                name: "lookup_context",
                arguments: #"{"task_id":"task-1"}"#
            )
        )
        let request = OpenAIChatCompletionRequest(
            model: "model",
            messages: [
                OpenAIChatMessage(
                    role: "assistant",
                    content: nil,
                    reasoningContent: "Need current facts first.",
                    toolCalls: [toolCall]
                ),
                OpenAIChatMessage(
                    role: "tool",
                    content: #"{"title":"Ship"}"#,
                    toolCallID: "call_lookup"
                ),
            ],
            temperature: 0,
            responseFormat: .init(type: "json_object"),
            tools: [
                OpenAIChatToolDefinition(
                    function: .init(
                        name: "lookup_context",
                        description: "Read one stable task.",
                        parameters: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "task_id": .object([
                                    "type": .string("string"),
                                ]),
                            ]),
                            "required": .array([.string("task_id")]),
                            "additionalProperties": .bool(false),
                        ])
                    )
                ),
            ]
        )

        let object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(request)
            ) as? [String: Any]
        )
        let messages = try #require(object["messages"] as? [[String: Any]])
        let assistant = messages[0]
        let encodedCalls = try #require(
            assistant["tool_calls"] as? [[String: Any]]
        )
        let encodedFunction = try #require(
            encodedCalls[0]["function"] as? [String: Any]
        )
        #expect(assistant["role"] as? String == "assistant")
        #expect(
            assistant["reasoning_content"] as? String ==
                "Need current facts first."
        )
        #expect(assistant["content"] == nil)
        #expect(encodedCalls[0]["id"] as? String == "call_lookup")
        #expect(encodedCalls[0]["type"] as? String == "function")
        #expect(encodedFunction["name"] as? String == "lookup_context")
        #expect(
            encodedFunction["arguments"] as? String ==
                #"{"task_id":"task-1"}"#
        )

        #expect(messages[1]["role"] as? String == "tool")
        #expect(messages[1]["tool_call_id"] as? String == "call_lookup")
        let tools = try #require(object["tools"] as? [[String: Any]])
        let definition = try #require(tools[0]["function"] as? [String: Any])
        let parameters = try #require(
            definition["parameters"] as? [String: Any]
        )
        #expect(tools[0]["type"] as? String == "function")
        #expect(definition["name"] as? String == "lookup_context")
        #expect(parameters["type"] as? String == "object")
        #expect(parameters["additionalProperties"] as? Bool == false)
    }

    @Test
    func toolRequestCanRequireToolChoiceWithoutResponseFormat() throws {
        let request = OpenAIChatCompletionRequest(
            model: "model",
            messages: [
                OpenAIChatMessage(role: "user", content: "Inspect the task."),
            ],
            temperature: 0,
            tools: [
                OpenAIChatToolDefinition(
                    function: .init(
                        name: "lookup_task",
                        description: "Read one task.",
                        parameters: .object([
                            "type": .string("object"),
                        ])
                    )
                ),
            ],
            toolChoice: "required"
        )

        let object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(request)
            ) as? [String: Any]
        )
        #expect(object["response_format"] == nil)
        #expect(object["tool_choice"] as? String == "required")
    }

    @Test
    func bufferedResponseDecodesAssistantToolCallsAndToolFinishReason() throws {
        let data = Data(
            """
            {
              "choices": [{
                "index": 3,
                "finish_reason": "tool_calls",
                "message": {
                  "role": "assistant",
                  "content": null,
                  "reasoning_content": "Need two reads.",
                  "tool_calls": [{
                    "id": "call_one",
                    "type": "function",
                    "function": {
                      "name": "lookup_context",
                      "arguments": "{\\"task_id\\":\\"task-1\\"}"
                    }
                  }]
                }
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(
            OpenAIChatCompletionResponse.self,
            from: data
        )
        let choice = try #require(response.choices.first)
        let call = try #require(choice.message.tool_calls?.first)
        #expect(choice.index == 3)
        #expect(choice.finish_reason == "tool_calls")
        #expect(choice.message.content == nil)
        #expect(choice.message.reasoning_content == "Need two reads.")
        #expect(call.id == "call_one")
        #expect(call.function.name == "lookup_context")
        #expect(call.function.arguments == #"{"task_id":"task-1"}"#)
    }

    @Test
    func fragmentedMultiToolCallsAccumulateByChoiceAndToolIndex() throws {
        var assembler = OpenAIChatToolCallDeltaAssembler()
        let chunks = try [
            Self.chunk(
                """
                {"choices":[
                  {"index":1,"delta":{
                    "role":"assistant",
                    "reasoning_content":"Choice one. ",
                    "tool_calls":[
                      {"index":1,"id":"call_b","type":"function",
                       "function":{"name":"lookup_category","arguments":"{\\"id\\":"}}
                    ]
                  }},
                  {"index":0,"delta":{
                    "role":"assistant",
                    "reasoning_content":"Choice zero. ",
                    "tool_calls":[
                      {"index":0,"id":"call_a","type":"function",
                       "function":{"name":"lookup_task","arguments":"{\\"id\\":"}}
                    ]
                  }}
                ]}
                """
            ),
            Self.chunk(
                """
                {"choices":[
                  {"index":1,"delta":{
                    "reasoning_content":"Continue.",
                    "tool_calls":[
                      {"index":0,"id":"call_c","type":"function",
                       "function":{"name":"lookup_checklist","arguments":"{\\"id\\":\\"c\\"}"}},
                      {"index":1,"function":{"arguments":"\\"b\\"}"}}
                    ]
                  }},
                  {"index":0,"delta":{
                    "content":"optional content",
                    "tool_calls":[
                      {"index":0,"function":{"arguments":"\\"a\\"}"}}
                    ]
                  }}
                ]}
                """
            ),
            Self.chunk(
                """
                {"choices":[
                  {"index":1,"delta":{},"finish_reason":"tool_calls"},
                  {"index":0,"delta":{},"finish_reason":"tool_calls"}
                ]}
                """
            ),
        ]

        for chunk in chunks {
            try assembler.ingest(chunk)
        }
        let choices = try assembler.finalize()

        #expect(choices.map(\.index) == [0, 1])
        #expect(choices[0].finishReason == "tool_calls")
        #expect(choices[0].assistantMessage.content == "optional content")
        #expect(
            choices[0].assistantMessage.reasoningContent == "Choice zero. "
        )
        #expect(
            choices[0].assistantMessage.toolCalls == [
                OpenAIChatToolCall(
                    id: "call_a",
                    type: "function",
                    function: .init(
                        name: "lookup_task",
                        arguments: #"{"id":"a"}"#
                    )
                ),
            ]
        )
        #expect(
            choices[1].assistantMessage.reasoningContent ==
                "Choice one. Continue."
        )
        #expect(
            choices[1].assistantMessage.toolCalls?.map(\.id) ==
                ["call_c", "call_b"]
        )
        #expect(
            choices[1].assistantMessage.toolCalls?.map(\.function.arguments) ==
                [#"{"id":"c"}"#, #"{"id":"b"}"#]
        )
    }

    @Test
    func unknownAndDuplicateToolFragmentsFailExplicitly() throws {
        var unknown = OpenAIChatToolCallDeltaAssembler()
        #expect(
            throws: OpenAIChatToolCallAssemblyError.unknownToolCallFragment(
                choiceIndex: 0,
                toolCallIndex: 0
            )
        ) {
            try unknown.ingest(
                Self.chunk(
                    """
                    {"choices":[{"index":0,"delta":{"tool_calls":[
                      {"index":0,"function":{"arguments":"{}"}}
                    ]}}]}
                    """
                )
            )
        }

        var duplicate = OpenAIChatToolCallDeltaAssembler()
        try duplicate.ingest(
            Self.chunk(
                """
                {"choices":[{"index":0,"delta":{"tool_calls":[
                  {"index":0,"id":"same","type":"function",
                   "function":{"name":"first","arguments":"{}"}},
                  {"index":1,"id":"same","type":"function",
                   "function":{"name":"second","arguments":"{}"}}
                ]},"finish_reason":"tool_calls"}]}
                """
            )
        )
        #expect(
            throws: OpenAIChatToolCallAssemblyError.duplicateToolCallID(
                choiceIndex: 0,
                id: "same"
            )
        ) {
            _ = try duplicate.finalize()
        }
    }

    @Test
    func missingMalformedAndUnknownCompletionStateFailExplicitly() throws {
        var missingID = OpenAIChatToolCallDeltaAssembler()
        try missingID.ingest(
            Self.chunk(
                """
                {"choices":[{"index":0,"delta":{"tool_calls":[
                  {"index":0,"type":"function",
                   "function":{"name":"lookup","arguments":"{}"}}
                ]},"finish_reason":"tool_calls"}]}
                """
            )
        )
        #expect(
            throws: OpenAIChatToolCallAssemblyError.missingToolCallField(
                choiceIndex: 0,
                toolCallIndex: 0,
                field: .id
            )
        ) {
            _ = try missingID.finalize()
        }

        var malformedArguments = OpenAIChatToolCallDeltaAssembler()
        try malformedArguments.ingest(
            Self.chunk(
                """
                {"choices":[{"index":0,"delta":{"tool_calls":[
                  {"index":0,"id":"bad","type":"function",
                   "function":{"name":"lookup","arguments":"not json"}}
                ]},"finish_reason":"tool_calls"}]}
                """
            )
        )
        #expect(
            throws: OpenAIChatToolCallAssemblyError.malformedToolCallArguments(
                choiceIndex: 0,
                toolCallIndex: 0
            )
        ) {
            _ = try malformedArguments.finalize()
        }

        var unknownFinish = OpenAIChatToolCallDeltaAssembler()
        try unknownFinish.ingest(
            Self.chunk(
                """
                {"choices":[{"index":0,"delta":{},"finish_reason":"mystery"}]}
                """
            )
        )
        #expect(
            throws: OpenAIChatToolCallAssemblyError.unknownFinishReason(
                choiceIndex: 0,
                reason: "mystery"
            )
        ) {
            _ = try unknownFinish.finalize()
        }

        var missingFinish = OpenAIChatToolCallDeltaAssembler()
        try missingFinish.ingest(
            Self.chunk(
                """
                {"choices":[{"index":0,"delta":{"content":"partial"}}]}
                """
            )
        )
        #expect(
            throws: OpenAIChatToolCallAssemblyError.missingFinishReason(
                choiceIndex: 0
            )
        ) {
            _ = try missingFinish.finalize()
        }
    }

    @Test
    func duplicateFinishAndDeltasAfterFinishAreRejected() throws {
        var duplicateFinish = OpenAIChatToolCallDeltaAssembler()
        try duplicateFinish.ingest(
            Self.chunk(
                """
                {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
                """
            )
        )
        #expect(
            throws: OpenAIChatToolCallAssemblyError.duplicateFinishReason(
                choiceIndex: 0
            )
        ) {
            try duplicateFinish.ingest(
                Self.chunk(
                    """
                    {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
                    """
                )
            )
        }

        var afterFinish = OpenAIChatToolCallDeltaAssembler()
        try afterFinish.ingest(
            Self.chunk(
                """
                {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
                """
            )
        )
        #expect(
            throws: OpenAIChatToolCallAssemblyError.deltaAfterFinish(
                choiceIndex: 0
            )
        ) {
            try afterFinish.ingest(
                Self.chunk(
                    """
                    {"choices":[{"index":0,"delta":{"content":"late"}}]}
                    """
                )
            )
        }
    }

    private static func chunk(
        _ json: String
    ) throws -> OpenAIChatCompletionStreamChunk {
        try JSONDecoder().decode(
            OpenAIChatCompletionStreamChunk.self,
            from: Data(json.utf8)
        )
    }
}
