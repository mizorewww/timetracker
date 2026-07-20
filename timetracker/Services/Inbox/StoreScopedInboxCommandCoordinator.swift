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
            "An external Inbox capture command key was reused with different content."
        case .externalCommandKeyConflict:
            "An external Inbox capture command key has conflicting committed results."
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
        try withFreshLockedContext { context in
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

    func toggle(baseline: InboxItemMutationBaseline) throws -> InboxMutationOutcome {
        try mutateItem(baseline: baseline) { item, context in
            try InboxCommandHandler().toggle(
                item,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func updateTitle(
        baseline: InboxItemMutationBaseline,
        title: String
    ) throws -> InboxMutationOutcome {
        try mutateItem(baseline: baseline) { item, context in
            try InboxCommandHandler().updateTitle(
                item,
                title: title,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func delete(baseline: InboxItemMutationBaseline) throws -> InboxMutationOutcome {
        try mutateItem(baseline: baseline) { item, context in
            try InboxCommandHandler().softDelete(
                item,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
        }
    }

    func discardSuggestion(baseline: InboxItemMutationBaseline) throws -> InboxMutationOutcome {
        try mutateItem(baseline: baseline) { item, context in
            try InboxCommandHandler().discardSuggestion(
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
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        return try StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        ).withFreshContext(operation)
    }

    private func mutateItem(
        baseline: InboxItemMutationBaseline,
        operation: (InboxItem, ModelContext) throws -> Void
    ) throws -> InboxMutationOutcome {
        try withFreshLockedContext { context in
            guard let item = try visibleItem(id: baseline.itemID, context: context) else {
                throw StoreScopedInboxMutationError.inboxChanged
            }
            guard item.clientMutationID == baseline.clientMutationID else {
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
        InboxSuggestionIdentityService().visibleLogicalItems(
            from: try context.fetch(FetchDescriptor<InboxItem>())
        )
        .filter { $0.isCompleted == false }
    }

    func visibleItem(id: UUID, context: ModelContext) throws -> InboxItem? {
        InboxSuggestionIdentityService().visibleLogicalItems(
            from: try context.fetch(FetchDescriptor<InboxItem>())
        )
        .first { $0.id == id }
    }

    private static func ordered(_ items: [InboxItem]) -> [InboxItem] {
        items.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
