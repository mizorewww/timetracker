import Foundation

nonisolated struct AITaskPlanDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var categories: [AITaskPlanCategoryDraft]
    var tasks: [AITaskPlanTaskDraft]
    var modelID: String

    init(
        id: UUID = UUID(),
        categories: [AITaskPlanCategoryDraft],
        tasks: [AITaskPlanTaskDraft],
        modelID: String
    ) {
        self.id = id
        self.categories = categories
        self.tasks = tasks
        self.modelID = modelID
    }
}

nonisolated struct AITaskPlanCategoryDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var iconName: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        title: String,
        iconName: String,
        colorHex: String
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

nonisolated struct AITaskPlanTaskDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var categoryID: UUID?
    var parentID: UUID?
    var title: String
    var notes: String
    var estimatedMinutes: Int?
    var iconName: String
    var colorHex: String
    var checklistItems: [AITaskPlanChecklistDraft]

    init(
        id: UUID = UUID(),
        categoryID: UUID? = nil,
        parentID: UUID? = nil,
        title: String,
        notes: String = "",
        estimatedMinutes: Int? = nil,
        iconName: String,
        colorHex: String,
        checklistItems: [AITaskPlanChecklistDraft] = []
    ) {
        self.id = id
        self.categoryID = categoryID
        self.parentID = parentID
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.iconName = iconName
        self.colorHex = colorHex
        self.checklistItems = checklistItems
    }
}

nonisolated struct AITaskPlanChecklistDraft: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var iconName: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        title: String,
        iconName: String,
        colorHex: String
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

enum LLMTaskPlanServiceError: LocalizedError, Equatable {
    case missingRequest
    case missingModel
    case requestTooLarge
    case instructionsTooLarge
    case responseContentTooLarge
    case invalidResponse
    case limitExceeded
    case duplicateReference
    case orphanReference
    case cycle
    case childCategory
    case noTasks
    case depthExceeded
    case invalidField

    var errorDescription: String? {
        switch self {
        case .missingRequest:
            AppStrings.localized("settings.llm.taskPlan.error.requestRequired")
        case .missingModel:
            AppStrings.localized("inbox.suggestion.error.missingModel")
        case .requestTooLarge:
            AppStrings.localized("settings.llm.taskPlan.error.requestTooLarge")
        case .instructionsTooLarge:
            AppStrings.localized("settings.llm.taskPlan.error.instructionsTooLarge")
        case .responseContentTooLarge:
            AppStrings.localized("settings.llm.taskPlan.error.responseTooLarge")
        case .invalidResponse:
            AppStrings.localized("settings.llm.taskPlan.error.invalidResponse")
        case .limitExceeded:
            AppStrings.localized("settings.llm.taskPlan.error.limitExceeded")
        case .duplicateReference:
            AppStrings.localized("settings.llm.taskPlan.error.duplicateReference")
        case .orphanReference:
            AppStrings.localized("settings.llm.taskPlan.error.orphanReference")
        case .cycle:
            AppStrings.localized("settings.llm.taskPlan.error.cycle")
        case .childCategory:
            AppStrings.localized("settings.llm.taskPlan.error.childCategory")
        case .noTasks:
            AppStrings.localized("settings.llm.taskPlan.error.noTasks")
        case .depthExceeded:
            AppStrings.localized("settings.llm.taskPlan.error.depthExceeded")
        case .invalidField:
            AppStrings.localized("settings.llm.taskPlan.error.invalidField")
        }
    }
}

