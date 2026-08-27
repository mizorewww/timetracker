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
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw LLMModelServiceError.responseStatus(httpResponse.statusCode)
        }
        try LLMSecureHTTPTransport.validateBufferedResponse(data)

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8)
        else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(ChecklistVisualSuggestionPayload.self, from: contentData)
        return Self.sanitize(payload: payload, modelID: input.modelID)
    }

    func suggestionRequest(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String,
        instructions: String = LLMPromptKind.checklistVisual.defaultInstructions,
        configuration: LLMRequestConfiguration
    ) throws -> URLRequest {
        let input = LLMSuggestionInputPolicy.prepareChecklistVisual(
            checklistTitle: checklistTitle,
            taskTitle: taskTitle,
            taskPath: taskPath,
            modelID: configuration.modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }
        return try suggestionRequest(
            input: input,
            instructions: instructions,
            configuration: configuration
        )
    }

    private func suggestionRequest(
        input: LLMChecklistVisualSuggestionPreparedInput,
        instructions: String,
        configuration: LLMRequestConfiguration
    ) throws -> URLRequest {
        let credentials = try configuration.validated(
            requestTooLarge: LLMInboxSuggestionServiceError.requestTooLarge
        )
        let preparedInstructions = try AppPreferenceValueSanitizer
            .llmChecklistVisualInstructions(instructions)

        var request = URLRequest(url: credentials.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: input.modelID,
                messages: [
                    .init(
                        role: "system",
                        content: Self.responseContract
                    ),
                    .init(
                        role: "user",
                        content: prompt(
                            input: input,
                            instructions: preparedInstructions
                        )
                    ),
                ],
                temperature: LLMChatRequestPolicy.temperature(
                    modelID: input.modelID,
                    fallback: LLMChatRequestPolicy.suggestionTemperature
                ),
                responseFormat: .init(type: "json_object"),
                thinking: LLMChatRequestPolicy.thinkingConfiguration(
                    modelID: input.modelID
                ),
                reasoningEffort: LLMChatRequestPolicy.reasoningEffort(
                    modelID: input.modelID,
                    selected: configuration.reasoningEffort
                )
            )
        )
        request.httpBody = body
        return request
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
