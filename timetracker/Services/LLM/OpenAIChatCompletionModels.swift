import Foundation

struct OpenAIChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
    let responseFormat: OpenAIChatResponseFormat
    var stream: Bool?
    var streamOptions: OpenAIChatStreamOptions?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
        case stream
        case streamOptions = "stream_options"
    }
}

struct OpenAIChatMessage: Encodable {
    let role: String
    let content: String
}

struct OpenAIChatResponseFormat: Encodable {
    let type: String
}

struct OpenAIChatStreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
            /// Reasoning-capable providers return the chain of thought beside
            /// the JSON answer; absent for ordinary models.
            let reasoning_content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}
