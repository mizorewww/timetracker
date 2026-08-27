import Foundation

struct StoreLLMSuggestionTask {
    let requestID: UUID
    let isAutomatic: Bool
    let task: Task<Void, Never>
}

struct StoreLLMSuggestionDebounceTask {
    let schedulingFingerprint: String
    let task: Task<Void, Never>
}

struct ChecklistVisualSuggestionFailure {
    let fingerprint: String
    let retryAfter: Date
}

struct LLMSuggestionTaskSnapshot {
    let inboxRequestIDsByItemID: [UUID: UUID]
    let checklistRequestIDsByItemID: [UUID: UUID]
}
