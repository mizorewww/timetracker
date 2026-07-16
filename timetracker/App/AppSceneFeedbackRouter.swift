import Foundation
import Observation

nonisolated enum AppSceneFeedbackContext: Equatable, Sendable {
    case general
    case dataExport
    case databaseMaintenance
    case syncRecovery
    case presentation
}

struct AppSceneFeedback: Identifiable, Equatable {
    let id: UUID
    let context: AppSceneFeedbackContext
    let title: String
    let message: String

    init(
        id: UUID = UUID(),
        context: AppSceneFeedbackContext = .general,
        title: String,
        message: String
    ) {
        self.id = id
        self.context = context
        self.title = title
        self.message = message
    }
}

@MainActor
@Observable
final class AppSceneFeedbackRouter {
    private(set) var current: AppSceneFeedback?
    @ObservationIgnored private var pending: [AppSceneFeedback] = []

    var pendingCount: Int {
        pending.count
    }

    func present(_ feedback: AppSceneFeedback) {
        guard current == nil else {
            pending.append(feedback)
            return
        }
        current = feedback
    }

    @discardableResult
    func present(
        context: AppSceneFeedbackContext = .general,
        title: String,
        message: String
    ) -> UUID {
        let feedback = AppSceneFeedback(
            context: context,
            title: title,
            message: message
        )
        present(feedback)
        return feedback.id
    }

    func dismiss(feedbackID: UUID) {
        guard current?.id == feedbackID else { return }
        current = pending.isEmpty ? nil : pending.removeFirst()
    }
}
