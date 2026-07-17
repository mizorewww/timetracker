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
            if let externalCommandKey = command.externalCommandKey {
                let receipts = try activeCaptureReceipts(
                    for: externalCommandKey,
                    context: context
                )
                if let receipt = try replayReceipt(
                    from: receipts,
                    expectedPayloadFingerprint: payloadFingerprint
                ) {
                    return InboxMutationOutcome(
                        affectedItemIDs: [receipt.inboxItemID],
                        didMutate: false
                    )
                }
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

    private func replayReceipt(
        from receipts: [InboxCaptureReceipt],
        expectedPayloadFingerprint: String
    ) throws -> InboxCaptureReceipt? {
        guard !receipts.isEmpty else { return nil }
        let committedResults = Set(receipts.map {
            CaptureReceiptResult(
                payloadFingerprint: $0.payloadFingerprint,
                inboxItemID: $0.inboxItemID
            )
        })
        guard committedResults.count == 1 else {
            throw StoreScopedInboxMutationError.externalCommandKeyConflict
        }
        guard receipts[0].payloadFingerprint == expectedPayloadFingerprint else {
                    throw StoreScopedInboxMutationError.externalCommandPayloadChanged
                }
        return receipts.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func activeCaptureReceipts(
        for externalCommandKey: ExternalCommandKey,
        context: ModelContext
    ) throws -> [InboxCaptureReceipt] {
        let commandKey = externalCommandKey.storageValue
        return try context.fetch(
            FetchDescriptor<InboxCaptureReceipt>(
                predicate: #Predicate {
                    $0.commandKey == commandKey && $0.deletedAt == nil
                }
            )
        )
    }
}

private struct CaptureReceiptResult: Hashable {
    let payloadFingerprint: String
    let inboxItemID: UUID
}
