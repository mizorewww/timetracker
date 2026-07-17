import Foundation
import SwiftData

struct InboxOrderMutationBaseline: Equatable, Sendable {
    let itemMutationIDs: [UUID: UUID]
    let orderedItemIDs: [UUID]

    init(items: [InboxItem]) {
        itemMutationIDs = items.reduce(into: [:]) { result, item in
            result[item.id] = item.clientMutationID
        }
        orderedItemIDs = Self.ordered(items).map(\.id)
    }

    private static func ordered(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

enum StoreScopedInboxMutationError: LocalizedError, Equatable {
    case inboxChanged

    var errorDescription: String? {
        AppStrings.localized("inbox.error.changed")
    }
}

struct InboxMutationOutcome: Equatable {
    let affectedItemIDs: Set<UUID>
    let didMutate: Bool

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [.inboxChanged(itemIDs: affectedItemIDs)]
    }
}

/// Serializes Inbox ordering with the other store-scoped writers. The visible
/// open set and every item revision are revalidated only after the lock is held.
@MainActor
struct StoreScopedInboxCommandCoordinator {
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

    func reorder(
        baseline: InboxOrderMutationBaseline,
        orderedItemIDs: [UUID]
    ) throws -> InboxMutationOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        return try transaction.withFreshContext { context in
            let items = try openItems(context: context)
            let currentMutationIDs = items.reduce(into: [UUID: UUID]()) {
                $0[$1.id] = $1.clientMutationID
            }
            let currentOrder = Self.ordered(items).map(\.id)
            guard currentMutationIDs == baseline.itemMutationIDs,
                  currentOrder == baseline.orderedItemIDs,
                  orderedItemIDs.count == items.count,
                  Set(orderedItemIDs) == Set(items.map(\.id)) else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            guard currentOrder != orderedItemIDs else {
                return InboxMutationOutcome(
                    affectedItemIDs: Set(orderedItemIDs),
                    didMutate: false
                )
            }
            try InboxCommandHandler().reorderOpenItems(
                orderedItemIDs: orderedItemIDs,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            return InboxMutationOutcome(
                affectedItemIDs: Set(orderedItemIDs),
                didMutate: true
            )
        }
    }

    private func openItems(context: ModelContext) throws -> [InboxItem] {
        InboxSuggestionIdentityService().visibleLogicalItems(
            from: try context.fetch(FetchDescriptor<InboxItem>())
        )
        .filter { $0.isCompleted == false }
    }

    private static func ordered(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
