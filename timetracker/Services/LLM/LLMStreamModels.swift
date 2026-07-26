import Foundation

/// One server-sent-events chunk of an OpenAI-compatible streaming chat
/// completion. Reasoning-capable providers (e.g. DeepSeek) stream the chain
/// of thought in `reasoning_content` alongside the regular `content` delta;
/// a final chunk may carry token `usage` when the request opted in via
/// `stream_options.include_usage`.
nonisolated struct OpenAIChatCompletionStreamChunk: Decodable, Sendable {
    nonisolated struct Choice: Decodable, Sendable {
        nonisolated struct Delta: Decodable, Sendable {
            nonisolated struct ToolCall: Decodable, Sendable {
                nonisolated struct Function: Decodable, Sendable {
                    let name: String?
                    let arguments: String?
                }

                let index: Int
                let id: String?
                let type: String?
                let function: Function?
            }

            let role: String?
            let content: String?
            let reasoning_content: String?
            let tool_calls: [ToolCall]?

            var hasPayload: Bool {
                role != nil ||
                    content != nil ||
                    reasoning_content != nil ||
                    tool_calls?.isEmpty == false
            }
        }

        let index: Int
        let delta: Delta?
        let finish_reason: String?
    }

    nonisolated struct Usage: Decodable, Sendable, Equatable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }

    let choices: [Choice]
    let usage: Usage?
}

/// Provider-agnostic events surfaced while a streaming generation runs.
enum LLMGenerationStreamEvent: Sendable, Equatable {
    case contentDelta(String)
    case reasoningDelta(String)
    case usage(OpenAIChatCompletionStreamChunk.Usage)
}

/// Live progress snapshot for the generation UI. Exact token counts are only
/// available when the provider reports usage; until then the estimate assumes
/// roughly four characters per token so the user can tell the model is alive.
struct LLMGenerationProgress: Sendable, Equatable {
    var contentCharacterCount: Int
    var reasoningCharacterCount: Int
    var reportedCompletionTokens: Int?

    var displayedOutputTokens: Int {
        if let reportedCompletionTokens {
            return reportedCompletionTokens
        }
        return (contentCharacterCount + reasoningCharacterCount) / 4
    }
}
