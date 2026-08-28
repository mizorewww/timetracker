import Foundation
import SwiftData

/// Serializes quantity progress writes with task editing, recurrence
/// materialization, timers, and sync snapshot transactions. Commands carry
/// value-semantic baselines; scene-owned SwiftData models never cross the
/// store lock.
@MainActor
struct StoreScopedTaskQuantityEntryCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String
    let nowProvider: () -> Date
    let didReachCheckpoint:
        (TaskQuantityEntryMutationCheckpoint) throws -> Void

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String = DeviceIdentity.current,
        nowProvider: @escaping () -> Date = Date.init,
        didReachCheckpoint: @escaping
        (TaskQuantityEntryMutationCheckpoint) throws -> Void = { _ in }
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.nowProvider = nowProvider
        self.didReachCheckpoint = didReachCheckpoint
    }

    func record(
        command: TaskQuantityEntryRecordCommand
    ) throws -> TaskQuantityEntryMutationOutcome {
        try withFreshState { context, state in
            try record(command: command, context: context, state: state)
        }
    }

    func update(
        command: TaskQuantityEntryUpdateCommand
    ) throws -> TaskQuantityEntryMutationOutcome {
        try withFreshState { _, state in
            try update(command: command, state: state)
        }
    }

    func delete(
        command: TaskQuantityEntryDeleteCommand
    ) throws -> TaskQuantityEntryMutationOutcome {
        try withFreshState { _, state in
            try delete(command: command, state: state)
        }
    }

    private func withFreshState<Result>(
        _ operation: (
            ModelContext,
            TaskQuantityEntryPersistenceState
        ) throws -> Result
    ) throws -> Result {
        try StoreScopedMutationSession(
            container: container,
            writeAuthorization: writeAuthorization
        ).withFreshMutationContext { context in
            try operation(
                context,
                TaskQuantityEntryPersistenceState(context: context)
            )
        }
    }
}
