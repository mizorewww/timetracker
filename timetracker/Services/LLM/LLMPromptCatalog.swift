import Foundation

nonisolated enum LLMPromptKind: String, CaseIterable, Identifiable, Sendable {
    case inboxRouting
    case checklistVisual
    case taskPlan

    var id: Self { self }

    var defaultInstructions: String {
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
