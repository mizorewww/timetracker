import Foundation

nonisolated enum OpenAIChatToolCallField:
    String,
    Equatable,
    Sendable
{
    case id
    case type
    case functionName
    case arguments
}

nonisolated enum OpenAIChatToolCallAssemblyError:
    Error,
    Equatable,
    Sendable
{
    case malformedChoiceIndex(Int)
    case malformedToolCallIndex(choiceIndex: Int, toolCallIndex: Int)
    case unknownToolCallFragment(choiceIndex: Int, toolCallIndex: Int)
    case duplicateToolCallField(
        choiceIndex: Int,
        toolCallIndex: Int,
        field: OpenAIChatToolCallField
    )
    case duplicateToolCallID(choiceIndex: Int, id: String)
    case missingToolCallIndex(choiceIndex: Int, expected: Int)
    case missingToolCallField(
        choiceIndex: Int,
        toolCallIndex: Int,
        field: OpenAIChatToolCallField
    )
    case malformedToolCallField(
        choiceIndex: Int,
        toolCallIndex: Int,
        field: OpenAIChatToolCallField
    )
    case malformedToolCallArguments(choiceIndex: Int, toolCallIndex: Int)
    case malformedAssistantRole(choiceIndex: Int, role: String)
    case missingToolCalls(choiceIndex: Int)
    case unexpectedToolCalls(choiceIndex: Int, finishReason: String)
    case unknownFinishReason(choiceIndex: Int, reason: String)
    case incompleteFinishReason(choiceIndex: Int, reason: String)
    case missingFinishReason(choiceIndex: Int)
    case duplicateFinishReason(choiceIndex: Int)
    case deltaAfterFinish(choiceIndex: Int)
}

nonisolated struct OpenAIChatAssembledChoice:
    Equatable,
    Sendable
{
    let index: Int
    let assistantMessage: OpenAIChatMessage
    let finishReason: String
}

nonisolated struct OpenAIChatToolCallDeltaAssembler {
    struct ToolState {
        var id: String?
        var type: String?
        var name: String?
        var arguments = ""
    }

    struct ChoiceState {
        var role: String?
        var content = ""
        var reasoningContent = ""
        var toolByIndex: [Int: ToolState] = [:]
        var finishReason: String?
    }

    private var choiceByIndex: [Int: ChoiceState] = [:]

    mutating func ingest(
        _ chunk: OpenAIChatCompletionStreamChunk
    ) throws {
        for choice in chunk.choices {
            try ingest(choice)
        }
    }

    func finalize() throws -> [OpenAIChatAssembledChoice] {
        try choiceByIndex.keys.sorted().map { choiceIndex in
            guard let state = choiceByIndex[choiceIndex] else {
                preconditionFailure("Sorted key must resolve its choice state")
            }
            guard let finishReason = state.finishReason else {
                throw OpenAIChatToolCallAssemblyError.missingFinishReason(
                    choiceIndex: choiceIndex
                )
            }
            let toolCalls = try assembledToolCalls(
                choiceIndex: choiceIndex,
                state: state
            )
            try validate(
                finishReason: finishReason,
                toolCalls: toolCalls,
                choiceIndex: choiceIndex
            )
            return OpenAIChatAssembledChoice(
                index: choiceIndex,
                assistantMessage: OpenAIChatMessage(
                    role: state.role ?? "assistant",
                    content: state.content.isEmpty ? nil : state.content,
                    reasoningContent: state.reasoningContent.isEmpty
                        ? nil
                        : state.reasoningContent,
                    toolCalls: toolCalls.isEmpty ? nil : toolCalls
                ),
                finishReason: finishReason
            )
        }
    }

    private mutating func ingest(
        _ choice: OpenAIChatCompletionStreamChunk.Choice
    ) throws {
        guard choice.index >= 0 else {
            throw OpenAIChatToolCallAssemblyError.malformedChoiceIndex(
                choice.index
            )
        }
        var state = choiceByIndex[choice.index] ?? ChoiceState()
        if state.finishReason != nil {
            if choice.finish_reason != nil {
                throw OpenAIChatToolCallAssemblyError.duplicateFinishReason(
                    choiceIndex: choice.index
                )
            }
            if choice.delta?.hasPayload == true {
                throw OpenAIChatToolCallAssemblyError.deltaAfterFinish(
                    choiceIndex: choice.index
                )
            }
            return
        }

        if let delta = choice.delta {
            try ingest(delta, choiceIndex: choice.index, state: &state)
        }
        if let finishReason = choice.finish_reason {
            state.finishReason = finishReason
        }
        choiceByIndex[choice.index] = state
    }

    private func ingest(
        _ delta: OpenAIChatCompletionStreamChunk.Choice.Delta,
        choiceIndex: Int,
        state: inout ChoiceState
    ) throws {
        if let role = delta.role {
            guard role == "assistant" else {
                throw OpenAIChatToolCallAssemblyError.malformedAssistantRole(
                    choiceIndex: choiceIndex,
                    role: role
                )
            }
            state.role = role
        }
        state.content += delta.content ?? ""
        state.reasoningContent += delta.reasoning_content ?? ""
        for toolCall in delta.tool_calls ?? [] {
            try ingest(
                toolCall,
                choiceIndex: choiceIndex,
                state: &state
            )
        }
    }

    private func ingest(
        _ delta: OpenAIChatCompletionStreamChunk.Choice.Delta.ToolCall,
        choiceIndex: Int,
        state: inout ChoiceState
    ) throws {
        guard delta.index >= 0 else {
            throw OpenAIChatToolCallAssemblyError.malformedToolCallIndex(
                choiceIndex: choiceIndex,
                toolCallIndex: delta.index
            )
        }
        let isStart = delta.id != nil ||
            delta.type != nil ||
            delta.function?.name != nil
        guard state.toolByIndex[delta.index] != nil || isStart else {
            throw OpenAIChatToolCallAssemblyError.unknownToolCallFragment(
                choiceIndex: choiceIndex,
                toolCallIndex: delta.index
            )
        }

        var tool = state.toolByIndex[delta.index] ?? ToolState()
        try assign(
            delta.id,
            to: &tool.id,
            field: .id,
            choiceIndex: choiceIndex,
            toolCallIndex: delta.index
        )
        try assign(
            delta.type,
            to: &tool.type,
            field: .type,
            choiceIndex: choiceIndex,
            toolCallIndex: delta.index
        )
        try assign(
            delta.function?.name,
            to: &tool.name,
            field: .functionName,
            choiceIndex: choiceIndex,
            toolCallIndex: delta.index
        )
        tool.arguments += delta.function?.arguments ?? ""
        state.toolByIndex[delta.index] = tool
    }

    private func assign(
        _ fragment: String?,
        to value: inout String?,
        field: OpenAIChatToolCallField,
        choiceIndex: Int,
        toolCallIndex: Int
    ) throws {
        guard let fragment else { return }
        guard value == nil else {
            throw OpenAIChatToolCallAssemblyError.duplicateToolCallField(
                choiceIndex: choiceIndex,
                toolCallIndex: toolCallIndex,
                field: field
            )
        }
        value = fragment
    }
}
