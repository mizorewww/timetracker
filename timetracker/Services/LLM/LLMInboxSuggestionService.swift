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

nonisolated struct LLMCategoryCandidate: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let iconName: String
    let colorHex: String
}

nonisolated struct LLMInboxSuggestionResult: Equatable, Sendable {
    let destination: InboxManualRouteDestination
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
        taskCandidates: [LLMTaskCandidate],
        categoryCandidates: [LLMCategoryCandidate],
        instructions: String = LLMPromptKind.inboxRouting.defaultInstructions,
        endpoint: String,
        apiKey: String,
        modelID: String
    ) async throws -> LLMInboxSuggestionResult {
        let input = LLMSuggestionInputPolicy.prepare(
            inboxTitle: inboxTitle,
            taskCandidates: taskCandidates,
            categoryCandidates: categoryCandidates,
            modelID: modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }
        guard !input.taskCandidates.isEmpty || !input.categoryCandidates.isEmpty else {
            throw LLMInboxSuggestionServiceError.noTaskCandidates
        }

        let request = try suggestionRequest(
            input: input,
            instructions: instructions,
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

        do {
            let payload = try JSONDecoder().decode(InboxSuggestionPayload.self, from: contentData)
            return try Self.sanitize(
                payload: payload,
                taskCandidates: input.taskCandidates,
                categoryCandidates: input.categoryCandidates,
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
        taskCandidates: [LLMTaskCandidate],
        categoryCandidates: [LLMCategoryCandidate],
        instructions: String = LLMPromptKind.inboxRouting.defaultInstructions,
        endpoint: String,
        apiKey: String,
        modelID: String
    ) throws -> URLRequest {
        let input = LLMSuggestionInputPolicy.prepare(
            inboxTitle: inboxTitle,
            taskCandidates: taskCandidates,
            categoryCandidates: categoryCandidates,
            modelID: modelID
        )
        guard !input.modelID.isEmpty else {
            throw LLMInboxSuggestionServiceError.missingModel
        }
        guard !input.taskCandidates.isEmpty || !input.categoryCandidates.isEmpty else {
            throw LLMInboxSuggestionServiceError.noTaskCandidates
        }
        return try suggestionRequest(
            input: input,
            instructions: instructions,
            endpoint: endpoint,
            apiKey: apiKey
        )
    }

    private func suggestionRequest(
        input: LLMInboxSuggestionPreparedInput,
        instructions: String,
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
        let preparedInstructions = try AppPreferenceValueSanitizer
            .llmInboxSuggestionInstructions(instructions)

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
                        content: Self.responseContract
                    ),
                    .init(
                        role: "user",
                        content: try prompt(
                            input: input,
                            instructions: preparedInstructions
                        )
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
        taskCandidates: [LLMTaskCandidate],
        categoryCandidates: [LLMCategoryCandidate],
        modelID: String
    ) throws -> LLMInboxSuggestionResult {
        let boundedCandidates = LLMSuggestionInputPolicy.boundedDestinationCandidates(
            tasks: taskCandidates,
            categories: categoryCandidates
        )
        let taskCandidateByID = boundedCandidates.tasks.reduce(
            into: [UUID: LLMTaskCandidate]()
        ) { result, candidate in
            result[candidate.id] = candidate
        }
        let categoryCandidateByID = boundedCandidates.categories.reduce(
            into: [UUID: LLMCategoryCandidate]()
        ) { result, candidate in
            result[candidate.id] = candidate
        }
        guard let kind = InboxSuggestionDestinationKind(rawValue: payload.destinationKind),
              let destinationID = LLMSuggestionInputPolicy.sanitizedDestinationID(
                  payload.destinationID
              ) else {
            throw LLMInboxSuggestionServiceError.noValidTask
        }

        let destination: InboxManualRouteDestination
        let fallbackColor: String
        switch kind {
        case .childTask:
            guard let candidate = taskCandidateByID[destinationID] else {
                throw LLMInboxSuggestionServiceError.noValidTask
            }
            destination = .childTask(parentTaskID: destinationID)
            fallbackColor = candidate.colorHex
        case .category:
            guard let candidate = categoryCandidateByID[destinationID] else {
                throw LLMInboxSuggestionServiceError.noValidTask
            }
            destination = .category(categoryID: destinationID)
            fallbackColor = candidate.colorHex
        case .checklist:
            guard let candidate = taskCandidateByID[destinationID] else {
                throw LLMInboxSuggestionServiceError.noValidTask
            }
            destination = .checklist(taskID: destinationID)
            fallbackColor = candidate.colorHex
        }

        let iconName = LLMSuggestionInputPolicy.sanitizedSuggestedIcon(payload.iconName)
        let colorHex = LLMSuggestionInputPolicy.sanitizedSuggestedColor(
            payload.colorHex,
            fallback: fallbackColor
        )
        let reason = LLMSuggestionInputPolicy.sanitizedReason(payload.reason)
        return LLMInboxSuggestionResult(
            destination: destination,
            reason: reason,
            iconName: iconName,
            colorHex: colorHex,
            modelID: LLMSuggestionInputPolicy.boundedTrimmedUTF8(
                modelID,
                maximumByteCount: LLMSuggestionInputPolicy.maximumModelIDByteCount
            )
        )
    }

    private func prompt(
        input: LLMInboxSuggestionPreparedInput,
        instructions: String
    ) throws -> String {
        let payload = PromptPayload(
            instructions: instructions,
            inboxTitle: input.inboxTitle,
            allowedSymbols: SymbolCatalog.aiSuggestionSymbolNames,
            allowedColors: TaskColorPalette.hexValues,
            tasks: input.taskCandidates,
            categories: input.categoryCandidates
        )
        let data = try JSONEncoder().encode(payload)
        guard data.count <= LLMSuggestionInputPolicy.maximumPromptByteCount,
              let json = String(data: data, encoding: .utf8) else {
            throw LLMInboxSuggestionServiceError.requestTooLarge
        }
        return json
    }
}

private extension LLMInboxSuggestionService {
    static let responseContract = """
    Return only JSON with keys destinationKind, destinationID, reason, iconName, \
    colorHex. destinationKind must be childTask, category, or checklist. For \
    childTask and checklist, destinationID must exactly match an ID from tasks. \
    For category, destinationID must exactly match an ID from categories. Use \
    childTask to create a new child task, category to create a new root task in \
    that category, and checklist to create a checklist item in that task. Use an \
    SF Symbol from allowedSymbols and a color from allowedColors exactly.
    """
}

struct InboxSuggestionPayload: Codable, Equatable {
    let destinationKind: String
    let destinationID: String
    let reason: String
    let iconName: String
    let colorHex: String
}

private struct PromptPayload: Encodable {
    let instructions: String
    let inboxTitle: String
    let allowedSymbols: [String]
    let allowedColors: [String]
    let tasks: [LLMTaskCandidate]
    let categories: [LLMCategoryCandidate]
}
