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

/// A `get_*` miss encodes as `{"ok":true,"value":null}`.
private nonisolated struct AITaskWorkspaceToolResult<Value: Encodable>: Encodable {
    let ok = true
    let value: Value
}

private nonisolated struct AITaskWorkspaceToolFailureResult: Encodable {
    let ok = false
    let error: String
}

/// Tool schemas are strict, but decoding is lenient so a model that drops an
/// optional key (missing means `null`) or adds an unknown one still gets a
/// usable call; value validation belongs to `AITaskWorkspaceOverlay`.
private nonisolated struct AITaskWorkspaceIDArguments: Decodable {
    let id: UUID
}

private nonisolated struct AITaskWorkspaceCategoryNameArguments: Decodable {
    let title: String
}

private nonisolated struct AITaskWorkspaceCreateCategoryArguments: Decodable {
    let title: String
    let iconName: String
    let colorHex: String
    let includesInForecast: Bool
}

private nonisolated struct AITaskWorkspaceUpdateCategoryArguments: Decodable {
    let id: UUID
    let title: String
    let iconName: String
    let colorHex: String
    let includesInForecast: Bool
}

private nonisolated struct AITaskWorkspaceQuantityGoalArguments: Decodable {
    let targetAmount: Int
    let unitLabel: String

    var draft: TaskQuantityGoalDraft {
        TaskQuantityGoalDraft(targetAmount: targetAmount, unitLabel: unitLabel)
    }
}

