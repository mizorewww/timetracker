import Foundation
import OpenAI

nonisolated enum AITaskWorkspaceToolName: String, CaseIterable, Sendable {
    case listWorkspace = "list_workspace"
    case getCategory = "get_category"
    case getTask = "get_task"
    case getChecklistItem = "get_checklist_item"
    case useExistingCategory = "use_existing_category"
    case createCategory = "create_category"
    case updateCategory = "update_category"
    case deleteCategory = "delete_category"
    case createTask = "create_task"
    case updateTask = "update_task"
    case archiveTask = "archive_task"
    case createChecklistItem = "create_checklist_item"
    case updateChecklistItem = "update_checklist_item"
    case deleteChecklistItem = "delete_checklist_item"
    case finalizePlan = "finalize_plan"
}

private nonisolated struct AITaskWorkspaceToolEntityResult<Value: Encodable>:
    Encodable
{
    let ok = true
    let value: Value
}

private nonisolated struct AITaskWorkspaceToolOptionalResult<Value: Encodable>:
    Encodable
{
    let ok = true
    let value: Value?
}

private nonisolated struct AITaskWorkspaceToolFailureResult: Encodable {
    let ok = false
    let error: String
}

/// Tool arguments are schema-strict: every declared key must be present
/// (optionals as `null`) and no undeclared key is accepted. Declaring
/// `CodingKeys` as `CaseIterable` makes the type its own key list.
private nonisolated protocol AITaskWorkspaceToolArguments: Decodable {
    associatedtype CodingKeys: CodingKey, CaseIterable
}

private nonisolated struct AITaskWorkspaceArgumentKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

/// Decodes `Value` only when the JSON object carries exactly its keys.
private nonisolated struct ExactToolArguments<
    Value: AITaskWorkspaceToolArguments
>: Decodable {
    let value: Value

    init(from decoder: Decoder) throws {
        let presentKeys = try decoder
            .container(keyedBy: AITaskWorkspaceArgumentKey.self)
            .allKeys.map(\.stringValue)
        let declaredKeys = Value.CodingKeys.allCases.map(\.stringValue)
        guard Set(presentKeys) == Set(declaredKeys) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Tool arguments must match the schema keys."
                )
            )
        }
        value = try Value(from: decoder)
    }
}

private nonisolated struct AITaskWorkspaceEmptyArguments:
    AITaskWorkspaceToolArguments
{
    enum CodingKeys: CodingKey, CaseIterable {}
}

private nonisolated struct AITaskWorkspaceIDArguments:
    AITaskWorkspaceToolArguments
{
    let id: UUID

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
    }
}

private nonisolated struct AITaskWorkspaceCategoryNameArguments:
    AITaskWorkspaceToolArguments
{
    let title: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case title
    }
}

private nonisolated struct AITaskWorkspaceCreateCategoryArguments:
    AITaskWorkspaceToolArguments
{
    let title: String
    let iconName: String
    let colorHex: String
    let includesInForecast: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, iconName, colorHex, includesInForecast
    }
}

private nonisolated struct AITaskWorkspaceUpdateCategoryArguments:
    AITaskWorkspaceToolArguments
{
    let id: UUID
    let title: String
    let iconName: String
    let colorHex: String
    let includesInForecast: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, iconName, colorHex, includesInForecast
    }
}

private nonisolated struct AITaskWorkspaceQuantityGoalArguments:
    AITaskWorkspaceToolArguments
{
    let targetAmount: Int
    let unitLabel: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case targetAmount, unitLabel
    }

    var draft: TaskQuantityGoalDraft {
        TaskQuantityGoalDraft(targetAmount: targetAmount, unitLabel: unitLabel)
    }
}

