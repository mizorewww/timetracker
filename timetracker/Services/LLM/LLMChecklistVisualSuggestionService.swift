import Foundation

struct LLMChecklistVisualSuggestionResult: Equatable {
    let iconName: String
    let colorHex: String
    let reason: String
    let modelID: String
}

struct LLMChecklistVisualSuggestionService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { request in
        try await URLSession.shared.data(for: request)
    }

    func suggest(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String,
        endpoint: String,
        apiKey: String,
        modelID: String
    ) async throws -> LLMChecklistVisualSuggestionResult {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }

        let request = try suggestionRequest(
            checklistTitle: checklistTitle,
            taskTitle: taskTitle,
            taskPath: taskPath,
            endpoint: endpoint,
            apiKey: apiKey,
            modelID: modelID
        )
        let (data, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMModelServiceError.responseStatus(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenAIVisualChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
        let payload = try JSONDecoder().decode(ChecklistVisualSuggestionPayload.self, from: contentData)
        return Self.sanitize(payload: payload, modelID: modelID)
    }

    func suggestionRequest(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String,
        endpoint: String,
        apiKey: String,
        modelID: String
    ) throws -> URLRequest {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { throw LLMModelServiceError.missingEndpoint }
        guard !trimmedAPIKey.isEmpty else { throw LLMModelServiceError.missingAPIKey }
        guard let url = LLMInboxSuggestionService.chatCompletionsURL(endpoint: trimmedEndpoint) else {
            throw LLMModelServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            OpenAIVisualChatCompletionRequest(
                model: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
                messages: [
                    .init(
                        role: "system",
                        content: """
                        You choose a concise visual identity for one checklist item. Return only JSON with keys iconName, colorHex, reason. Use a valid SF Symbol from allowedSymbols exactly and a color from allowedColors exactly.
                        """
                    ),
                    .init(
                        role: "user",
                        content: prompt(
                            checklistTitle: checklistTitle,
                            taskTitle: taskTitle,
                            taskPath: taskPath
                        )
                    )
                ],
                temperature: 0.2,
                responseFormat: .init(type: "json_object")
            )
        )
        return request
    }

    static func sanitize(
        payload: ChecklistVisualSuggestionPayload,
        modelID: String
    ) -> LLMChecklistVisualSuggestionResult {
        LLMChecklistVisualSuggestionResult(
            iconName: ChecklistVisualSanitizer.sanitizedIcon(payload.iconName),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(payload.colorHex),
            reason: payload.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID: modelID
        )
    }

    private func prompt(
        checklistTitle: String,
        taskTitle: String,
        taskPath: String
    ) -> String {
        let payload = ChecklistVisualPromptPayload(
            checklistTitle: checklistTitle,
            taskTitle: taskTitle,
            taskPath: taskPath,
            allowedSymbols: SymbolCatalog.symbolNames,
            allowedColors: TaskColorPalette.hexValues
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return checklistTitle
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

private struct OpenAIVisualChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
}

private struct OpenAIVisualChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
