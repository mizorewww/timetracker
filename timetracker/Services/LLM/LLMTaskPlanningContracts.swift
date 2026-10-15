import Foundation

enum LLMTaskPlanningError: LocalizedError, Equatable {
    case missingRequest
    case missingModel
    case instructionsTooLarge
    case invalidField

    var errorDescription: String? {
        switch self {
        case .missingRequest:
            AppStrings.localized("settings.llm.taskPlan.error.requestRequired")
        case .missingModel:
            AppStrings.localized("inbox.suggestion.error.missingModel")
        case .instructionsTooLarge:
            AppStrings.localized("settings.llm.taskPlan.error.instructionsTooLarge")
        case .invalidField:
            AppStrings.localized("settings.llm.taskPlan.error.invalidField")
        }
    }
}
