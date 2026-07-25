import Foundation

struct AppleHealthTaskCatalogMutationOutcome: Equatable {
    let createdCategoryIDs: [UUID]
    let restoredCategoryIDs: [UUID]
    let createdTaskIDs: [UUID]
    let restoredTaskIDs: [UUID]
    let restoredAssignmentIDs: [UUID]
    let consumedClearRecoveryTaskIDs: Set<UUID>

    var didMutate: Bool {
        createdCategoryIDs.isEmpty == false ||
            restoredCategoryIDs.isEmpty == false ||
            createdTaskIDs.isEmpty == false ||
            restoredTaskIDs.isEmpty == false ||
            restoredAssignmentIDs.isEmpty == false
    }

    var events: Set<StoreDomainEvent> {
        didMutate
            ? [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
            : []
    }

    static let noChanges = AppleHealthTaskCatalogMutationOutcome(
        createdCategoryIDs: [],
        restoredCategoryIDs: [],
        createdTaskIDs: [],
        restoredTaskIDs: [],
        restoredAssignmentIDs: [],
        consumedClearRecoveryTaskIDs: []
    )
}

enum AppleHealthTaskCatalogMutationCheckpoint: Equatable {
    case categoryCreated(UUID)
    case categoryRestored(UUID)
    case taskCreated(UUID)
    case taskRestored(UUID)
    case assignmentRestored(UUID)
}

enum AppleHealthTaskCatalogMutationError: LocalizedError, Equatable {
    case generatedAssignmentUnavailable

    var errorDescription: String? {
        switch self {
        case .generatedAssignmentUnavailable:
            AppStrings.localized(
                "health.taskSetup.error.generatedAssignmentUnavailable"
            )
        }
    }
}

extension AppleHealthTaskCatalogMutationOutcome {
    func appendingCreatedCategory(
        _ id: UUID
    ) -> AppleHealthTaskCatalogMutationOutcome {
        replacing(createdCategoryIDs: createdCategoryIDs + [id])
    }

    func appendingRestoredCategory(
        _ id: UUID
    ) -> AppleHealthTaskCatalogMutationOutcome {
        replacing(restoredCategoryIDs: restoredCategoryIDs + [id])
    }

    func appendingCreatedTask(
        _ id: UUID
    ) -> AppleHealthTaskCatalogMutationOutcome {
        replacing(createdTaskIDs: createdTaskIDs + [id])
    }

    func appendingRestoredTask(
        _ id: UUID
    ) -> AppleHealthTaskCatalogMutationOutcome {
        replacing(restoredTaskIDs: restoredTaskIDs + [id])
    }

    func appendingRestoredAssignment(
        _ id: UUID
    ) -> AppleHealthTaskCatalogMutationOutcome {
        replacing(restoredAssignmentIDs: restoredAssignmentIDs + [id])
    }

    func consumingClearRecoveryTask(
        _ id: UUID
    ) -> AppleHealthTaskCatalogMutationOutcome {
        replacing(
            consumedClearRecoveryTaskIDs:
            consumedClearRecoveryTaskIDs.union([id])
        )
    }

    private func replacing(
        createdCategoryIDs: [UUID]? = nil,
        restoredCategoryIDs: [UUID]? = nil,
        createdTaskIDs: [UUID]? = nil,
        restoredTaskIDs: [UUID]? = nil,
        restoredAssignmentIDs: [UUID]? = nil,
        consumedClearRecoveryTaskIDs: Set<UUID>? = nil
    ) -> AppleHealthTaskCatalogMutationOutcome {
        AppleHealthTaskCatalogMutationOutcome(
            createdCategoryIDs: createdCategoryIDs ?? self.createdCategoryIDs,
            restoredCategoryIDs:
            restoredCategoryIDs ?? self.restoredCategoryIDs,
            createdTaskIDs: createdTaskIDs ?? self.createdTaskIDs,
            restoredTaskIDs: restoredTaskIDs ?? self.restoredTaskIDs,
            restoredAssignmentIDs:
            restoredAssignmentIDs ?? self.restoredAssignmentIDs,
            consumedClearRecoveryTaskIDs:
            consumedClearRecoveryTaskIDs ??
                self.consumedClearRecoveryTaskIDs
        )
    }
}
