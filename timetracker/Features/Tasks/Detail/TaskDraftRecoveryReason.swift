import Foundation

enum TaskDraftRecoveryReason: Equatable {
    case sourceUnavailable
    case sourceArchived
    case sourceChanged

    var messageKey: String {
        switch self {
        case .sourceUnavailable:
            "task.editor.recovery.message"
        case .sourceArchived:
            "task.editor.recovery.archived.message"
        case .sourceChanged:
            "task.editor.recovery.sourceChanged.message"
        }
    }

    var systemImage: String {
        switch self {
        case .sourceUnavailable:
            "icloud.slash"
        case .sourceArchived:
            "archivebox"
        case .sourceChanged:
            "arrow.triangle.2.circlepath"
        }
    }
}

enum TaskDraftRecoveryPresentation {
    static func isRequired(
        reason: TaskDraftRecoveryReason?,
        savedCopyTaskID: UUID?
    ) -> Bool {
        reason != nil || savedCopyTaskID != nil
    }
}
