import Foundation

/// Raw user-configured LLM connection settings, passed as a single value
/// through preferences → store → service instead of four loose parameters.
nonisolated struct LLMRequestConfiguration: Equatable, Sendable {
    let endpoint: String
    let apiKey: String
    let modelID: String
    let reasoningEffort: LLMReasoningEffort

    /// Endpoint and credentials after the shared trim, presence, byte-ceiling,
    /// and endpoint-policy checks every chat request builder applies.
    struct Validated {
        let endpoint: String
        let apiKey: String
        let chatCompletionsURL: URL
    }

    /// - Parameter requestTooLarge: the caller-specific error thrown when the
    ///   endpoint or API key exceeds the shared byte ceiling.
    func validated(requestTooLarge: @autoclosure () -> Error) throws -> Validated {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { throw LLMModelServiceError.missingEndpoint }
        guard !trimmedAPIKey.isEmpty else { throw LLMModelServiceError.missingAPIKey }
        guard trimmedEndpoint.utf8.count <= LLMSuggestionInputPolicy.maximumEndpointByteCount,
              trimmedAPIKey.utf8.count <= LLMSuggestionInputPolicy.maximumAPIKeyByteCount
        else {
            throw requestTooLarge()
        }
        guard let url = LLMInboxSuggestionService.chatCompletionsURL(endpoint: trimmedEndpoint) else {
            throw LLMModelServiceError.invalidEndpoint
        }
        return Validated(
            endpoint: trimmedEndpoint,
            apiKey: trimmedAPIKey,
            chatCompletionsURL: url
        )
    }
}

extension AppPreferences {
    /// Current connection settings as a single request configuration value.
    var llmRequestConfiguration: LLMRequestConfiguration {
        LLMRequestConfiguration(
            endpoint: llmEndpoint,
            apiKey: llmAPIKey,
            modelID: llmSelectedModel,
            reasoningEffort: llmReasoningEffort
        )
    }
}
