import Foundation

/// Raw user-configured LLM connection settings, passed as a single value
/// through preferences → store → service instead of four loose parameters.
nonisolated struct LLMRequestConfiguration: Equatable, Sendable {
    let endpoint: String
    let apiKey: String
    let modelID: String
    let reasoningEffort: LLMReasoningEffort
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