private nonisolated struct AITaskWorkspaceDailyRecurrenceArguments:
    AITaskWorkspaceToolArguments
{
    let isEnabled: Bool
    let startDayKey: String
    let timeZoneIdentifier: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case isEnabled, startDayKey, timeZoneIdentifier
    }

    var draft: TaskDailyRecurrenceDraft {
        TaskDailyRecurrenceDraft(
            isEnabled: isEnabled,
            startDayKey: startDayKey,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

private nonisolated struct AITaskWorkspaceCreateTaskArguments:
    AITaskWorkspaceToolArguments
{
    let title: String
    let parentID: UUID?
    let categoryID: UUID?
    let notes: String
    let estimatedMinutes: Int?
    let dueAt: String?
    let iconName: String
    let colorHex: String
    let quantityGoal: ExactToolArguments<AITaskWorkspaceQuantityGoalArguments>?
    let dailyRecurrence:
        ExactToolArguments<AITaskWorkspaceDailyRecurrenceArguments>?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, parentID, categoryID, notes, estimatedMinutes, dueAt
        case iconName, colorHex, quantityGoal, dailyRecurrence
    }
}

private nonisolated struct AITaskWorkspaceUpdateTaskArguments:
    AITaskWorkspaceToolArguments
{
    let id: UUID
    let title: String
    let parentID: UUID?
    let categoryID: UUID?
    let notes: String
    let estimatedMinutes: Int?
    let dueAt: String?
    let iconName: String
    let colorHex: String
    let quantityGoal: ExactToolArguments<AITaskWorkspaceQuantityGoalArguments>?
    let dailyRecurrence:
        ExactToolArguments<AITaskWorkspaceDailyRecurrenceArguments>?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, parentID, categoryID, notes, estimatedMinutes, dueAt
        case iconName, colorHex, quantityGoal, dailyRecurrence
    }
}

private nonisolated struct AITaskWorkspaceCreateChecklistArguments:
    AITaskWorkspaceToolArguments
{
    let taskID: UUID
    let title: String
    let isCompleted: Bool
    let iconName: String
    let colorHex: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case taskID, title, isCompleted, iconName, colorHex
    }
}

private nonisolated struct AITaskWorkspaceUpdateChecklistArguments:
    AITaskWorkspaceToolArguments
{
    let id: UUID
    let title: String
    let isCompleted: Bool
    let iconName: String
    let colorHex: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, title, isCompleted, iconName, colorHex
    }
}

extension LLMTaskWorkspacePlanningService {
    static func execute(
        _ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam,
        overlay: inout AITaskWorkspaceOverlay,
        makeID: @MainActor () -> UUID
    ) throws -> String {
        guard let tool = AITaskWorkspaceToolName(
            rawValue: call.function.name
        ) else {
            throw LLMTaskWorkspacePlanningError.unknownTool(
                call.function.name
            )
        }

        do {
            switch tool {
            case .listWorkspace:
                try validateEmptyArguments(
                    call.function.arguments,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.snapshot
                    )
                )

            case .getCategory:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolOptionalResult(
                        value: overlay.category(id: arguments.id)
                    )
                )

            case .getTask:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolOptionalResult(
                        value: overlay.task(id: arguments.id)
                    )
                )