struct LLMTaskPlanService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    static let maximumRequestByteCount = 4 * 1_024
    static let maximumInstructionsByteCount = 4 * 1_024
    static let maximumResponseContentByteCount = 128 * 1_024
    static let maximumCategoryCount = 8
    static let maximumTaskCount = 64
    static let maximumChecklistItemCountPerTask = 32
    static let maximumChecklistItemCount = 256
    /// Root tasks have depth zero. A task at depth six is accepted.
    static let maximumTaskDepth = 6

    var transport: Transport = { request in
        try await LLMSecureHTTPTransport.data(for: request)
    }

    func generate(
        request: String,
        instructions: String,
        endpoint: String,
        apiKey: String,
        modelID: String
    ) async throws -> AITaskPlanDraft {
        let generationRequest = try generationRequest(
            request: request,
            instructions: instructions,
            endpoint: endpoint,
            apiKey: apiKey,
            modelID: modelID
        )
        let (data, response) = try await transport(generationRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMTaskPlanServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LLMModelServiceError.responseStatus(httpResponse.statusCode)
        }
        try LLMSecureHTTPTransport.validateBufferedResponse(data)

        let decoded: OpenAIChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            throw LLMTaskPlanServiceError.invalidResponse
        }
        guard let content = decoded.choices.first?.message.content else {
            throw LLMTaskPlanServiceError.invalidResponse
        }
        guard content.utf8.count <= Self.maximumResponseContentByteCount else {
            throw LLMTaskPlanServiceError.responseContentTooLarge
        }

        let payload: AITaskPlanPayload
        do {
            payload = try JSONDecoder().decode(AITaskPlanPayload.self, from: Data(content.utf8))
        } catch {
            throw LLMTaskPlanServiceError.invalidResponse
        }
        return try Self.makeDraft(
            from: payload,
            modelID: Self.preparedModelID(modelID)
        )
    }

    func generationRequest(
        request: String,
        instructions: String,
        endpoint: String,
        apiKey: String,
        modelID: String
    ) throws -> URLRequest {
        let preparedRequest = try Self.preparedRequest(request)
        let preparedInstructions = try Self.preparedInstructions(instructions)
        let preparedModelID = Self.preparedModelID(modelID)
        guard !preparedModelID.isEmpty else {
            throw LLMTaskPlanServiceError.missingModel
        }

        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            throw LLMModelServiceError.missingEndpoint
        }
        guard !trimmedAPIKey.isEmpty else {
            throw LLMModelServiceError.missingAPIKey
        }
        guard trimmedEndpoint.utf8.count <= LLMSuggestionInputPolicy.maximumEndpointByteCount,
              trimmedAPIKey.utf8.count <= LLMSuggestionInputPolicy.maximumAPIKeyByteCount else {
            throw LLMTaskPlanServiceError.requestTooLarge
        }
        guard let url = LLMInboxSuggestionService.chatCompletionsURL(
            endpoint: trimmedEndpoint
        ) else {
            throw LLMModelServiceError.invalidEndpoint
        }

        let prompt = AITaskPlanPromptEnvelope(
            instructions: preparedInstructions,
            request: preparedRequest,
            allowedSymbols: SymbolCatalog.aiSuggestionSymbolNames,
            allowedColors: TaskColorPalette.hexValues
        )
        let promptData = try JSONEncoder().encode(prompt)
        guard promptData.count <= LLMSuggestionInputPolicy.maximumPromptByteCount,
              let promptJSON = String(data: promptData, encoding: .utf8) else {
            throw LLMTaskPlanServiceError.requestTooLarge
        }

        let body = try JSONEncoder().encode(
            OpenAIChatCompletionRequest(
                model: preparedModelID,
                messages: [
                    .init(role: "system", content: Self.systemContract),
                    .init(role: "user", content: promptJSON)
                ],
                temperature: 0.2,
                responseFormat: .init(type: "json_object")
            )
        )
        guard body.count <= LLMSuggestionInputPolicy.maximumRequestBodyByteCount else {
            throw LLMTaskPlanServiceError.requestTooLarge
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 45
        urlRequest.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = body
        return urlRequest
    }

    static func makeDraft(
        from payload: AITaskPlanPayload,
        modelID: String
    ) throws -> AITaskPlanDraft {
        guard !payload.tasks.isEmpty else {
            throw LLMTaskPlanServiceError.noTasks
        }
        guard payload.categories.count <= maximumCategoryCount,
              payload.tasks.count <= maximumTaskCount,
              payload.checklistItems.count <= maximumChecklistItemCount else {
            throw LLMTaskPlanServiceError.limitExceeded
        }

        let categoryReferences = try uniqueReferences(payload.categories.map(\.reference))
        let taskReferences = try uniqueReferences(payload.tasks.map(\.reference))
        _ = try uniqueReferences(payload.checklistItems.map(\.reference))

        let categoryIDByReference = Dictionary(
            uniqueKeysWithValues: categoryReferences.map { ($0, UUID()) }
        )
        let taskIDByReference = Dictionary(
            uniqueKeysWithValues: taskReferences.map { ($0, UUID()) }
        )

        var normalizedTaskRelationships: [
            String: (categoryReference: String?, parentReference: String?)
        ] = [:]
        normalizedTaskRelationships.reserveCapacity(payload.tasks.count)

        for (index, task) in payload.tasks.enumerated() {
            let reference = taskReferences[index]
            let categoryReference = try optionalReference(task.categoryReference)
            let parentReference = try optionalReference(task.parentReference)
            if parentReference != nil, categoryReference != nil {
                throw LLMTaskPlanServiceError.childCategory
            }
            if let categoryReference,
               categoryIDByReference[categoryReference] == nil {
                throw LLMTaskPlanServiceError.orphanReference
            }
            if let parentReference,
               taskIDByReference[parentReference] == nil {
                throw LLMTaskPlanServiceError.orphanReference
            }
            normalizedTaskRelationships[reference] = (
                categoryReference: categoryReference,
                parentReference: parentReference
            )
        }

        try validateTaskGraph(normalizedTaskRelationships)

        var checklistPayloadByTaskReference: [String: [AITaskPlanChecklistPayload]] = [:]
        checklistPayloadByTaskReference.reserveCapacity(payload.tasks.count)
        for checklistItem in payload.checklistItems {
            let taskReference = try requiredReference(checklistItem.taskReference)
            guard taskIDByReference[taskReference] != nil else {
                throw LLMTaskPlanServiceError.orphanReference
            }
            checklistPayloadByTaskReference[taskReference, default: []].append(checklistItem)
            if checklistPayloadByTaskReference[taskReference, default: []].count >
                maximumChecklistItemCountPerTask {
                throw LLMTaskPlanServiceError.limitExceeded
            }
        }

        let categories: [AITaskPlanCategoryDraft]
        do {
            categories = try zip(payload.categories, categoryReferences).map { category, reference in
                let iconName = sanitizedIcon(category.iconName)
                let colorHex = sanitizedColor(category.colorHex)
                let prepared = try TaskPersistencePolicy.prepareCategory(
                    title: category.title,
                    colorHex: colorHex,
                    iconName: iconName
                )
                return AITaskPlanCategoryDraft(
                    id: categoryIDByReference[reference]!,
                    title: prepared.title,
                    iconName: prepared.iconName ?? ChecklistVisualSanitizer.defaultIcon,
                    colorHex: prepared.colorHex ?? ChecklistVisualSanitizer.defaultColor
                )
            }
        } catch {
            throw LLMTaskPlanServiceError.invalidField
        }

        let tasks: [AITaskPlanTaskDraft]
        do {
            tasks = try zip(payload.tasks, taskReferences).map { task, reference in
                guard let relationship = normalizedTaskRelationships[reference] else {
                    throw LLMTaskPlanServiceError.invalidResponse
                }
                let iconName = sanitizedIcon(task.iconName)
                let colorHex = sanitizedColor(task.colorHex)
                let prepared = try TaskPersistencePolicy.prepareTask(
                    title: task.title,
                    colorHex: colorHex,
                    iconName: iconName,
                    notes: task.notes
                )
                let checklistItems = try (checklistPayloadByTaskReference[reference] ?? []).map {
                    try preparedChecklistDraft(from: $0)
                }
                return AITaskPlanTaskDraft(
                    id: taskIDByReference[reference]!,
                    categoryID: relationship.categoryReference.flatMap {
                        categoryIDByReference[$0]
                    },
                    parentID: relationship.parentReference.flatMap {
                        taskIDByReference[$0]
                    },
                    title: prepared.title,
                    notes: prepared.notes ?? "",
                    estimatedMinutes: try preparedEstimatedMinutes(task.estimatedMinutes),
                    iconName: prepared.iconName ?? ChecklistVisualSanitizer.defaultIcon,
                    colorHex: prepared.colorHex ?? ChecklistVisualSanitizer.defaultColor,
                    checklistItems: checklistItems
                )
            }
        } catch let error as LLMTaskPlanServiceError {
            throw error
        } catch {
            throw LLMTaskPlanServiceError.invalidField
        }

        return AITaskPlanDraft(
            categories: categories,
            tasks: tasks,
            modelID: modelID
        )
    }
}

