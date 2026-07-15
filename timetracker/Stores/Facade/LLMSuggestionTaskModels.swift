import Foundation

struct StoreLLMSuggestionTask {
    let requestID: UUID
    let isAutomatic: Bool
    let task: Task<Void, Never>
}

struct LLMSuggestionTaskSnapshot {
    let inboxRequestIDsByItemID: [UUID: UUID]
    let checklistRequestIDsByItemID: [UUID: UUID]
}
