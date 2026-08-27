import Foundation
import SwiftData

extension TimeTrackerStore {
    func completeChecklistVisualSuggestion(
        _ result: LLMChecklistVisualSuggestionResult,
        request: ChecklistVisualSuggestionRequest,
        requestID: UUID
    ) {
        guard checklistVisualSuggestionLifecycle.isCurrentRequest(
            itemID: request.itemID,
            requestID: requestID
        ) else { return }
        defer {
            finishChecklistVisualSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID
            )
        }

        guard matchesCurrentLLMConfiguration(request.configuration),
              matchesCurrentLLMPrompt(
                  request.instructions,
                  kind: .checklistVisual
              ),
              preferences.llmAutomaticSuggestionsEnabled,
              let modelContext
        else {
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
        guard checklistVisualSuggestionLifecycle.isCurrentRequest(
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

        guard matchesCurrentLLMConfiguration(request.configuration),
              matchesCurrentLLMPrompt(request.instructions, kind: .checklistVisual),
              showsErrors || preferences.llmAutomaticSuggestionsEnabled
        else {
            return
        }
        if showsErrors {
            errorMessage = error.localizedDescription
        }
        checklistVisualSuggestionLifecycle.failureByItemID[request.itemID] =
            ChecklistVisualSuggestionFailure(
                fingerprint: request.fingerprint,
                retryAfter: Date().addingTimeInterval(60)
            )
    }

    private func finishChecklistVisualSuggestionRequest(
        itemID: UUID,
        requestID: UUID,
        shouldAutoSuggest: Bool = true
    ) {
        guard checklistVisualSuggestionLifecycle.finish(itemID: itemID, requestID: requestID)
        else { return }
        checklistVisualSuggestionSchedulingFingerprintByItemID.removeValue(
            forKey: itemID
        )
        if shouldAutoSuggest {
            autoSuggestChecklistVisualsIfNeeded()
        }
    }
}

struct ChecklistVisualSuggestionRequest {
    let itemID: UUID
    let taskID: UUID
    let title: String
    let baseline: ChecklistVisualSuggestionBaseline
    let taskTitle: String
    let taskPath: String
    let instructions: String
    let configuration: LLMRequestConfiguration

    var fingerprint: String {
        [
            title,
            taskTitle,
            taskPath,
            instructions,
            configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            configuration.reasoningEffort.rawValue,
            String(configuration.apiKey.hashValue),
        ].joined(separator: "|")
    }

    var schedulingFingerprint: String {
        [
            fingerprint,
            baseline.itemMutationID.uuidString,
            baseline.visualMutationID?.uuidString ?? "none",
            baseline.visualUserEditedAt?.timeIntervalSinceReferenceDate
                .description ?? "none",
        ].joined(separator: "|")
    }
}
