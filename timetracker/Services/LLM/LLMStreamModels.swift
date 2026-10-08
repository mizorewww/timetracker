import Foundation

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
