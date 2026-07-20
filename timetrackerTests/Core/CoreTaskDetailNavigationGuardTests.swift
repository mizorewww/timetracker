import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct CoreTaskDetailNavigationGuardTests {
    @Test
    func cleanWorkspaceNavigatesImmediately() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var didNavigate = false
        var didRequestConfirmation = false

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { false },
            requestDiscardConfirmation: { _ in didRequestConfirmation = true },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation {
            didNavigate = true
        }

        #expect(didNavigate)
        #expect(didRequestConfirmation == false)
    }

    @Test
    func dirtyWorkspaceFlushesBeforeDecidingWhetherNavigationNeedsConfirmation() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var isDirty = true
        var events: [String] = []
        var didRequestConfirmation = false

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            prepareForNavigation: {
                events.append("flush")
                isDirty = false
            },
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in
                didRequestConfirmation = true
            },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation {
            events.append("navigate")
        }

        #expect(events == ["flush", "navigate"])
        #expect(didRequestConfirmation == false)
    }

    @Test
    func failedFlushKeepsDirtyWorkspaceBehindDiscardProtection() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var didNavigate = false
        var didRequestConfirmation = false

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            prepareForNavigation: {},
            hasUnsavedChanges: { true },
            requestDiscardConfirmation: { _ in
                didRequestConfirmation = true
            },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation {
            didNavigate = true
        }

        #expect(didNavigate == false)
        #expect(didRequestConfirmation)
        #expect(guardCoordinator.hasPendingNavigation)
    }

    @Test
    func dirtyWorkspaceDefersNavigationUntilDiscardCompletes() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var isDirty = true
        var didNavigate = false
        var didRequestConfirmation = false
        var didDismissDetail = false

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in didRequestConfirmation = true },
            dismissDetail: { didDismissDetail = true }
        )
        guardCoordinator.requestNavigation(dismissingActiveDetail: true) {
            didNavigate = true
        }

        #expect(didRequestConfirmation)
        #expect(didNavigate == false)
        #expect(didDismissDetail == false)

        isDirty = false
        guardCoordinator.completePendingNavigation(id: registrationID)
        #expect(didDismissDetail)
        #expect(didNavigate)
    }

    @Test
    func cancellingDiscardAlsoCancelsThePendingNavigation() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var didNavigate = false

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { true },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation {
            didNavigate = true
        }
        guardCoordinator.cancelPendingNavigation(id: registrationID)
        guardCoordinator.completePendingNavigation(id: registrationID)

        #expect(didNavigate == false)
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func dirtyProtectionReadsTheLiveRegisteredWorkspaceState() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        let taskID = UUID()
        var isDirty = true

        guardCoordinator.register(
            id: registrationID,
            taskID: taskID,
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )

        #expect(guardCoordinator.protectsUnsavedChanges(for: taskID))

        isDirty = false

        #expect(guardCoordinator.protectsUnsavedChanges(for: taskID) == false)
    }

    @Test
    func predismissingUnavailableDetailStillCompletesRequestedNavigation() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        let currentTaskID = UUID()
        let nextTaskID = UUID()
        var isDirty = true
        var presentedTaskID: UUID? = currentTaskID

        guardCoordinator.register(
            id: registrationID,
            taskID: currentTaskID,
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in },
            dismissDetail: { presentedTaskID = nil }
        )
        guardCoordinator.requestNavigation(dismissingActiveDetail: true) {
            presentedTaskID = nextTaskID
        }

        isDirty = false
        presentedTaskID = nil
        guardCoordinator.completePendingNavigation(id: registrationID)

        #expect(presentedTaskID == nextTaskID)
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func sameWorkspaceReregistrationPreservesPendingNavigation() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        let taskID = UUID()
        var isDirty = true
        var navigationCount = 0

        guardCoordinator.register(
            id: registrationID,
            taskID: taskID,
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation {
            navigationCount += 1
        }
        guardCoordinator.register(
            id: registrationID,
            taskID: taskID,
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )

        #expect(guardCoordinator.hasPendingNavigation)
        isDirty = false
        guardCoordinator.completePendingNavigation(id: registrationID)

        #expect(navigationCount == 1)
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func replacementWorkspaceCancelsTheOldPendingNavigation() {
        let guardCoordinator = TaskDetailNavigationGuard()
        let firstRegistrationID = UUID()
        let secondRegistrationID = UUID()
        var navigationCount = 0

        guardCoordinator.register(
            id: firstRegistrationID,
            taskID: UUID(),
            hasUnsavedChanges: { true },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation {
            navigationCount += 1
        }
        guardCoordinator.register(
            id: secondRegistrationID,
            taskID: UUID(),
            hasUnsavedChanges: { false },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )

        guardCoordinator.completePendingNavigation(id: firstRegistrationID)
        guardCoordinator.completePendingNavigation(id: secondRegistrationID)

        #expect(navigationCount == 0)
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func registrationTokenUnregistersWhenItsWorkspaceLifetimeEnds() {
        let guardCoordinator = TaskDetailNavigationGuard()
        var token: TaskDetailNavigationRegistrationToken? =
            TaskDetailNavigationRegistrationToken()
        let taskID = UUID()

        token?.attach(to: guardCoordinator)
        guardCoordinator.register(
            id: token?.id ?? UUID(),
            taskID: taskID,
            hasUnsavedChanges: { false },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        #expect(guardCoordinator.activeTaskID == taskID)

        token = nil

        #expect(guardCoordinator.activeTaskID == nil)
    }

    @Test
    func scenePresentedConfirmationDiscardsBeforeNavigating() throws {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var isDirty = true
        var didRequestSourceConfirmation = false
        var discardCount = 0
        var navigationCount = 0

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { isDirty },
            discardChanges: {
                isDirty = false
                discardCount += 1
                return true
            },
            requestDiscardConfirmation: { _ in
                didRequestSourceConfirmation = true
            },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation(
            presentingConfirmationInSource: false
        ) {
            navigationCount += 1
        }

        #expect(guardCoordinator.hasPendingNavigation)
        #expect(didRequestSourceConfirmation == false)
        #expect(navigationCount == 0)

        let requestID = try #require(guardCoordinator.pendingNavigationID)
        guardCoordinator.discardChangesAndCompletePendingNavigation(
            requestID: requestID
        )

        #expect(discardCount == 1)
        #expect(navigationCount == 1)
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func failedPreparationPreservesDirtyChangesAndCancelsNavigation() throws {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var isDirty = true
        var events: [String] = []

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { isDirty },
            discardChanges: {
                isDirty = false
                events.append("discard")
                return true
            },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation(
            beforeDiscardingChanges: {
                events.append("prepare")
                return false
            }
        ) {
            events.append("navigate")
        }

        let requestID = try #require(guardCoordinator.pendingNavigationID)
        let didComplete = guardCoordinator
            .discardChangesAndCompletePendingNavigation(
                requestID: requestID
            )

        #expect(didComplete == false)
        #expect(isDirty)
        #expect(events == ["prepare"])
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func failedDiscardPreservesDirtyChangesAndCancelsNavigation() throws {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var isDirty = true
        var events: [String] = []

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { isDirty },
            discardChanges: {
                events.append("discard-failed")
                return false
            },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation {
            isDirty = false
            events.append("navigate")
        }

        let requestID = try #require(guardCoordinator.pendingNavigationID)
        let didComplete = guardCoordinator
            .discardChangesAndCompletePendingNavigation(
                requestID: requestID
            )

        #expect(didComplete == false)
        #expect(isDirty)
        #expect(events == ["discard-failed"])
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func successfulPreparationCommitsBeforeDiscardAndNavigation() throws {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var isDirty = true
        var events: [String] = []

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { isDirty },
            discardChanges: {
                isDirty = false
                events.append("discard")
                return true
            },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        guardCoordinator.requestNavigation(
            beforeDiscardingChanges: {
                events.append("prepare")
                return true
            }
        ) {
            events.append("navigate")
        }

        let requestID = try #require(guardCoordinator.pendingNavigationID)
        let didComplete = guardCoordinator
            .discardChangesAndCompletePendingNavigation(
                requestID: requestID
            )

        #expect(didComplete)
        #expect(isDirty == false)
        #expect(events == ["prepare", "discard", "navigate"])
        #expect(guardCoordinator.hasPendingNavigation == false)
    }

    @Test
    func replacingARequestDismissesItsConfirmationOwner() throws {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var dismissedSourceRequestID: UUID?
        var dismissedSceneRequestID: UUID?

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { true },
            requestDiscardConfirmation: { _ in },
            dismissDiscardConfirmation: {
                dismissedSourceRequestID = $0
            },
            dismissDetail: {}
        )
        let sourceRequestID = try #require(
            guardCoordinator.requestNavigation {}
        )
        let sceneRequestID = try #require(
            guardCoordinator.requestNavigation(
                presentingConfirmationInSource: false,
                dismissPresentedConfirmation: {
                    dismissedSceneRequestID = $0
                }
            ) {}
        )

        #expect(dismissedSourceRequestID == sourceRequestID)
        #expect(guardCoordinator.pendingNavigationID == sceneRequestID)

        _ = guardCoordinator.requestNavigation {}

        #expect(dismissedSceneRequestID == sceneRequestID)
    }

    @Test
    func staleConfirmationDismissalCannotCancelReplacementRequest() throws {
        let guardCoordinator = TaskDetailNavigationGuard()
        let registrationID = UUID()
        var replacementNavigationCount = 0

        guardCoordinator.register(
            id: registrationID,
            taskID: UUID(),
            hasUnsavedChanges: { true },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )
        let staleRequestID = try #require(
            guardCoordinator.requestNavigation {}
        )
        let replacementRequestID = try #require(
            guardCoordinator.requestNavigation {
                replacementNavigationCount += 1
            }
        )

        guardCoordinator.cancelPendingNavigation(requestID: staleRequestID)

        #expect(guardCoordinator.pendingNavigationID == replacementRequestID)
        guardCoordinator.completePendingNavigation(
            requestID: replacementRequestID
        )
        #expect(replacementNavigationCount == 1)
    }
}
