import Foundation

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

private nonisolated struct AITaskWorkspaceCreateTaskArguments: Decodable {
    let title: String
    let parentID: UUID?
    let categoryID: UUID?
    let notes: String
    let estimatedMinutes: Int?
    let dueAt: String?
    let iconName: String
    let colorHex: String
    let quantityGoal: TaskQuantityGoalDraft?
    let dailyRecurrence: TaskDailyRecurrenceDraft?
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
    let quantityGoal: TaskQuantityGoalDraft?
    let dailyRecurrence: TaskDailyRecurrenceDraft?
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
        _ call: OpenAIChatToolCall,
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
                    toolName: tool.rawValue,
                    keys: ["id"]
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolOptionalResult(
                        value: overlay.category(id: arguments.id)
                    )
                )

            case .getTask:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue,
                    keys: ["id"]
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolOptionalResult(
                        value: overlay.task(id: arguments.id)
                    )
                )

            case .getChecklistItem:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue,
                    keys: ["id"]
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
                        toolName: tool.rawValue,
                        keys: ["title"]
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
                        toolName: tool.rawValue,
                        keys: [
                            "title",
                            "iconName",
                            "colorHex",
                            "includesInForecast",
                        ]
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
                        toolName: tool.rawValue,
                        keys: [
                            "id",
                            "title",
                            "iconName",
                            "colorHex",
                            "includesInForecast",
                        ]
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
                    toolName: tool.rawValue,
                    keys: ["id"]
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
                        toolName: tool.rawValue,
                        keys: Self.taskCreateKeys
                    )
                try validateTaskProgressArguments(
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
                            quantityGoal: arguments.quantityGoal,
                            dailyRecurrence: arguments.dailyRecurrence
                        )
                    )
                )

            case .updateTask:
                let arguments: AITaskWorkspaceUpdateTaskArguments =
                    try decodeArguments(
                        call.function.arguments,
                        toolName: tool.rawValue,
                        keys: Self.taskCreateKeys.union(["id"])
                    )
                try validateTaskProgressArguments(
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
                            quantityGoal: arguments.quantityGoal,
                            dailyRecurrence: arguments.dailyRecurrence
                        )
                    )
                )

            case .archiveTask:
                let arguments: AITaskWorkspaceIDArguments = try decodeArguments(
                    call.function.arguments,
                    toolName: tool.rawValue,
                    keys: ["id"]
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
                        toolName: tool.rawValue,
                        keys: [
                            "taskID",
                            "title",
                            "isCompleted",
                            "iconName",
                            "colorHex",
                        ]
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
                        toolName: tool.rawValue,
                        keys: [
                            "id",
                            "title",
                            "isCompleted",
                            "iconName",
                            "colorHex",
                        ]
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
                    toolName: tool.rawValue,
                    keys: ["id"]
                )
                return try encodeToolResult(
                    AITaskWorkspaceToolEntityResult(
                        value: overlay.deleteChecklistItem(
                            id: arguments.id
                        )
                    )
                )

            case .finalizePlan:
                preconditionFailure("Finalize is handled before tool execution")
            }
        } catch let error as LLMTaskWorkspacePlanningError {
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
    static let taskCreateKeys: Set<String> = [
        "title",
        "parentID",
        "categoryID",
        "notes",
        "estimatedMinutes",
        "dueAt",
        "iconName",
        "colorHex",
        "quantityGoal",
        "dailyRecurrence",
    ]

    static func decodeArguments<Value: Decodable>(
        _ arguments: String,
        toolName: String,
        keys: Set<String>
    ) throws -> Value {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == keys
        else {
            throw LLMTaskWorkspacePlanningError.invalidToolArguments(
                toolName
            )
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
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
        let _: EmptyToolArguments = try decodeArguments(
            arguments,
            toolName: toolName,
            keys: []
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

    static func validateTaskProgressArguments(
        _ arguments: String,
        toolName: String
    ) throws {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              hasExactNestedKeys(
                  dictionary["quantityGoal"],
                  keys: ["targetAmount", "unitLabel"]
              ),
              hasExactNestedKeys(
                  dictionary["dailyRecurrence"],
                  keys: [
                      "isEnabled",
                      "startDayKey",
                      "timeZoneIdentifier",
                  ]
              )
        else {
            throw LLMTaskWorkspacePlanningError.invalidToolArguments(
                toolName
            )
        }
    }

    static func hasExactNestedKeys(
        _ value: Any?,
        keys: Set<String>
    ) -> Bool {
        if value is NSNull {
            return true
        }
        guard let dictionary = value as? [String: Any] else {
            return false
        }
        return Set(dictionary.keys) == keys
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

    struct EmptyToolArguments: Decodable {}
}
