import Foundation
import OpenAI

/// Shared chat-completion plumbing for the two LLM suggestion services (inbox
/// routing + checklist visual). The per-kind prompt, response contract and
/// payload sanitization stay in each service; only the query/response shape
/// lives here.
nonisolated enum LLMSuggestionChatSupport {
    static func query(
        modelID: String,
        responseContract: String,
        configuration: LLMRequestConfiguration,
        promptJSON: String
    ) -> ChatQuery {
        ChatQuery(
            messages: [
                .system(.init(content: .textContent(responseContract))),
                .user(.init(content: .string(promptJSON))),
            ],
            model: modelID,
            reasoningEffort: configuration.reasoningEffort.chatQueryValue,
            responseFormat: .jsonObject
        )
    }

    static func contentData(_ result: ChatResult) throws -> Data {
        guard let content = result.choices.first?.message.content else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        return Data(content.utf8)
    }
}
