import Foundation

nonisolated struct LLMChecklistVisualSuggestionResult: Equatable, Sendable {
    let iconName: String
    let colorHex: String
    let reason: String
    let modelID: String
}

struct LLMChecklistVisualSuggestionService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { request in
        try await LLMSecureHTTPTransport.data(for: request)
    }

    func suggest(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String,
        instructions: String = LLMPromptKind.checklistVisual.defaultInstructions,
        configuration: LLMRequestConfiguration
    ) async throws -> LLMChecklistVisualSuggestionResult {
        let input = LLMSuggestionInputPolicy.prepareChecklistVisual(
            checklistTitle: checklistTitle,
            taskTitle: taskTitle,
            taskPath: taskPath,
            modelID: configuration.modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }

        let request = try suggestionRequest(
            input: input,
            instructions: instructions,
            configuration: configuration
        )
        let contentData = try await LLMSuggestionChatSupport.contentData(
            for: request,
            transport: transport
        )
        let payload = try JSONDecoder().decode(ChecklistVisualSuggestionPayload.self, from: contentData)
        return Self.sanitize(payload: payload, modelID: input.modelID)
    }

    private func suggestionRequest(
        input: LLMChecklistVisualSuggestionPreparedInput,
        instructions: String,
        configuration: LLMRequestConfiguration
    ) throws -> URLRequest {
        try LLMSuggestionChatSupport.request(
            modelID: input.modelID,
            responseContract: Self.responseContract,
            configuration: configuration
        ) {
            try prompt(
                input: input,
                instructions: AppPreferenceValueSanitizer
                    .llmChecklistVisualInstructions(instructions)
            )
        }
    }

    static func sanitize(
        payload: ChecklistVisualSuggestionPayload,
        modelID: String
    ) -> LLMChecklistVisualSuggestionResult {
        LLMChecklistVisualSuggestionResult(
            iconName: LLMSuggestionInputPolicy.sanitizedSuggestedIcon(payload.iconName),
            colorHex: LLMSuggestionInputPolicy.sanitizedSuggestedColor(
                payload.colorHex,
                fallback: ChecklistVisualSanitizer.defaultColor
            ),
            reason: LLMSuggestionInputPolicy.sanitizedReason(payload.reason),
            modelID: AppPreferenceValueSanitizer.llmModelID(modelID)
        )
    }

    private func prompt(
        input: LLMChecklistVisualSuggestionPreparedInput,
        instructions: String
    ) throws -> String {
        let payload = ChecklistVisualPromptPayload(
            instructions: instructions,
            checklistTitle: input.checklistTitle,
            taskTitle: input.taskTitle,
            taskPath: input.taskPath,
            allowedSymbols: SymbolCatalog.symbolNames,
            allowedColors: TaskColorPalette.hexValues
        )
        let data = try JSONEncoder().encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        return json
    }
}

extension LLMChecklistVisualSuggestionService {
    static let responseContract = """
    Return only JSON with keys iconName, colorHex, reason. Use an SF Symbol from \
    allowedSymbols exactly and a color from allowedColors exactly.
    """
}

struct ChecklistVisualSuggestionPayload: Codable, Equatable {
    let iconName: String
    let colorHex: String
    let reason: String
}

private struct ChecklistVisualPromptPayload: Encodable {
    let instructions: String
    let checklistTitle: String
    let taskTitle: String
    let taskPath: String
    let allowedSymbols: [String]
    let allowedColors: [String]
}
