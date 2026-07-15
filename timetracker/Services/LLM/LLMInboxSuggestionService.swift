import Foundation

enum LLMInboxSuggestionServiceError: LocalizedError, Equatable {
    case missingModel
    case noTaskCandidates
    case requestTooLarge
    case invalidResponse
    case noValidTask

    var errorDescription: String? {
        switch self {
        case .missingModel:
            return AppStrings.localized("inbox.suggestion.error.missingModel")
        case .noTaskCandidates:
            return AppStrings.localized("inbox.suggestion.error.noTaskCandidates")
        case .requestTooLarge:
            return AppStrings.localized("inbox.suggestion.error.requestTooLarge")
        case .invalidResponse:
            return AppStrings.localized("settings.llm.error.invalidResponse")
        case .noValidTask:
            return AppStrings.localized("inbox.suggestion.error.noValidTask")
        }
    }
}

nonisolated struct LLMTaskCandidate: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let path: String
    let iconName: String
    let colorHex: String
}

nonisolated struct LLMInboxSuggestionResult: Equatable, Sendable {
    let taskID: UUID
    let reason: String
    let iconName: String
    let colorHex: String
    let modelID: String
}

struct LLMInboxSuggestionService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    var transport: Transport = { request in
        try await LLMSecureHTTPTransport.data(for: request)
    }

    func suggest(
        inboxTitle: String,
        candidates: [LLMTaskCandidate],
        endpoint: String,
        apiKey: String,
        modelID: String
    ) async throws -> LLMInboxSuggestionResult {
        let input = LLMSuggestionInputPolicy.prepare(
            inboxTitle: inboxTitle,
            candidates: candidates,
            modelID: modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }
        guard !input.candidates.isEmpty else {
            throw LLMInboxSuggestionServiceError.noTaskCandidates
        }

        let request = try suggestionRequest(
            input: input,
            endpoint: endpoint,
            apiKey: apiKey
        )
        let (data, response) = try await transport(request)
        try LLMSecureHTTPTransport.validateBufferedResponse(data)
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

        do {
            let payload = try JSONDecoder().decode(InboxSuggestionPayload.self, from: contentData)
            return try Self.sanitize(
                payload: payload,
                candidates: input.candidates,
                modelID: input.modelID
            )
        } catch let error as LLMInboxSuggestionServiceError {
            throw error
        } catch {
            throw LLMInboxSuggestionServiceError.invalidResponse
        }
    }

    func suggestionRequest(
        inboxTitle: String,
        candidates: [LLMTaskCandidate],
        endpoint: String,
        apiKey: String,
        modelID: String
    ) throws -> URLRequest {
        let input = LLMSuggestionInputPolicy.prepare(
            inboxTitle: inboxTitle,
            candidates: candidates,
            modelID: modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }
        guard !input.candidates.isEmpty else {
            throw LLMInboxSuggestionServiceError.noTaskCandidates
        }
        return try suggestionRequest(input: input, endpoint: endpoint, apiKey: apiKey)
    }

    private func suggestionRequest(
        input: LLMInboxSuggestionPreparedInput,
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
        guard let url = Self.chatCompletionsURL(endpoint: trimmedEndpoint) else {
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
                        You classify inbox checklist items into one existing task. Return only JSON with keys taskID, reason, iconName, colorHex. Use one of the provided task IDs exactly. Use a valid SF Symbol from the allowedSymbols list and a color from allowedColors exactly.
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

    static func chatCompletionsURL(endpoint: String) -> URL? {
        guard var components = LLMModelService.validatedEndpointComponents(endpoint) else {
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
        let boundedCandidates = LLMSuggestionInputPolicy.boundedCandidates(candidates)
        let candidateByID = boundedCandidates.reduce(into: [UUID: LLMTaskCandidate]()) { result, candidate in
            result[candidate.id] = candidate
        }
        guard let taskID = LLMSuggestionInputPolicy.sanitizedTaskID(payload.taskID),
              let candidate = candidateByID[taskID] else {
            throw LLMInboxSuggestionServiceError.noValidTask
        }

        let iconName = LLMSuggestionInputPolicy.sanitizedSuggestedIcon(payload.iconName)
        let colorHex = LLMSuggestionInputPolicy.sanitizedSuggestedColor(
            payload.colorHex,
            fallback: candidate.colorHex
        )
        let reason = LLMSuggestionInputPolicy.sanitizedReason(payload.reason)
        return LLMInboxSuggestionResult(
            taskID: taskID,
            reason: reason,
            iconName: iconName,
            colorHex: colorHex,
            modelID: LLMSuggestionInputPolicy.boundedTrimmedUTF8(
                modelID,
                maximumByteCount: LLMSuggestionInputPolicy.maximumModelIDByteCount
            )
        )
    }

    private func prompt(input: LLMInboxSuggestionPreparedInput) throws -> String {
        let payload = PromptPayload(
            inboxTitle: input.inboxTitle,
            allowedSymbols: SymbolCatalog.aiSuggestionSymbolNames,
            allowedColors: TaskColorPalette.hexValues,
            tasks: input.candidates
        )
        let data = try JSONEncoder().encode(payload)
        guard data.count <= LLMSuggestionInputPolicy.maximumPromptByteCount,
              let json = String(data: data, encoding: .utf8) else {
            throw LLMInboxSuggestionServiceError.requestTooLarge
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