            case .getChecklistItem:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolOptionalResult(
                        value: overlay.checklistItem(id: arguments.id)
                    )
                )

            case .useExistingCategory:
                let arguments: AITaskWorkspaceCategoryNameArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue
                    )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.useExistingCategory(
                            named: arguments.title
                        )
                    )
                )

            case .createCategory:
                let arguments: AITaskWorkspaceCreateCategoryArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue
                    )
                try validateVisual(
                    iconName: arguments.iconName,
                    colorHex: arguments.colorHex,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.createCategory(
                            id: makeID(),
                            title: arguments.title,
                            iconName: arguments.iconName,
                            colorHex: arguments.colorHex,
                            includesInForecast:
                            arguments.includesInForecast
                        )
                    )
                )

            case .updateCategory:
                let arguments: AITaskWorkspaceUpdateCategoryArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue
                    )
                try validateVisual(
                    iconName: arguments.iconName,
                    colorHex: arguments.colorHex,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.updateCategory(
                            id: arguments.id,
                            title: arguments.title,
                            iconName: arguments.iconName,
                            colorHex: arguments.colorHex,
                            includesInForecast:
                            arguments.includesInForecast
                        )
                    )
                )

            case .deleteCategory:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.deleteCategory(id: arguments.id)
                    )
                )

            case .createTask:
                let arguments: AITaskWorkspaceCreateTaskArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue
                    )
                try validateVisual(
                    iconName: arguments.iconName,
                    colorHex: arguments.colorHex,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.createTask(
                            id: makeID(),
                            title: arguments.title,
                            parentID: arguments.parentID,
                            categoryID: arguments.categoryID,
                            notes: arguments.notes,
                            estimatedMinutes:
                            arguments.estimatedMinutes,
                            dueAt: preparedDate(
                                arguments.dueAt,
                                toolName: tool.rawValue
                            ),
                            iconName: arguments.iconName,
                            colorHex: arguments.colorHex,
                            quantityGoal: arguments.quantityGoal?.value.draft,
                            dailyRecurrence:
                            arguments.dailyRecurrence?.value.draft
                        )
                    )
                )

            case .updateTask:
                let arguments: AITaskWorkspaceUpdateTaskArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue
                    )
                try validateVisual(
                    iconName: arguments.iconName,
                    colorHex: arguments.colorHex,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.updateTask(
                            id: arguments.id,
                            title: arguments.title,
                            parentID: arguments.parentID,
                            categoryID: arguments.categoryID,
                            notes: arguments.notes,
                            estimatedMinutes:
                            arguments.estimatedMinutes,
                            dueAt: preparedDate(
                                arguments.dueAt,
                                toolName: tool.rawValue
                            ),
                            iconName: arguments.iconName,
                            colorHex: arguments.colorHex,
                            quantityGoal: arguments.quantityGoal?.value.draft,
                            dailyRecurrence:
                            arguments.dailyRecurrence?.value.draft
                        )
                    )
                )

            case .archiveTask:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.deleteTask(id: arguments.id)
                    )
                )

            case .createChecklistItem:
                let arguments: AITaskWorkspaceCreateChecklistArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue
                    )
                try validateVisual(
                    iconName: arguments.iconName,
                    colorHex: arguments.colorHex,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.createChecklistItem(
                            id: makeID(),
                            taskID: arguments.taskID,
                            title: arguments.title,
                            isCompleted: arguments.isCompleted,
                            iconName: arguments.iconName,
                            colorHex: arguments.colorHex
                        )
                    )
                )

            case .updateChecklistItem:
                let arguments: AITaskWorkspaceUpdateChecklistArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue
                    )
                try validateVisual(
                    iconName: arguments.iconName,
                    colorHex: arguments.colorHex,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.updateChecklistItem(
                            id: arguments.id,
                            title: arguments.title,
                            isCompleted: arguments.isCompleted,
                            iconName: arguments.iconName,
                            colorHex: arguments.colorHex
                        )
                    )
                )

            case .deleteChecklistItem:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.deleteChecklistItem(
                            id: arguments.id
                        )
                    )
                )

            case .finalizePlan:
                throw LLMTaskWorkspacePlanningError.invalidResponse
            }
        } catch let error as LLMTaskWorkspacePlanningError {
            if case .invalidToolArguments = error {
                return try encodeToolResult(
                    AITaskWorkspaceToolFailureResult(
                        error: error.localizedDescription
                    )
                )
            }
            throw error
        } catch {
            return try encodeToolResult(
                AITaskWorkspaceToolFailureResult(
                    error: error.localizedDescription
                )
            )
        }
    }
}

extension LLMTaskWorkspacePlanningService {
    private static func decodeArguments<Value: AITaskWorkspaceToolArguments>(
        _ arguments: String,
        toolName: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(
                ExactToolArguments<Value>.self,
                from: Data(arguments.utf8)
            ).value
        } catch {
            throw LLMTaskWorkspacePlanningError.invalidToolArguments(
                toolName
            )
        }
    }

    static func validateEmptyArguments(
        _ arguments: String,
        toolName: String
    ) throws {
        let _: AITaskWorkspaceEmptyArguments = try decodeArguments(
            arguments,
            toolName: toolName
        )
    }

    static func validateVisual(
        iconName: String,
        colorHex: String,
        toolName: String
    ) throws {
        guard SymbolCatalog.symbolNameSet.contains(iconName),
              TaskColorPalette.hexValues.contains(colorHex)
        else {
            throw LLMTaskWorkspacePlanningError.invalidToolArguments(
                toolName
            )
        }
    }

    static func preparedDate(
        _ value: String?,
        toolName: String
    ) throws -> Date? {
        guard let value else { return nil }
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw LLMTaskWorkspacePlanningError.invalidToolArguments(
                toolName
            )
        }
        return date
    }

    static func encodeToolResult<Value: Encodable>(
        _ value: Value
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw LLMTaskWorkspacePlanningError.invalidResponse
        }
        return result
    }
}
