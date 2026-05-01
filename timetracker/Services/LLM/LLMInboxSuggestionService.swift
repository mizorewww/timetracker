import Foundation

enum LLMInboxSuggestionServiceError: LocalizedError, Equatable {
    case missingModel
    case noTaskCandidates
    case invalidResponse
    case noValidTask

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return AppStrings.localized("inbox.suggestion.error.missingModel")
        case .noTaskCandidates:
            return AppStrings.localized("inbox.suggestion.error.noTaskCandidates")
        case .invalidResponse:
            return AppStrings.localized("settings.llm.error.invalidResponse")
        case .noValidTask:
            return AppStrings.localized("inbox.suggestion.error.noValidTask")
        }
    }
}

struct LLMTaskCandidate: Encodable, Equatable {
    let id: UUID
    let title: String
    let path: String
    let iconName: String
    let colorHex: String
}

struct LLMInboxSuggestionResult: Equatable {
    let taskID: UUID
    let reason: String
    let iconName: String
    let colorHex: String
    let modelID: String
}

struct LLMInboxSuggestionService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { request in
        try await URLSession.shared.data(for: request)
    }

    func suggest(
        inboxTitle: String,
        candidates: [LLMTaskCandidate],
        endpoint: String,
        apiKey: String,
        modelID: String
    ) async throws -> LLMInboxSuggestionResult {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }
        guard !candidates.isEmpty else {
            throw LLMInboxSuggestionServiceError.noTaskCandidates
        }

        let request = try suggestionRequest(
            inboxTitle: inboxTitle,
            candidates: candidates,
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

        let decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              let contentData = content.data(using: .utf8) else {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }

        let payload = try JSONDecoder().decode(InboxSuggestionPayload.self, from: contentData)
        return try Self.sanitize(payload: payload, candidates: candidates, modelID: modelID)
    }

    func suggestionRequest(
        inboxTitle: String,
        candidates: [LLMTaskCandidate],
        endpoint: String,
        apiKey: String,
        modelID: String
    ) throws -> URLRequest {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else { throw LLMModelServiceError.missingEndpoint }
        guard !trimmedAPIKey.isEmpty else { throw LLMModelServiceError.missingAPIKey }
        guard let url = Self.chatCompletionsURL(endpoint: trimmedEndpoint) else {
            throw LLMModelServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
                messages: [
                    .init(
                        role: "system",
                        content: """
                        You classify inbox checklist items into one existing task. Return only JSON with keys taskID, reason, iconName, colorHex. Use one of the provided task IDs exactly. Use a valid SF Symbol from the allowedSymbols list and a color from allowedColors exactly.
                        """
                    ),
                    .init(
                        role: "user",
                        content: prompt(
                            inboxTitle: inboxTitle,
                            candidates: candidates
                        )
                    )
                ],
                temperature: 0.2,
                responseFormat: .init(type: "json_object")
            )
        )
        return request
    }

    static func chatCompletionsURL(endpoint: String) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/models") {
            path.removeLast("/models".count)
        }
        if !path.hasSuffix("/chat/completions") {
            path += "/chat/completions"
        }
        components.path = path
        return components.url
    }

    static func sanitize(
        payload: InboxSuggestionPayload,
        candidates: [LLMTaskCandidate],
        modelID: String
    ) throws -> LLMInboxSuggestionResult {
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        guard let taskID = UUID(uuidString: payload.taskID),
              let candidate = candidateByID[taskID] else {
            throw LLMInboxSuggestionServiceError.noValidTask
        }

        let iconName = ChecklistVisualSanitizer.sanitizedIcon(payload.iconName)
        let colorHex = ChecklistVisualSanitizer.sanitizedColor(payload.colorHex, fallback: candidate.colorHex)
        let reason = payload.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMInboxSuggestionResult(
            taskID: taskID,
            reason: reason,
            iconName: iconName,
            colorHex: colorHex,
            modelID: modelID
        )
    }

    private func prompt(inboxTitle: String, candidates: [LLMTaskCandidate]) -> String {
        let allowedSymbols = Array(SymbolCatalog.symbolNames.prefix(400))
        let payload = PromptPayload(
            inboxTitle: inboxTitle,
            allowedSymbols: allowedSymbols,
            allowedColors: TaskColorPalette.hexValues,
            tasks: candidates
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return inboxTitle
        }
        return json
    }
}

struct InboxSuggestionPayload: Codable, Equatable {
    let taskID: String
    let reason: String
    let iconName: String
    let colorHex: String
}

private struct PromptPayload: Encodable {
    let inboxTitle: String
    let allowedSymbols: [String]
    let allowedColors: [String]
    let tasks: [LLMTaskCandidate]
}

private struct OpenAIChatCompletionRequest: Encodable {
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

private struct OpenAIChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }

        let message: Message
    }

    let choices: [Choice]
}