nonisolated struct AITaskPlanPayload: Decodable, Equatable, Sendable {
    let categories: [AITaskPlanCategoryPayload]
    let tasks: [AITaskPlanTaskPayload]
    let checklistItems: [AITaskPlanChecklistPayload]
}

nonisolated struct AITaskPlanCategoryPayload: Decodable, Equatable, Sendable {
    let reference: String
    let title: String
    let iconName: String
    let colorHex: String
}

nonisolated struct AITaskPlanTaskPayload: Decodable, Equatable, Sendable {
    let reference: String
    let categoryReference: String?
    let parentReference: String?
    let title: String
    let notes: String?
    let estimatedMinutes: Int?
    let iconName: String
    let colorHex: String
}

nonisolated struct AITaskPlanChecklistPayload: Decodable, Equatable, Sendable {
    let reference: String
    let taskReference: String
    let title: String
    let iconName: String
    let colorHex: String
}

private nonisolated struct AITaskPlanPromptEnvelope: Encodable {
    let instructions: String
    let request: String
    let allowedSymbols: [String]
    let allowedColors: [String]
}

private extension LLMTaskPlanService {
    static let maximumReferenceByteCount =
        SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount

    static let systemContract = """
    You generate an editable Time Tracker plan draft. Return only one JSON \
    object with exactly three flat arrays: categories, tasks, and \
    checklistItems.

    Category object: reference, title, iconName, colorHex.
    Task object: reference, categoryReference, parentReference, title, notes, \
    estimatedMinutes, iconName, colorHex.
    Checklist object: reference, taskReference, title, iconName, colorHex.

    References are opaque strings. Each reference must be nonempty and unique \
    within its array. A task parentReference must name another task. A \
    checklist taskReference must name a task. A task categoryReference must \
    name a category. Only root tasks may have categoryReference; child tasks \
    must use null. The task graph must be acyclic and contain at least one \
    task. Root task depth is zero and maximum task depth is 6.

    Limits: at most 8 categories, 64 tasks, 32 checklist items per task, and \
    256 checklist items total. estimatedMinutes is null or an integer from 0 \
    through 600. notes is null or plain text. Use iconName from \
    allowedSymbols exactly and colorHex from allowedColors exactly. Do not \
    include Markdown fences, commentary, generated UUIDs, or nested task \
    objects.
    """

