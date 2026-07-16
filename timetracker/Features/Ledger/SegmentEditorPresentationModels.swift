import Foundation

enum SegmentDeletionImpact: Equatable {
    case historicalRecord
    case runningTimer
    case activeFocusSession

    init(baseline: SegmentEditorDraftBaseline) {
        if baseline.pomodoroPhase != nil {
            self = .activeFocusSession
        } else if baseline.endedAt == nil {
            self = .runningTimer
        } else {
            self = .historicalRecord
        }
    }

    var confirmationMessage: String {
        let key = switch self {
        case .historicalRecord:
            "segment.delete.confirm.message"
        case .runningTimer:
            "segment.delete.confirm.runningMessage"
        case .activeFocusSession:
            "segment.delete.confirm.focusMessage"
        }
        return AppStrings.localized(key)
    }

    var confirmationTitle: String {
        let key = switch self {
        case .historicalRecord:
            "segment.delete.confirm.title"
        case .runningTimer:
            "segment.delete.confirm.runningTitle"
        case .activeFocusSession:
            "segment.delete.confirm.focusTitle"
        }
        return AppStrings.localized(key)
    }

    var confirmationActionTitle: String {
        let key = switch self {
        case .historicalRecord:
            "segment.delete.action"
        case .runningTimer:
            "segment.delete.action.running"
        case .activeFocusSession:
            "segment.delete.action.focus"
        }
        return AppStrings.localized(key)
    }
}

enum SegmentEditorRecoveryError: Identifiable, Equatable {
    case stale
    case inconsistent

    init?(_ error: Error) {
        guard let mutationError = error as? SegmentMutationError else {
            return nil
        }
        switch mutationError {
        case .staleDraft:
            self = .stale
        case .inconsistentSession:
            self = .inconsistent
        case .activeTimerStartInFuture:
            return nil
        }
    }

    var id: String {
        switch self {
        case .stale:
            "stale"
        case .inconsistent:
            "inconsistent"
        }
    }

    var message: String {
        switch self {
        case .stale:
            SegmentMutationError.staleDraft.localizedDescription
        case .inconsistent:
            SegmentMutationError.inconsistentSession.localizedDescription
        }
    }

    var title: String {
        let key = switch self {
        case .stale:
            "segment.editor.recovery.title"
        case .inconsistent:
            "segment.editor.inconsistent.title"
        }
        return AppStrings.localized(key)
    }
}
