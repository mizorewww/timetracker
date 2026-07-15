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
        endpoint: String,
        apiKey: String,
        modelID: String
    ) async throws -> LLMChecklistVisualSuggestionResult {
        let input = LLMSuggestionInputPolicy.prepareChecklistVisual(
            checklistTitle: checklistTitle,
            taskTitle: taskTitle,
            taskPath: taskPath,
            modelID: modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }

        let request = try suggestionRequest(
            input: input,
            endpoint: endpoint,
            apiKey: apiKey
        )
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMModelServiceError.responseStatus(httpResponse.statusCode)
        }
        try LLMSecureHTTPTransport.validateBufferedResponse(data)

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(ChecklistVisualSuggestionPayload.self, from: contentData)
        return Self.sanitize(payload: payload, modelID: input.modelID)
    }

    func suggestionRequest(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String,
        endpoint: String,
        apiKey: String,
        modelID: String
    ) throws -> URLRequest {
        let input = LLMSuggestionInputPolicy.prepareChecklistVisual(
            checklistTitle: checklistTitle,
            taskTitle: taskTitle,
            taskPath: taskPath,
            modelID: modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }
        return try suggestionRequest(input: input, endpoint: endpoint, apiKey: apiKey)
    }

    private func suggestionRequest(
        input: LLMChecklistVisualSuggestionPreparedInput,
        endpoint: String,
        apiKey: String
    ) throws -> URLRequest {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { throw LLMModelServiceError.missingEndpoint }
        guard !trimmedAPIKey.isEmpty else { throw LLMModelServiceError.missingAPIKey }
        guard trimmedEndpoint.utf8.count <= LLMSuggestionInputPolicy.maximumEndpointByteCount,
              trimmedAPIKey.utf8.count <= LLMSuggestionInputPolicy.maximumAPIKeyByteCount else {
            throw LLMInboxSuggestionServiceError.requestTooLarge
        }
        guard let url = LLMInboxSuggestionService.chatCompletionsURL(endpoint: trimmedEndpoint) else {
            throw LLMModelServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: input.modelID,
                messages: [
                    .init(
                        role: "system",
                        content: """
                        You choose a concise visual identity for one checklist item. Return only JSON with keys iconName, colorHex, reason. Use a valid SF Symbol from allowedSymbols exactly and a color from allowedColors exactly.
                        """
                    ),
                    .init(
                        role: "user",
                        content: try prompt(input: input)
                    )
                ],
                temperature: 0.2,
                responseFormat: .init(type: "json_object")
            )
        )
        guard body.count <= LLMSuggestionInputPolicy.maximumRequestBodyByteCount else {
            throw LLMInboxSuggestionServiceError.requestTooLarge
        }
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
            modelID: LLMSuggestionInputPolicy.boundedTrimmedUTF8(
                modelID,
                maximumByteCount: LLMSuggestionInputPolicy.maximumModelIDByteCount
            )
        )
    }

    private func prompt(input: LLMChecklistVisualSuggestionPreparedInput) throws -> String {
        let payload = ChecklistVisualPromptPayload(
            checklistTitle: input.checklistTitle,
            taskTitle: input.taskTitle,
            taskPath: input.taskPath,
            allowedSymbols: SymbolCatalog.aiSuggestionSymbolNames,
            allowedColors: TaskColorPalette.hexValues
        )
        let data = try JSONEncoder().encode(payload)
        guard data.count <= LLMSuggestionInputPolicy.maximumPromptByteCount,
              let json = String(data: data, encoding: .utf8) else {
            throw LLMInboxSuggestionServiceError.requestTooLarge
        }
        return json
    }
}

struct ChecklistVisualSuggestionPayload: Codable, Equatable {
    let iconName: String
    let colorHex: String
    let reason: String
}

private struct ChecklistVisualPromptPayload: Encodable {
    let checklistTitle: String
    let taskTitle: String
    let taskPath: String
    let allowedSymbols: [String]
    let allowedColors: [String]
}
