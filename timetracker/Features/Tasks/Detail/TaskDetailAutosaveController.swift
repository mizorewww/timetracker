import Foundation
import Observation

nonisolated struct TaskDetailAutosaveRequest: Equatable, Sendable {
    let isEnabled: Bool
    let draft: TaskEditorDraft
    let hasUnsavedChanges: Bool
    let isValid: Bool
}

nonisolated enum TaskDetailAutosaveCommitResult: Equatable, Sendable {
    case saved
    case failed(message: String)
    case conflicted
}

@MainActor
@Observable
final class TaskDetailAutosaveController {
    enum Status: Equatable {
        case idle
        case scheduled
        case saving
        case saved
        case validationBlocked
        case failed(message: String)
        case conflicted
    }

    private(set) var status: Status = .idle

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let commit: (
        TaskEditorDraft
    ) -> TaskDetailAutosaveCommitResult
    @ObservationIgnored private var latestRequest: TaskDetailAutosaveRequest?
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRequestID = UUID()

    init(
        delay: Duration = .milliseconds(450),
        commit: @escaping (
            TaskEditorDraft
        ) -> TaskDetailAutosaveCommitResult
    ) {
        self.delay = delay
        self.commit = commit
    }

    func update(with request: TaskDetailAutosaveRequest) {
        latestRequest = request
        cancelPendingTask()

        guard request.isEnabled, request.hasUnsavedChanges else {
            status = .idle
            return
        }
        guard request.isValid else {
            status = .validationBlocked
            return
        }

        status = .scheduled
        let requestID = UUID()
        pendingRequestID = requestID
        pendingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.delay ?? .zero)
            } catch {
                return
            }
            self?.commitScheduledRequest(id: requestID)
        }
    }

    @discardableResult
    func flush(_ request: TaskDetailAutosaveRequest? = nil) -> Bool {
        if let request {
            latestRequest = request
        }
        cancelPendingTask()
        guard let latestRequest else {
            status = .idle
            return true
        }
        return commitImmediately(latestRequest)
    }

    @discardableResult
    func retry() -> Bool {
        flush()
    }

    func cancel() {
        latestRequest = nil
        cancelPendingTask()
        status = .idle
    }

    private func commitScheduledRequest(id: UUID) {
        guard id == pendingRequestID,
              let latestRequest else { return }
        pendingTask = nil
        _ = commitImmediately(latestRequest)
    }

    private func commitImmediately(
        _ request: TaskDetailAutosaveRequest
    ) -> Bool {
        guard request.isEnabled else {
            status = .idle
            return request.hasUnsavedChanges == false
        }
        guard request.hasUnsavedChanges else {
            status = .idle
            return true
        }
        guard request.isValid else {
            status = .validationBlocked
            return false
        }

        status = .saving
        switch commit(request.draft) {
        case .saved:
            status = .saved
            return true
        case let .failed(message):
            status = .failed(message: message)
            return false
        case .conflicted:
            status = .conflicted
            return false
        }
    }

    private func cancelPendingTask() {
        pendingRequestID = UUID()
        pendingTask?.cancel()
        pendingTask = nil
    }

    deinit {
        pendingTask?.cancel()
    }
}
