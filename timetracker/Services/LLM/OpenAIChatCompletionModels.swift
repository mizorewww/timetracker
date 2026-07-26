import Foundation

nonisolated struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double?
    let responseFormat: OpenAIChatResponseFormat?
    var stream: Bool?
    var streamOptions: OpenAIChatStreamOptions?
    var tools: [OpenAIChatToolDefinition]?
    var toolChoice: String?
    var thinking: OpenAIChatThinkingConfiguration?
    var reasoningEffort: String?

    init(
        model: String,
        messages: [OpenAIChatMessage],
        temperature: Double?,
        responseFormat: OpenAIChatResponseFormat? = nil,
        stream: Bool? = nil,
        streamOptions: OpenAIChatStreamOptions? = nil,
        tools: [OpenAIChatToolDefinition]? = nil,
        toolChoice: String? = nil,
        thinking: OpenAIChatThinkingConfiguration? = nil,
        reasoningEffort: String? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.responseFormat = responseFormat
        self.stream = stream
        self.streamOptions = streamOptions
        self.tools = tools
        self.toolChoice = toolChoice
        self.thinking = thinking
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
        case stream
        case streamOptions = "stream_options"
        case tools
        case toolChoice = "tool_choice"
        case thinking
        case reasoningEffort = "reasoning_effort"
    }
}

nonisolated struct OpenAIChatThinkingConfiguration: Encodable {
    let type: String
}

nonisolated struct OpenAIChatMessage: Encodable, Equatable, Sendable {
    let role: String
    let content: String?
    let reasoningContent: String?
    let toolCalls: [OpenAIChatToolCall]?
    let toolCallID: String?

    init(
        role: String,
        content: String?,
        reasoningContent: String? = nil,
        toolCalls: [OpenAIChatToolCall]? = nil,
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case reasoningContent = "reasoning_content"
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

nonisolated struct OpenAIChatResponseFormat: Encodable {
    let type: String
}

nonisolated struct OpenAIChatStreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

nonisolated struct OpenAIChatCompletionResponse: Decodable, Sendable {
    nonisolated struct Choice: Decodable, Sendable {
        nonisolated struct Message: Decodable, Sendable {
            let role: String?
            let content: String?
            /// Reasoning-capable providers return the chain of thought beside
            /// the JSON answer; absent for ordinary models.
            let reasoning_content: String?
            let tool_calls: [OpenAIChatToolCall]?
        }

        let index: Int?
        let message: Message
        let finish_reason: String?
    }

    let choices: [Choice]
    let usage: OpenAIChatCompletionStreamChunk.Usage?
}
