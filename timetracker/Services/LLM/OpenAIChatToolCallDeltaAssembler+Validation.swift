import Foundation

nonisolated extension OpenAIChatToolCallDeltaAssembler {
    func assembledToolCalls(
        choiceIndex: Int,
        state: ChoiceState
    ) throws -> [OpenAIChatToolCall] {
        let sortedIndexes = state.toolByIndex.keys.sorted()
        for (expected, actual) in sortedIndexes.enumerated()
            where expected != actual
        {
            throw OpenAIChatToolCallAssemblyError.missingToolCallIndex(
                choiceIndex: choiceIndex,
                expected: expected
            )
        }

        var seenIDs = Set<String>()
        return try sortedIndexes.map { toolCallIndex in
            guard let state = state.toolByIndex[toolCallIndex] else {
                preconditionFailure("Sorted key must resolve its tool state")
            }
            let id = try required(
                state.id,
                field: .id,
                choiceIndex: choiceIndex,
                toolCallIndex: toolCallIndex
            )
            guard seenIDs.insert(id).inserted else {
                throw OpenAIChatToolCallAssemblyError.duplicateToolCallID(
                    choiceIndex: choiceIndex,
                    id: id
                )
            }
            let type = try required(
                state.type,
                field: .type,
                choiceIndex: choiceIndex,
                toolCallIndex: toolCallIndex
            )
            guard type == "function" else {
                throw OpenAIChatToolCallAssemblyError
                    .malformedToolCallField(
                        choiceIndex: choiceIndex,
                        toolCallIndex: toolCallIndex,
                        field: .type
                    )
            }
            let name = try required(
                state.name,
                field: .functionName,
                choiceIndex: choiceIndex,
                toolCallIndex: toolCallIndex
            )
            try validateArguments(
                state.arguments,
                choiceIndex: choiceIndex,
                toolCallIndex: toolCallIndex
            )
            return OpenAIChatToolCall(
                id: id,
                type: type,
                function: .init(
                    name: name,
                    arguments: state.arguments
                )
            )
        }
    }

    func validate(
        finishReason: String,
        toolCalls: [OpenAIChatToolCall],
        choiceIndex: Int
    ) throws {
        switch finishReason {
        case "tool_calls":
            guard toolCalls.isEmpty == false else {
                throw OpenAIChatToolCallAssemblyError.missingToolCalls(
                    choiceIndex: choiceIndex
                )
            }
        case "stop":
            guard toolCalls.isEmpty else {
                throw OpenAIChatToolCallAssemblyError.unexpectedToolCalls(
                    choiceIndex: choiceIndex,
                    finishReason: finishReason
                )
            }
        case "length", "content_filter":
            throw OpenAIChatToolCallAssemblyError.incompleteFinishReason(
                choiceIndex: choiceIndex,
                reason: finishReason
            )
        default:
            throw OpenAIChatToolCallAssemblyError.unknownFinishReason(
                choiceIndex: choiceIndex,
                reason: finishReason
            )
        }
    }

    private func required(
        _ value: String?,
        field: OpenAIChatToolCallField,
        choiceIndex: Int,
        toolCallIndex: Int
    ) throws -> String {
        guard let value else {
            throw OpenAIChatToolCallAssemblyError.missingToolCallField(
                choiceIndex: choiceIndex,
                toolCallIndex: toolCallIndex,
                field: field
            )
        }
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmed.isEmpty == false,
              trimmed.unicodeScalars.contains(
                  where: CharacterSet.controlCharacters.contains
              ) == false
        else {
            throw OpenAIChatToolCallAssemblyError.malformedToolCallField(
                choiceIndex: choiceIndex,
                toolCallIndex: toolCallIndex,
                field: field
            )
        }
        return value
    }

    private func validateArguments(
        _ arguments: String,
        choiceIndex: Int,
        toolCallIndex: Int
    ) throws {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any]
        else {
            throw OpenAIChatToolCallAssemblyError
                .malformedToolCallArguments(
                    choiceIndex: choiceIndex,
                    toolCallIndex: toolCallIndex
                )
        }
    }
}
