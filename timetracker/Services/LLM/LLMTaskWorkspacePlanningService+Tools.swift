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
                            quantityGoal: arguments.quantityGoal?.draft,
                            dailyRecurrence:
                            arguments.dailyRecurrence?.draft
                        )
                    )
                )

            case .updateTask:
                let arguments: AITaskWorkspaceUpdateTaskArguments =
                    try decodeArguments(
                        call.function.arguments,
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
                            quantityGoal: arguments.quantityGoal?.draft,
                            dailyRecurrence:
                            arguments.dailyRecurrence?.draft
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
