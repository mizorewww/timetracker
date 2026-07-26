import Foundation

nonisolated enum LLMPromptKind: String, CaseIterable, Identifiable, Sendable {
    case inboxRouting
    case checklistVisual
    case taskPlan

    var id: Self {
        self
    }

    var defaultInstructions: String {
        switch self {
        case .inboxRouting:
            """
            Route each inbox item to the one existing destination that best \
            matches its intent. Use a child task for work that belongs under \
            an existing task, a category for new standalone work in that area, \
            or a checklist item for a concrete step of an existing task. Keep \
            the reason concise.

            ### Worked example

            **Example input**

            - Inbox title: `Read chapter 4`
            - Existing task: `Artificial Intelligence: A Modern Approach`
              (`11111111-1111-1111-1111-111111111111`)

            **Example output**

            ```json
            {
              "destinationKind": "checklist",
              "destinationID": "11111111-1111-1111-1111-111111111111",
              "reason": "This is a concrete step of the existing reading task.",
              "iconName": "book",
              "colorHex": "1677FF"
            }
            ```
            """
        case .checklistVisual:
            """
            Choose a concise visual identity that reflects the checklist \
            item's meaning and task context. Prefer a familiar, specific SF \
            Symbol and a color that makes related work easy to recognize. Keep \
            the reason concise.

            ### Worked example

            **Example input**

            - Checklist item: `Read chapter 4`
            - Task path: `Reading / Artificial Intelligence: A Modern Approach`

            **Example output**

            ```json
            {
              "iconName": "book",
              "colorHex": "1677FF",
              "reason": "A book directly represents this reading step."
            }
            ```
            """
        case .taskPlan:
            """
            ## Build the complete useful plan

            Generate all useful work called for by the request. Keep the plan \
            practical for timing and progress tracking, and do not stop after \
            one representative item.

            ### Choose the smallest useful type

            - **Category**: a broad, durable reporting group.
            - **Task**: work that is useful to time independently.
            - **Child task**: independently timed work that belongs inside \
              another task.
            - **Checklist item**: a concrete completion unit that does not need \
              its own timer.
            - **Quantity goal**: numeric progress such as pages, repetitions, or \
              glasses. Include a clear target and unit.
            - **Daily recurrence**: work that should produce one occurrence each \
              day. Combine it with a quantity goal when both are useful.

            ### Keep the result actionable

            Use concise titles, avoid duplicate work, and add notes only when \
            they provide useful context. Expand explicitly numbered or named \
            steps completely. For example, reading a ten-chapter book should \
            produce one reading task with **Checklist item** entries for every \
            chapter, not a single sample chapter.

            ### Worked example

            **Example input**

            The workspace contains the task `Artificial Intelligence: A Modern \
            Approach` with ID `22222222-2222-2222-2222-222222222222`. The \
            request is: `Add checklist items for chapters 1 through 3`.

            **Example output**

            Call `create_checklist_item` three times, once for each chapter, \
            using the exact existing task ID and distinct complete titles:

            ```json
            {"taskID":"22222222-2222-2222-2222-222222222222","title":"Read chapter 1","isCompleted":false,"iconName":"book","colorHex":"1677FF"}
            {"taskID":"22222222-2222-2222-2222-222222222222","title":"Read chapter 2","isCompleted":false,"iconName":"book","colorHex":"1677FF"}
            {"taskID":"22222222-2222-2222-2222-222222222222","title":"Read chapter 3","isCompleted":false,"iconName":"book","colorHex":"1677FF"}
            ```

            After all requested changes exist in the overlay, call \
            `finalize_plan` with `{}`. Do not replace the complete sequence \
            with one representative checklist item.
            """
        }
    }
}

extension LLMPromptKind {
    /// The exact defaults shipped before typed worked examples were added.
    /// Stored values equal to these strings migrate forward, while any edited
    /// text remains untouched.
    var previousDefaultInstructions: String {
        switch self {
        case .inboxRouting:
            """
            Route each inbox item to the one existing destination that best \
            matches its intent. Use a child task for work that belongs under \
            an existing task, a category for new standalone work in that area, \
            or a checklist item for a concrete step of an existing task. Keep \
            the reason concise.
            """
        case .checklistVisual:
            """
            Choose a concise visual identity that reflects the checklist \
            item's meaning and task context. Prefer a familiar, specific SF \
            Symbol and a color that makes related work easy to recognize. Keep \
            the reason concise.
            """
        case .taskPlan:
            """
            ## Build the complete useful plan

            Generate all useful work called for by the request. Keep the plan \
            practical for timing and progress tracking, and do not stop after \
            one representative item.

            ### Choose the smallest useful type

            - **Category**: a broad, durable reporting group.
            - **Task**: work that is useful to time independently.
            - **Child task**: independently timed work that belongs inside \
              another task.
            - **Checklist item**: a concrete completion unit that does not need \
              its own timer.
            - **Quantity goal**: numeric progress such as pages, repetitions, or \
              glasses. Include a clear target and unit.
            - **Daily recurrence**: work that should produce one occurrence each \
              day. Combine it with a quantity goal when both are useful.

            ### Keep the result actionable

            Use concise titles, avoid duplicate work, and add notes only when \
            they provide useful context. Expand explicitly numbered or named \
            steps completely. For example, reading a ten-chapter book should \
            produce one reading task with **Checklist item** entries for every \
            chapter, not a single sample chapter.
            """
        }
    }

