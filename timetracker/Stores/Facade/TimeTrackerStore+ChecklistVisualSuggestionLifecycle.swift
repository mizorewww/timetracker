import Foundation
import SwiftData

extension TimeTrackerStore {
    func completeChecklistVisualSuggestion(
        _ result: LLMChecklistVisualSuggestionResult,
        request: ChecklistVisualSuggestionRequest,
        requestID: UUID
    ) {
        guard isCurrentChecklistVisualSuggestionRequest(
            itemID: request.itemID,
            requestID: requestID
        ) else { return }
        defer {
            finishChecklistVisualSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID
            )
        }

        guard matchesCurrentLLMConfiguration(
                  endpoint: request.endpoint,
                  apiKey: request.apiKey,
                  modelID: request.modelID
              ),
              preferences.llmAutomaticSuggestionsEnabled,
              let modelContext else {
            return
        }

        do {
            let outcome = try StoreScopedChecklistCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).applyVisualSuggestion(baseline: request.baseline, result: result)
            if outcome.didMutate {
                finishStoreScopedMutation(events: outcome.events)
            } else {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks, .checklist]))
            }
        } catch {
            // LLM output is advisory. A task/item that disappeared or changed in
            // another scene is a stale result, not an error that should overwrite
            // user feedback. Refresh the local read models when possible.
            try? refresh(plan: StoreRefreshPlan(scopes: [.tasks, .checklist]))
        }
    }

    func completeChecklistVisualSuggestionFailure(
        _ error: Error,
        request: ChecklistVisualSuggestionRequest,
        requestID: UUID,
        showsErrors: Bool,
        wasCancelled: Bool
    ) {
        guard isCurrentChecklistVisualSuggestionRequest(
            itemID: request.itemID,
            requestID: requestID
        ) else { return }
        if wasCancelled {
            finishChecklistVisualSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID,
                shouldAutoSuggest: false
            )
            return
        }
        defer {
            finishChecklistVisualSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID
            )
        }

        guard matchesCurrentLLMConfiguration(
            endpoint: request.endpoint,
            apiKey: request.apiKey,
            modelID: request.modelID
        ), showsErrors || preferences.llmAutomaticSuggestionsEnabled else {
            return
        }
        if showsErrors {
            errorMessage = error.localizedDescription
        }
        checklistVisualSuggestionFailureFingerprintByItemID[request.itemID] = request.fingerprint
        checklistVisualSuggestionRetryAfterByItemID[request.itemID] = Date().addingTimeInterval(60)
    }

    private func finishChecklistVisualSuggestionRequest(
        itemID: UUID,
        requestID: UUID,
        shouldAutoSuggest: Bool = true
    ) {
        guard isCurrentChecklistVisualSuggestionRequest(
            itemID: itemID,
            requestID: requestID
        ) else { return }
        checklistVisualSuggestionTasksByItemID.removeValue(forKey: itemID)
        checklistVisualSuggestionInFlightIDs.remove(itemID)
        if shouldAutoSuggest {
            autoSuggestChecklistVisualsIfNeeded()
        }
    }

    private func isCurrentChecklistVisualSuggestionRequest(
        itemID: UUID,
        requestID: UUID
    ) -> Bool {
        checklistVisualSuggestionTasksByItemID[itemID]?.requestID == requestID
    }
}

struct ChecklistVisualSuggestionRequest {
    let itemID: UUID
    let taskID: UUID
    let title: String
    let baseline: ChecklistVisualSuggestionBaseline
    let taskTitle: String
    let taskPath: String
    let endpoint: String
    let apiKey: String
    let modelID: String

    var fingerprint: String {
        [
            title,
            endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            String(apiKey.hashValue)
        ].joined(separator: "|")
    }
}