private nonisolated struct AITaskWorkspaceDailyRecurrenceArguments: Decodable {
    let isEnabled: Bool
    let startDayKey: String
    let timeZoneIdentifier: String

    var draft: TaskDailyRecurrenceDraft {
        TaskDailyRecurrenceDraft(
            isEnabled: isEnabled,
            startDayKey: startDayKey,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}

private nonisolated struct AITaskWorkspaceCreateTaskArguments: Decodable {
    let title: String
    let parentID: UUID?
    let categoryID: UUID?
    let notes: String
    let estimatedMinutes: Int?
    let dueAt: String?
    let iconName: String
    let colorHex: String
    let quantityGoal: AITaskWorkspaceQuantityGoalArguments?
    let dailyRecurrence: AITaskWorkspaceDailyRecurrenceArguments?
}

private nonisolated struct AITaskWorkspaceUpdateTaskArguments: Decodable {
    let id: UUID
    let title: String
    let parentID: UUID?
    let categoryID: UUID?
    let notes: String
    let estimatedMinutes: Int?
    let dueAt: String?
    let iconName: String
    let colorHex: String
    let quantityGoal: AITaskWorkspaceQuantityGoalArguments?
    let dailyRecurrence: AITaskWorkspaceDailyRecurrenceArguments?
}

private nonisolated struct AITaskWorkspaceCreateChecklistArguments: Decodable {
    let taskID: UUID
    let title: String
    let isCompleted: Bool
    let iconName: String
    let colorHex: String
}

private nonisolated struct AITaskWorkspaceUpdateChecklistArguments: Decodable {
    let id: UUID
    let title: String
    let isCompleted: Bool
    let iconName: String
    let colorHex: String
}

extension LLMTaskWorkspacePlanningService {
    static func execute(
        _ call: ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam,
        overlay: inout AITaskWorkspaceOverlay,
        makeID: @MainActor () -> UUID
    ) throws -> String {
        guard let tool = AITaskWorkspaceToolName(rawValue: call.function.name) else {
            throw LLMTaskWorkspacePlanningError.unknownTool(call.function.name)
        }
        let arguments = call.function.arguments

        // Decodes the call's arguments, runs one overlay operation, and
        // encodes its value as the tool result.
        func respond<Arguments: Decodable>(
            _ body: (Arguments) throws -> some Encodable
        ) throws -> String {
            let decoded: Arguments = try decodeArguments(arguments, toolName: tool.rawValue)
            return try encodeToolResult(AITaskWorkspaceToolResult(value: body(decoded)))
        }

        do {
            switch tool {
            case .listWorkspace:
                try validateEmptyArguments(arguments, toolName: tool.rawValue)
                return try encodeToolResult(AITaskWorkspaceToolResult(value: overlay.snapshot))
            case .getCategory:
                return try respond { (input: AITaskWorkspaceIDArguments) in
                    overlay.category(id: input.id)
                }
            case .getTask:
                return try respond { (input: AITaskWorkspaceIDArguments) in
                    overlay.task(id: input.id)
                }
            case .getChecklistItem:
                return try respond { (input: AITaskWorkspaceIDArguments) in
                    overlay.checklistItem(id: input.id)
                }
            case .useExistingCategory:
                return try respond { (input: AITaskWorkspaceCategoryNameArguments) in
                    try overlay.useExistingCategory(named: input.title)
                }
            case .createCategory:
                return try respond { (input: AITaskWorkspaceCreateCategoryArguments) in
                    try overlay.createCategory(
                        id: makeID(),
                        title: input.title,
                        iconName: input.iconName,
                        colorHex: input.colorHex,
                        includesInForecast: input.includesInForecast
                    )
                }
            case .updateCategory:
                return try respond { (input: AITaskWorkspaceUpdateCategoryArguments) in
                    try overlay.updateCategory(
                        id: input.id,
                        title: input.title,
                        iconName: input.iconName,
                        colorHex: input.colorHex,
                        includesInForecast: input.includesInForecast
                    )
                }
            case .deleteCategory:
                return try respond { (input: AITaskWorkspaceIDArguments) in
                    try overlay.deleteCategory(id: input.id)
                }
            case .createTask:
                return try respond { (input: AITaskWorkspaceCreateTaskArguments) in
                    try overlay.createTask(
                        id: makeID(),
                        title: input.title,
                        parentID: input.parentID,
                        categoryID: input.categoryID,
                        notes: input.notes,
                        estimatedMinutes: input.estimatedMinutes,
                        dueAt: preparedDate(input.dueAt, toolName: tool.rawValue),
                        iconName: input.iconName,
                        colorHex: input.colorHex,
                        quantityGoal: input.quantityGoal?.draft,
                        dailyRecurrence: input.dailyRecurrence?.draft
                    )
                }
            case .updateTask:
                return try respond { (input: AITaskWorkspaceUpdateTaskArguments) in
                    try overlay.updateTask(
                        id: input.id,
                        title: input.title,
                        parentID: input.parentID,
                        categoryID: input.categoryID,
                        notes: input.notes,
                        estimatedMinutes: input.estimatedMinutes,
                        dueAt: preparedDate(input.dueAt, toolName: tool.rawValue),
                        iconName: input.iconName,
                        colorHex: input.colorHex,
                        quantityGoal: input.quantityGoal?.draft,
                        dailyRecurrence: input.dailyRecurrence?.draft
                    )
                }
            case .archiveTask:
                return try respond { (input: AITaskWorkspaceIDArguments) in
                    try overlay.deleteTask(id: input.id)
                }
            case .createChecklistItem:
                return try respond { (input: AITaskWorkspaceCreateChecklistArguments) in
                    try overlay.createChecklistItem(
                        id: makeID(),
                        taskID: input.taskID,
                        title: input.title,
                        isCompleted: input.isCompleted,
                        iconName: input.iconName,
                        colorHex: input.colorHex
                    )
                }
            case .updateChecklistItem:
                return try respond { (input: AITaskWorkspaceUpdateChecklistArguments) in
                    try overlay.updateChecklistItem(
                        id: input.id,
                        title: input.title,
                        isCompleted: input.isCompleted,
                        iconName: input.iconName,
                        colorHex: input.colorHex
                    )
                }
            case .deleteChecklistItem:
                return try respond { (input: AITaskWorkspaceIDArguments) in
                    try overlay.deleteChecklistItem(id: input.id)
                }
            case .finalizePlan:
                throw LLMTaskWorkspacePlanningError.invalidResponse
            }
        } catch let error as LLMTaskWorkspacePlanningError {
            guard case .invalidToolArguments = error else { throw error }
            return try encodeToolResult(AITaskWorkspaceToolFailureResult(error: error.localizedDescription))
        } catch {
            return try encodeToolResult(AITaskWorkspaceToolFailureResult(error: error.localizedDescription))
        }
    }
}

extension LLMTaskWorkspacePlanningService {
    private static func decodeArguments<Value: Decodable>(
        _ arguments: String,
        toolName: String
    ) throws -> Value {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(arguments.utf8))
        } catch {
            throw LLMTaskWorkspacePlanningError.invalidToolArguments(
                toolName
            )
        }
    }

    /// A no-argument tool accepts any JSON object, or the empty string some
    /// servers send instead of `{}`.
    static func validateEmptyArguments(
        _ arguments: String,
        toolName: String
    ) throws {
        guard arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) is [String: Any]
        else {
            throw LLMTaskWorkspacePlanningError.invalidToolArguments(toolName)
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
