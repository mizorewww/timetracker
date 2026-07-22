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
            Create a practical plan for time tracking. Use categories only as \
            broad reporting groups, tasks as work that can be timed, and \
            checklist items as concrete completion steps. Keep titles concise, \
            avoid duplicate work, and add notes only when they provide useful \
            context.
            """
        }
    }
}

/// Compatibility name retained for the task-plan service and existing synced
/// preference. New prompt surfaces should use `LLMPromptKind` directly.
nonisolated enum LLMTaskPlanPrompt {
    static let defaultInstructions = LLMPromptKind.taskPlan.defaultInstructions
}
