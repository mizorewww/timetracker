import Foundation
import Observation

struct AppSceneFeedback: Identifiable, Equatable {
    let id: UUID
    let title: String
    let message: String

    init(
        id: UUID = UUID(),
        title: String,
        message: String
    ) {
        self.id = id
        self.title = title
        self.message = message
    }
}

@MainActor
@Observable
final class AppSceneFeedbackRouter {
    private(set) var current: AppSceneFeedback?
    @ObservationIgnored private var pending: [AppSceneFeedback] = []

    func present(_ feedback: AppSceneFeedback) {
        guard current == nil else {
            pending.append(feedback)
            return
        }
        current = feedback
    }

    @discardableResult
    func present(
        title: String,
        message: String
    ) -> UUID {
        let feedback = AppSceneFeedback(
            title: title,
            message: message
        )
        present(feedback)
        return feedback.id
    }

    /// Presents a failed command's error under the generic error title.
    func present(_ error: Error, title: String = AppStrings.localized("error.title")) {
        present(title: title, message: error.localizedDescription)
    }

    /// Runs a user-initiated command and presents its failure, returning nil
    /// when it threw.
    @discardableResult
    func perform<Result>(
        title: String = AppStrings.localized("error.title"),
        _ command: () throws -> Result
    ) -> Result? {
        do {
            return try command()
        } catch {
            present(error, title: title)
            return nil
        }
    }

    func dismiss(feedbackID: UUID) {
        guard current?.id == feedbackID else { return }
        current = pending.isEmpty ? nil : pending.removeFirst()
    }
}
