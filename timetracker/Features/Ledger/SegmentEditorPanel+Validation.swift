import SwiftUI

extension SegmentEditorPanel {
    var isActiveFocus: Bool {
        initialDraft.baseline.pomodoroPhase != nil
    }

    var endActionKey: String {
        isActiveFocus ? "segment.endFocusNow" : "segment.endTimerNow"
    }

    var keepRunningActionKey: String {
        isActiveFocus ? "segment.keepFocusing" : "segment.keepRunning"
    }

    var deletionImpact: SegmentDeletionImpact {
        SegmentDeletionImpact(baseline: initialDraft.baseline)
    }

    func trackedTimeValidation(
        for draft: SegmentEditorDraft,
        at now: Date
    ) -> TrackedTimePolicy.WriteValidation {
        TrackedTimePolicy.validateWrite(
            startedAt: draft.startedAt,
            endedAt: draft.isActive ? nil : draft.endedAt,
            now: now
        )
    }

    @ViewBuilder
    func validationMessage(
        for validation: TrackedTimePolicy.WriteValidation,
        isActive: Bool
    ) -> some View {
        switch validation {
        case .valid:
            EmptyView()
        case .invalidRange:
            timeValidationLabel(key: "segment.error.endAfterStart")
        case .futureTime:
            timeValidationLabel(
                key: isActive
                    ? "segment.error.startNotFuture"
                    : "segment.error.timeNotFuture"
            )
        }
    }

    func timeValidationLabel(key: String) -> some View {
        Label(
            AppStrings.localized(key),
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.red)
        .accessibilityAddTraits(.isStaticText)
    }

    func noteValidationMessage(for draft: SegmentEditorDraft) -> String? {
        do {
            _ = try LedgerPersistencePolicy.prepareNote(draft.note)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func noteValidationLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityAddTraits(.isStaticText)
    }

    var availableTasks: [TaskNode] {
        store.tasks.filter { task in
            store.isTaskAvailableForTracking(task) || task.id == initialDraft.taskID
        }
    }
}
