import Foundation

/// Raw user-configured LLM connection settings, passed as a single value
/// through preferences → store → service instead of four loose parameters.
nonisolated struct LLMRequestConfiguration: Equatable, Sendable {
    let endpoint: String
    let apiKey: String
    let modelID: String
    let reasoningEffort: LLMReasoningEffort
}

nonisolated extension LLMClient {
    /// A connection is usable once the endpoint is valid, a key is set, and
    /// the selected model was listed by that endpoint.
    static func isConfigured(
        endpoint: String,
        apiKey: String,
        selectedModel: String,
        availableModels: [String]
    ) -> Bool {
        isValidEndpoint(endpoint) &&
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            availableModels.contains(selectedModel)
    }
}

extension AppPreferences {
    var isLLMConfigured: Bool {
        LLMClient.isConfigured(
            endpoint: llmEndpoint,
            apiKey: llmAPIKey,
            selectedModel: llmSelectedModel,
            availableModels: llmAvailableModelIDs
        )
    }

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
