import Foundation
import SwiftData

enum StoreScopedInboxMutationError: LocalizedError, Equatable {
    case inboxChanged
    case taskUnavailable
    case categoryUnavailable
    case externalCommandPayloadChanged
    case externalCommandKeyConflict

    var errorDescription: String? {
        switch self {
        case .inboxChanged:
            AppStrings.localized("inbox.error.changed")
        case .taskUnavailable:
            AppStrings.localized("inbox.route.error.taskUnavailable")
        case .categoryUnavailable:
            AppStrings.localized("taskCategory.error.unavailable")
        case .externalCommandPayloadChanged:
            AppStrings.localized("inbox.error.externalCommandPayloadChanged")
        case .externalCommandKeyConflict:
            AppStrings.localized("inbox.error.externalCommandKeyConflict")
        }
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

struct InboxItemMutationBaseline: Equatable, Sendable {
    let itemID: UUID
    let clientMutationID: UUID

    init(item: InboxItem) {
        itemID = item.id
        clientMutationID = item.clientMutationID
    }
}

/// Serializes every Inbox command with the other store-scoped writers. The
/// canonical item set and every item revision are revalidated only after the
/// lock is held in a fresh context.
@MainActor
struct StoreScopedInboxCommandCoordinator {
    let session: StoreMutationSession
    let deviceID: String
    let nowProvider: () -> Date

    init(
        session: StoreMutationSession,
        deviceID: String = DeviceIdentity.current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func reorder(orderedItemIDs: [UUID]) throws -> InboxMutationOutcome {
        try withFreshLockedContext { context in
            let items = try openItems(context: context)
            let currentOrder = Self.ordered(items).map(\.id)
            guard orderedItemIDs.count == items.count,
                  Set(orderedItemIDs) == Set(items.map(\.id))
            else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            guard currentOrder != orderedItemIDs else {
                return InboxMutationOutcome(
                    affectedItemIDs: Set(orderedItemIDs),
                    didMutate: false
                )
            }
            try reorderOpenItems(
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

    func toggle(itemID: UUID) throws -> InboxMutationOutcome {
        try mutateItem(itemID: itemID) { item, context in
            try toggle(
                item,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func updateTitle(
        itemID: UUID,
        title: String
    ) throws -> InboxMutationOutcome {
        try mutateItem(itemID: itemID) { item, context in
            try updateTitle(
                item,
                title: title,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func delete(itemID: UUID) throws -> InboxMutationOutcome {
        try mutateItem(itemID: itemID) { item, context in
            try softDelete(
                item,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func discardSuggestion(itemID: UUID) throws -> InboxMutationOutcome {
        try mutateItem(itemID: itemID) { item, context in
            try discardSuggestion(
                item,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func withFreshLockedContext<Outcome>(
        _ operation: (ModelContext) throws -> Outcome
    ) throws -> Outcome {
        try session.withFreshMutationContext(operation)
    }

    private func mutateItem(
        itemID: UUID,
        operation: (InboxItem, ModelContext) throws -> Void
    ) throws -> InboxMutationOutcome {
        try withFreshLockedContext { context in
            guard let item = try visibleItem(id: itemID, context: context) else {
                throw StoreScopedInboxMutationError.inboxChanged
            }
            let mutationIDBeforeOperation = item.clientMutationID
            try operation(item, context)
            return InboxMutationOutcome(
                affectedItemIDs: [item.id],
                didMutate: item.clientMutationID != mutationIDBeforeOperation
            )
        }
    }

    func openItems(context: ModelContext) throws -> [InboxItem] {
        try InboxSuggestionIdentityService.visibleLogicalItems(
            from: context.fetch(FetchDescriptor<InboxItem>())
        )
        .filter { $0.isCompleted == false }
    }

    func visibleItem(id: UUID, context: ModelContext) throws -> InboxItem? {
        try InboxSuggestionIdentityService.visibleLogicalItems(
            from: context.fetch(FetchDescriptor<InboxItem>())
        )
        .first { $0.id == id }
    }

    private static func ordered(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id < rhs.id
        }
    }
}
