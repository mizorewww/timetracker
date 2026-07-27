import Foundation

extension LLMTaskWorkspacePlanningService {
    static let toolDefinitions: [OpenAIChatToolDefinition] = [
        definition(
            .listWorkspace,
            "Read the complete current in-memory proposal workspace.",
            properties: [:]
        ),
        definition(
            .getCategory,
            "Read one Category by its exact UUID.",
            properties: ["id": uuidSchema]
        ),
        definition(
            .getTask,
            "Read one Task by its exact UUID.",
            properties: ["id": uuidSchema]
        ),
        definition(
            .getChecklistItem,
            "Read one Checklist item by its exact UUID.",
            properties: ["id": uuidSchema]
        ),
        definition(
            .useExistingCategory,
            """
            Resolve one uniquely named existing Category and record that it is \
            intentionally reused. Ambiguous names return an error result.
            """,
            properties: ["title": stringSchema]
        ),
        definition(
            .createCategory,
            "Propose a new Category. The app generates and returns its UUID.",
            properties: [
                "title": stringSchema,
                "iconName": stringSchema,
                "colorHex": stringSchema,
                "includesInForecast": boolSchema,
            ]
        ),
        definition(
            .updateCategory,
            "Replace editable fields on one existing Category UUID.",
            properties: [
                "id": uuidSchema,
                "title": stringSchema,
                "iconName": stringSchema,
                "colorHex": stringSchema,
                "includesInForecast": boolSchema,
            ]
        ),
        definition(
            .deleteCategory,
            """
            Propose deleting one existing Category UUID. Root task assignments \
            to that Category become uncategorized.
            """,
            properties: ["id": uuidSchema]
        ),
        definition(
            .createTask,
            """
            Propose an independently timed work unit that is useful to time \
            independently. Use parentID for a child Task. parentID and \
            categoryID are mutually exclusive; categoryID is valid only for \
            a root Task.
            """,
            properties: taskProperties
        ),
        definition(
            .updateTask,
            """
            Replace editable fields on one exact independently timed Task UUID. \
            This can also move the Task by changing parentID/categoryID.
            """,
            properties: ["id": uuidSchema].merging(
                taskProperties,
                uniquingKeysWith: { current, _ in current }
            )
        ),
        definition(
            .archiveTask,
            """
            Propose archiving one Task UUID and its visible subtree impact. \
            This is the only Task removal tool.
            """,
            properties: ["id": uuidSchema]
        ),
        definition(
            .createChecklistItem,
            """
            Propose an untimed completion step that cannot be timed \
            independently under one exact Task UUID. The app generates and \
            returns the Checklist UUID.
            """,
            properties: [
                "taskID": uuidSchema,
                "title": stringSchema,
                "isCompleted": boolSchema,
                "iconName": stringSchema,
                "colorHex": stringSchema,
            ]
        ),
        definition(
            .updateChecklistItem,
            """
            Replace editable fields on one exact untimed Checklist UUID; it \
            cannot be timed independently.
            """,
            properties: [
                "id": uuidSchema,
                "title": stringSchema,
                "isCompleted": boolSchema,
                "iconName": stringSchema,
                "colorHex": stringSchema,
            ]
        ),
        definition(
            .deleteChecklistItem,
            "Propose deleting one exact Checklist UUID.",
            properties: ["id": uuidSchema]
        ),
        definition(
            .finalizePlan,
            """
            Before finishing, audit that every Task is useful to time \
            independently, every Checklist is an untimed completion step, and \
            the same work is not represented as both. Call this by itself only \
            after all requested changes are represented in the in-memory \
            workspace.
            """,
            properties: [:]
        ),
    ]

    static var toolSchemaDisclosure: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        guard let data = try? encoder.encode(toolDefinitions),
              let json = String(data: data, encoding: .utf8)
        else {
            assertionFailure("Production LLM tool definitions must encode.")
            return "[]"
        }
        return json
    }
}

private extension LLMTaskWorkspacePlanningService {
    static let stringSchema = OpenAIJSONValue.object([
        "type": .string("string"),
    ])

    static let boolSchema = OpenAIJSONValue.object([
        "type": .string("boolean"),
    ])

    static let uuidSchema = OpenAIJSONValue.object([
        "type": .string("string"),
        "format": .string("uuid"),
    ])

    static let nullableUUIDSchema = OpenAIJSONValue.object([
        "type": .array([
            .string("string"),
            .string("null"),
        ]),
        "format": .string("uuid"),
    ])

    static let nullableIntegerSchema = OpenAIJSONValue.object([
        "type": .array([
            .string("integer"),
            .string("null"),
        ]),
    ])

    static let nullableDateSchema = OpenAIJSONValue.object([
        "type": .array([
            .string("string"),
            .string("null"),
        ]),
        "format": .string("date-time"),
    ])

    static let nullableQuantityGoalSchema = OpenAIJSONValue.object([
        "type": .array([
            .string("object"),
            .string("null"),
        ]),
        "properties": .object([
            "targetAmount": .object([
                "type": .string("integer"),
            ]),
            "unitLabel": stringSchema,
        ]),
        "required": .array([
            .string("targetAmount"),
            .string("unitLabel"),
        ]),
        "additionalProperties": .bool(false),
    ])

    static let nullableDailyRecurrenceSchema = OpenAIJSONValue.object([
        "type": .array([
            .string("object"),
            .string("null"),
        ]),
        "properties": .object([
            "isEnabled": boolSchema,
            "startDayKey": stringSchema,
            "timeZoneIdentifier": stringSchema,
        ]),
        "required": .array([
            .string("isEnabled"),
            .string("startDayKey"),
            .string("timeZoneIdentifier"),
        ]),
        "additionalProperties": .bool(false),
    ])

    static let taskProperties: [String: OpenAIJSONValue] = [
        "title": stringSchema,
        "parentID": nullableUUIDSchema,
        "categoryID": nullableUUIDSchema,
        "notes": stringSchema,
        "estimatedMinutes": nullableIntegerSchema,
        "dueAt": nullableDateSchema,
        "iconName": stringSchema,
        "colorHex": stringSchema,
        "quantityGoal": nullableQuantityGoalSchema,
        "dailyRecurrence": nullableDailyRecurrenceSchema,
    ]

    static func definition(
        _ name: AITaskWorkspaceToolName,
        _ description: String,
        properties: [String: OpenAIJSONValue]
    ) -> OpenAIChatToolDefinition {
        OpenAIChatToolDefinition(
            function: .init(
                name: name.rawValue,
                description: description,
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(
                        properties.keys.sorted().map(
                            OpenAIJSONValue.string
                        )
                    ),
                    "additionalProperties": .bool(false),
                ])
            )
        )
    }
}
