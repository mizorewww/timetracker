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
    /// Hosts in presentation order: the scene root first, then each sheet
    /// over it. Only the topmost can show an alert the user sees; an alert
    /// attached under an open sheet stays hidden behind it.
    private(set) var hostIDs: [UUID] = []
    @ObservationIgnored private var pending: [AppSceneFeedback] = []

    func registerHost(_ id: UUID) {
        guard hostIDs.contains(id) == false else { return }
        hostIDs.append(id)
    }

    func unregisterHost(_ id: UUID) {
        hostIDs.removeAll { $0 == id }
    }

    /// The feedback the host shows: the current one while it is the topmost
    /// host, else nil.
    func feedback(forHost hostID: UUID) -> AppSceneFeedback? {
        hostIDs.last == hostID ? current : nil
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
