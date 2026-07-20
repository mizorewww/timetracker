import Foundation
import Observation

@MainActor
@Observable
final class TaskDetailNavigationGuard {
    private struct Registration {
        let id: UUID
        let taskID: UUID
        let prepareForNavigation: () -> Void
        let hasUnsavedChanges: () -> Bool
        let discardChanges: () -> Bool
        let requestDiscardConfirmation: (UUID) -> Void
        let dismissDiscardConfirmation: (UUID) -> Void
        let dismissDetail: () -> Void
    }

    private struct PendingNavigation {
        let id: UUID
        let dismissesActiveDetail: Bool
        let beforeDiscardingChanges: () -> Bool
        let dismissConfirmation: () -> Void
        let navigate: () -> Void
    }

    @ObservationIgnored private var registration: Registration?
    @ObservationIgnored private var pendingNavigation: PendingNavigation?
    private(set) var hasPendingNavigation = false
    private(set) var pendingNavigationID: UUID?

    var activeTaskID: UUID? {
        registration?.taskID
    }

    func register(
        id: UUID,
        taskID: UUID,
        prepareForNavigation: @escaping () -> Void = {},
        hasUnsavedChanges: @escaping () -> Bool,
        discardChanges: @escaping () -> Bool = { true },
        requestDiscardConfirmation: @escaping (UUID) -> Void,
        dismissDiscardConfirmation: @escaping (UUID) -> Void = { _ in },
        dismissDetail: @escaping () -> Void
    ) {
        if registration?.id != id {
            cancelPendingNavigation()
        }
        registration = Registration(
            id: id,
            taskID: taskID,
            prepareForNavigation: prepareForNavigation,
            hasUnsavedChanges: hasUnsavedChanges,
            discardChanges: discardChanges,
            requestDiscardConfirmation: requestDiscardConfirmation,
            dismissDiscardConfirmation: dismissDiscardConfirmation,
            dismissDetail: dismissDetail
        )
    }

    func unregister(id: UUID) {
        guard registration?.id == id else { return }
        registration = nil
        cancelPendingNavigation()
    }

    func protectsUnsavedChanges(for taskID: UUID) -> Bool {
        guard let registration, registration.taskID == taskID else {
            return false
        }
        return registration.hasUnsavedChanges()
    }

    @discardableResult
    func requestNavigation(
        dismissingActiveDetail: Bool = false,
        presentingConfirmationInSource: Bool = true,
        dismissPresentedConfirmation: @escaping (UUID) -> Void = { _ in },
        beforeDiscardingChanges: @escaping () -> Bool = { true },
        _ navigate: @escaping () -> Void
    ) -> UUID? {
        guard let registration else {
            cancelPendingNavigation()
            guard beforeDiscardingChanges() else { return nil }
            navigate()
            return nil
        }
        registration.prepareForNavigation()
        guard registration.hasUnsavedChanges() else {
            cancelPendingNavigation()
            guard beforeDiscardingChanges() else { return nil }
            if dismissingActiveDetail {
                registration.dismissDetail()
            }
            navigate()
            return nil
        }

        cancelPendingNavigation()
        let requestID = UUID()
        let dismissConfirmation = presentingConfirmationInSource
            ? { registration.dismissDiscardConfirmation(requestID) }
            : { dismissPresentedConfirmation(requestID) }
        pendingNavigation = PendingNavigation(
            id: requestID,
            dismissesActiveDetail: dismissingActiveDetail,
            beforeDiscardingChanges: beforeDiscardingChanges,
            dismissConfirmation: dismissConfirmation,
            navigate: navigate
        )
        pendingNavigationID = requestID
        hasPendingNavigation = true
        if presentingConfirmationInSource {
            registration.requestDiscardConfirmation(requestID)
        }
        return requestID
    }

    func cancelPendingNavigation(id: UUID) {
        guard registration?.id == id else { return }
        cancelPendingNavigation()
    }

    func cancelPendingNavigation() {
        cancelPendingNavigationState()
    }

    func cancelPendingNavigation(requestID: UUID) {
        guard pendingNavigation?.id == requestID else { return }
        cancelPendingNavigationState()
    }

    func completePendingNavigation(id: UUID) {
        guard registration?.id == id else { return }
        completePendingNavigation()
    }

    func completePendingNavigation(requestID: UUID) {
        guard pendingNavigation?.id == requestID else { return }
        completePendingNavigation()
    }

    @discardableResult
    func discardChangesAndCompletePendingNavigation(requestID: UUID) -> Bool {
        guard let registration,
              let pendingNavigation,
              pendingNavigation.id == requestID else { return false }
        guard pendingNavigation.beforeDiscardingChanges() else {
            cancelPendingNavigationState()
            return false
        }
        guard registration.discardChanges() else {
            cancelPendingNavigationState()
            return false
        }
        completePreparedPendingNavigation()
        return true
    }

    private func completePendingNavigation() {
        guard let pendingNavigation else { return }
        guard pendingNavigation.beforeDiscardingChanges() else {
            cancelPendingNavigationState()
            return
        }
        completePreparedPendingNavigation()
    }

    private func completePreparedPendingNavigation() {
        guard let registration, let pending = takePendingNavigation() else { return }
        if pending.dismissesActiveDetail {
            registration.dismissDetail()
        }
        pending.navigate()
    }

    private func cancelPendingNavigationState() {
        _ = takePendingNavigation()
    }

    private func takePendingNavigation() -> PendingNavigation? {
        guard let pending = pendingNavigation else {
            pendingNavigationID = nil
            hasPendingNavigation = false
            return nil
        }
        pendingNavigation = nil
        pendingNavigationID = nil
        hasPendingNavigation = false
        pending.dismissConfirmation()
        return pending
    }
}

@MainActor
final class TaskDetailNavigationRegistrationToken {
    let id = UUID()
    private weak var navigationGuard: TaskDetailNavigationGuard?

    func attach(to navigationGuard: TaskDetailNavigationGuard) {
        if let currentGuard = self.navigationGuard,
           currentGuard !== navigationGuard {
            currentGuard.unregister(id: id)
        }
        self.navigationGuard = navigationGuard
    }

    func unregister() {
        navigationGuard?.unregister(id: id)
        navigationGuard = nil
    }

    deinit {
        MainActor.assumeIsolated {
            navigationGuard?.unregister(id: id)
        }
    }
}