    static func preparedRequest(_ value: String) throws -> String {
        let prepared = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prepared.isEmpty else {
            throw LLMTaskPlanServiceError.missingRequest
        }
        guard prepared.utf8.count <= maximumRequestByteCount else {
            throw LLMTaskPlanServiceError.requestTooLarge
        }
        return prepared
    }

    static func preparedInstructions(_ value: String) throws -> String {
        do {
            return try AppPreferenceValueSanitizer.llmTaskPlanInstructions(value)
        } catch let error as LLMTaskPlanInstructionsValidationError {
            switch error {
            case .controlCharacter:
                throw LLMTaskPlanServiceError.invalidField
            case .byteLimitExceeded:
                throw LLMTaskPlanServiceError.instructionsTooLarge
            }
        } catch {
            throw LLMTaskPlanServiceError.invalidField
        }
    }

    static func preparedModelID(_ value: String) -> String {
        LLMSuggestionInputPolicy.boundedTrimmedUTF8(
            value,
            maximumByteCount: LLMSuggestionInputPolicy.maximumModelIDByteCount
        )
    }

    static func uniqueReferences(_ values: [String]) throws -> [String] {
        var references: [String] = []
        references.reserveCapacity(values.count)
        var seen = Set<String>()
        for value in values {
            let reference = try requiredReference(value)
            guard seen.insert(reference).inserted else {
                throw LLMTaskPlanServiceError.duplicateReference
            }
            references.append(reference)
        }
        return references
    }