    /// The fixed response contract always sent alongside the editable
    /// instructions. Settings shows it read-only so users can tell which
    /// behavior their instructions cannot change.
    var fixedResponseContract: String {
        switch self {
        case .inboxRouting:
            LLMInboxSuggestionService.responseContract
        case .checklistVisual:
            LLMChecklistVisualSuggestionService.responseContract
        case .taskPlan:
            LLMTaskWorkspacePlanningService.responseContract
        }
    }

    /// Read-only, credential-free description of the production request.
    /// Keep its constants shared with request construction so Settings cannot
    /// describe a different protocol than the App actually sends.
    func effectiveRequestDisclosure(
        reasoningEffort: LLMReasoningEffort = .high
    ) -> String {
        let sharedEnvelope = """
        ## HTTP envelope

        - `POST <configured endpoint>/chat/completions`
        - `Authorization: Bearer <API key from Keychain>` is an HTTP header. \
        The API key never enters the prompt, disclosure text, workspace JSON, \
        tool arguments, or tool results.
        - `model`: the exact selected model ID.
        - `messages[0]`: the fixed system contract shown separately below.
        - `messages[1]`: a JSON user message containing the editable \
        instructions plus the runtime fields listed below.
        """
        let symbolSummary = """
        - `allowedSymbols`: \
        \(SymbolCatalog.symbolNames.count) exact SF Symbol names.
        - `allowedColors`: \(TaskColorPalette.hexValues.count) exact color values.
        """

        switch self {
        case .inboxRouting:
            return """
            \(sharedEnvelope)

            ## Runtime user JSON

            - `instructions`
            - `inboxTitle`
            - `tasks`: transmitted destination task records
            - `categories`: transmitted destination category records
            \(symbolSummary)

            ## Model controls

            - DeepSeek V4: `temperature` is omitted; `thinking.type` is \
            `enabled`; `reasoning_effort` is `\(reasoningEffort.rawValue)`.
            - Other models: `temperature` is \
            \(LLMChatRequestPolicy.suggestionTemperature), and thinking fields \
            are omitted.
            - `response_format.type`: `json_object`
            - `tools` and `tool_choice`: omitted
            """
        case .checklistVisual:
            return """
            \(sharedEnvelope)

            ## Runtime user JSON

            - `instructions`
            - `checklistTitle`
            - `taskTitle`
            - `taskPath`
            \(symbolSummary)

            ## Model controls

            - DeepSeek V4: `temperature` is omitted; `thinking.type` is \
            `enabled`; `reasoning_effort` is `\(reasoningEffort.rawValue)`.
            - Other models: `temperature` is \
            \(LLMChatRequestPolicy.suggestionTemperature), and thinking fields \
            are omitted.
            - `response_format.type`: `json_object`
            - `tools` and `tool_choice`: omitted
            """
        case .taskPlan:
            let toolNames = AITaskWorkspaceToolName.allCases
                .map { "- `\($0.rawValue)`" }
                .joined(separator: "\n")
            return """
            \(sharedEnvelope)

            ## Runtime user JSON

            - `schemaVersion`
            - `instructions`
            - `request`
            - `workspace`: every visible Category, Task, and Checklist item
            \(symbolSummary)

            ## Model controls

            - DeepSeek V4: `temperature` and `tool_choice` are omitted; \
            `thinking.type` is `enabled`; `reasoning_effort` is \
            `\(reasoningEffort.rawValue)`.
            - Other models: `temperature` is \
            \(LLMChatRequestPolicy.taskPlanningTemperature), `tool_choice` is \
            `required`, and thinking fields are omitted.
            - `response_format`: omitted because the response is tool calls.
            - Each round appends the assistant tool calls and matching tool \
            results to `messages`; only `finalize_plan` ends generation.

            ## Tools

            \(toolNames)

            ## Exact tool schemas sent in `tools`

            ```json
            \(LLMTaskWorkspacePlanningService.toolSchemaDisclosure)
            ```
            """
        }
    }
}

nonisolated enum LLMChatRequestPolicy {
    static let suggestionTemperature = 0.2
    static let taskPlanningTemperature = 0.0

    static func usesDeepSeekV4Thinking(modelID: String) -> Bool {
        let normalizedModelID = modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedModelID == "deepseek-v4-flash" ||
            normalizedModelID == "deepseek-v4-pro"
    }

    static func temperature(
        modelID: String,
        fallback: Double
    ) -> Double? {
        usesDeepSeekV4Thinking(modelID: modelID) ? nil : fallback
    }

    static func thinkingConfiguration(
        modelID: String
    ) -> OpenAIChatThinkingConfiguration? {
        usesDeepSeekV4Thinking(modelID: modelID)
            ? OpenAIChatThinkingConfiguration(type: "enabled")
            : nil
    }

    static func reasoningEffort(
        modelID: String,
        selected: LLMReasoningEffort
    ) -> String? {
        usesDeepSeekV4Thinking(modelID: modelID)
            ? selected.rawValue
            : nil
    }
}

/// Compatibility name retained for the task-plan service and existing synced
/// preference. New prompt surfaces should use `LLMPromptKind` directly.
nonisolated enum LLMTaskPlanPrompt {
    static let legacyDefaultInstructions = """
    Create a practical plan for time tracking. Use categories only as \
    broad reporting groups, tasks as work that can be timed, and \
    checklist items as concrete completion steps. Keep titles concise, \
    avoid duplicate work, and add notes only when they provide useful \
    context.
    """

    static let defaultInstructions = LLMPromptKind.taskPlan.defaultInstructions
}
