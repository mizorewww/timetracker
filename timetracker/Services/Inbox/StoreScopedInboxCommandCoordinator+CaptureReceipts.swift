import Foundation
import SwiftData

@MainActor
extension StoreScopedInboxCommandCoordinator {
    func add(title: String) throws -> InboxMutationOutcome {
        try add(command: InboxCaptureCommand(title: title))
    }

    func add(command: InboxCaptureCommand) throws -> InboxMutationOutcome {
        try withFreshLockedContext { context in
            let trimmedTitle = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else {
                return InboxMutationOutcome(affectedItemIDs: [], didMutate: false)
            }
            let payloadFingerprint = try command.payloadFingerprint()
            if let externalCommandKey = command.externalCommandKey,
               let receipt = try activeCaptureReceipt(
                   for: externalCommandKey,
                   context: context
               ) {
                guard receipt.payloadFingerprint == payloadFingerprint else {
                    throw StoreScopedInboxMutationError.externalCommandPayloadChanged
                }
                return InboxMutationOutcome(
                    affectedItemIDs: [receipt.inboxItemID],
                    didMutate: false
                )
            }

            let items = try openItems(context: context)
            guard let item = try InboxCommandHandler().add(
                title: command.title,
                existingItems: items,
                context: context,
                deviceID: deviceID
            ) else {
                return InboxMutationOutcome(affectedItemIDs: [], didMutate: false)
            }
            if let externalCommandKey = command.externalCommandKey {
                context.insert(InboxCaptureReceipt(
                    commandKey: externalCommandKey.storageValue,
                    payloadFingerprint: payloadFingerprint,
                    inboxItemID: item.id,
                    createdAt: nowProvider(),
                    deviceID: deviceID
                ))
            }
            return InboxMutationOutcome(affectedItemIDs: [item.id], didMutate: true)
        }
    }

    private func activeCaptureReceipt(
        for externalCommandKey: ExternalCommandKey,
        context: ModelContext
    ) throws -> InboxCaptureReceipt? {
        let matching = try context.fetch(FetchDescriptor<InboxCaptureReceipt>())
            .filter {
                $0.commandKey == externalCommandKey.storageValue && $0.deletedAt == nil
            }
        return matching.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