    static func requiredReference(_ value: String) throws -> String {
        let reference = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !reference.isEmpty,
              reference.utf8.count <= maximumReferenceByteCount,
              !reference.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw LLMTaskPlanServiceError.invalidField
        }
        return reference
    }

    static func optionalReference(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try requiredReference(trimmed)
    }

    static func validateTaskGraph(
        _ relationships: [String: (categoryReference: String?, parentReference: String?)]
    ) throws {
        enum VisitState {
            case visiting
            case visited
        }

        var states: [String: VisitState] = [:]
        var depthByReference: [String: Int] = [:]

        func depth(for reference: String) throws -> Int {
            if let depth = depthByReference[reference] {
                return depth
            }
            if states[reference] == .visiting {
                throw LLMTaskPlanServiceError.cycle
            }
            guard let relationship = relationships[reference] else {
                throw LLMTaskPlanServiceError.orphanReference
            }

            states[reference] = .visiting
            let resolvedDepth: Int
            if let parentReference = relationship.parentReference {
                resolvedDepth = try depth(for: parentReference) + 1
            } else {
                resolvedDepth = 0
            }
            guard resolvedDepth <= maximumTaskDepth else {
                throw LLMTaskPlanServiceError.depthExceeded
            }
            states[reference] = .visited
            depthByReference[reference] = resolvedDepth
            return resolvedDepth
        }

        for reference in relationships.keys {
            _ = try depth(for: reference)
        }
    }

    static func sanitizedIcon(_ iconName: String) -> String {
        LLMSuggestionInputPolicy.sanitizedSuggestedIcon(iconName)
    }

    static func sanitizedColor(_ colorHex: String) -> String {
        LLMSuggestionInputPolicy.sanitizedSuggestedColor(
            colorHex,
            fallback: ChecklistVisualSanitizer.defaultColor
        )
    }

    static func preparedChecklistDraft(
        from payload: AITaskPlanChecklistPayload
    ) throws -> AITaskPlanChecklistDraft {
        let prepared = try ChecklistDraftPersistencePolicy.prepare([
            ChecklistEditorDraft(
                title: payload.title,
                iconName: sanitizedIcon(payload.iconName),
                colorHex: sanitizedColor(payload.colorHex)
            )
        ])[0]
        return AITaskPlanChecklistDraft(
            title: prepared.title,
            iconName: prepared.iconName,
            colorHex: prepared.colorHex
        )
    }

    static func preparedEstimatedMinutes(_ minutes: Int?) throws -> Int? {
        guard let minutes else { return nil }
        guard TaskEstimatePolicy.minuteRange.contains(minutes) else {
            throw LLMTaskPlanServiceError.invalidField
        }
        return TaskEstimatePolicy.seconds(fromMinutes: minutes).map { $0 / 60 }
    }
}
