import Foundation
import SwiftData

struct CountdownMutationBaseline: Equatable, Sendable {
    let eventID: UUID
    let clientMutationID: UUID

    init(event: CountdownEvent) {
        eventID = event.id
        clientMutationID = event.clientMutationID
    }
}

enum StoreScopedCountdownMutationError: LocalizedError, Equatable {
    case eventUnavailable
    case eventChanged

    var errorDescription: String? {
        switch self {
        case .eventUnavailable:
            AppStrings.localized("settings.countdown.error.unavailable")
        case .eventChanged:
            AppStrings.localized("settings.countdown.error.changed")
        }
    }
}

/// Serializes countdown edits with the rest of the store mutation domain and
/// resolves the logical event only after the lock is held. A scene must not
/// write through an older SwiftData object after another scene has updated or
/// tombstoned the same logical event.
@MainActor
struct StoreScopedCountdownCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String
    let nowProvider: () -> Date

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String = DeviceIdentity.current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func update(
        baseline: CountdownMutationBaseline,
        title: String?,
        date: Date?
    ) throws {
        try mutate(baseline: baseline) { event, context in
            try CountdownCommandHandler().update(
                event,
                title: title,
                date: date,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func delete(baseline: CountdownMutationBaseline) throws {
        try mutate(baseline: baseline) { event, context in
            try CountdownCommandHandler().softDelete(
                event,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    private func mutate(
        baseline: CountdownMutationBaseline,
        operation: (CountdownEvent, ModelContext) throws -> Void
    ) throws {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        try transaction.withFreshContext { context in
            let eventID = baseline.eventID
            let descriptor = FetchDescriptor<CountdownEvent>(
                predicate: #Predicate { $0.id == eventID }
            )
            guard let event = try context.fetch(descriptor)
                .deduplicatedByID()
                .first(where: { $0.id == eventID }),
                  event.deletedAt == nil else {
                throw StoreScopedCountdownMutationError.eventUnavailable
            }
            guard event.clientMutationID == baseline.clientMutationID else {
                throw StoreScopedCountdownMutationError.eventChanged
            }
            try operation(event, context)
        }
    }
}
