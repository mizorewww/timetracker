import Foundation
import SwiftData

protocol WatchCommandReceiptStore: AnyObject {
    func contains(_ commandID: UUID) -> Bool
    func markProcessed(_ commandID: UUID)
}

final class UserDefaultsWatchCommandReceiptStore: WatchCommandReceiptStore {
    private let defaults: UserDefaults
    private let key: String
    private let maxReceipts: Int

    init(
        defaults: UserDefaults = AppDefaults.shared,
        key: String = "watch.processedCommandIDs.v1",
        maxReceipts: Int = 512
    ) {
        self.defaults = defaults
        self.key = key
        self.maxReceipts = maxReceipts
    }

    func contains(_ commandID: UUID) -> Bool {
        receiptIDs.contains(commandID.uuidString)
    }

    func markProcessed(_ commandID: UUID) {
        var ids = receiptIDs
        ids.removeAll { $0 == commandID.uuidString }
        ids.insert(commandID.uuidString, at: 0)
        if ids.count > maxReceipts {
            ids = Array(ids.prefix(maxReceipts))
        }
        defaults.set(ids, forKey: key)
    }

    private var receiptIDs: [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}

final class InMemoryWatchCommandReceiptStore: WatchCommandReceiptStore {
    private var processedIDs: Set<UUID> = []

    func contains(_ commandID: UUID) -> Bool {
        processedIDs.contains(commandID)
    }

    func markProcessed(_ commandID: UUID) {
        processedIDs.insert(commandID)
    }
}

@MainActor
struct WatchCommandMutationOutcome {
    let result: WatchCommandProcessingResult
    let events: Set<StoreDomainEvent>
}

@MainActor
struct WatchCommandProcessor {
    var receiptStore: WatchCommandReceiptStore
    let writeAuthorization: StoreWriteAuthorization

    init(
        receiptStore: WatchCommandReceiptStore,
        writeAuthorization: StoreWriteAuthorization = .applicationState
    ) {
        self.receiptStore = receiptStore
        self.writeAuthorization = writeAuthorization
    }

    init(writeAuthorization: StoreWriteAuthorization = .applicationState) {
        receiptStore = UserDefaultsWatchCommandReceiptStore()
        self.writeAuthorization = writeAuthorization
    }

    func process(
        _ command: WatchTimerCommand,
        context: ModelContext,
        now: Date = Date()
    ) throws -> WatchCommandProcessingResult {
        try processWithMutationOutcome(command, context: context, now: now).result
    }

    func processWithMutationOutcome(
        _ command: WatchTimerCommand,
        context: ModelContext,
        now: Date = Date()
    ) throws -> WatchCommandMutationOutcome {
        guard receiptStore.contains(command.id) == false else {
            return WatchCommandMutationOutcome(
                result: .duplicate(command.id),
                events: []
            )
        }
        guard command.isValid(at: now) else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }

        switch command.type {
        case .startTask:
            return try startTask(command, context: context)
        case .stopSegment:
            return try stopSegment(command, context: context)
        }
    }

    private func startTask(
        _ command: WatchTimerCommand,
        context: ModelContext
    ) throws -> WatchCommandMutationOutcome {
        guard let taskID = command.taskID else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }
        let outcome: StoreScopedTimerCommandOutcome
        do {
            outcome = try SystemActionCommandHandler(
                writeAuthorization: writeAuthorization
            ).startTimerMutation(
                taskID: taskID,
                source: .watch,
                container: context.container
            )
        } catch SystemActionCommandError.taskNotFound {
            return WatchCommandMutationOutcome(
                result: .missingTask(taskID),
                events: []
            )
        }
        guard let segmentID = outcome.subjectSegmentID else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }
        receiptStore.markProcessed(command.id)
        return WatchCommandMutationOutcome(
            result: .started(segmentID),
            events: outcome.events
        )
    }

    private func stopSegment(
        _ command: WatchTimerCommand,
        context: ModelContext
    ) throws -> WatchCommandMutationOutcome {
        guard let segmentID = command.segmentID else {
            return WatchCommandMutationOutcome(result: .invalid, events: [])
        }
        let outcome = try SystemActionCommandHandler(
            writeAuthorization: writeAuthorization
        ).stopTimerMutation(
            segmentID: segmentID,
            container: context.container
        )
        guard outcome.subjectSegmentID == segmentID else {
            return WatchCommandMutationOutcome(
                result: .missingSegment(segmentID),
                events: []
            )
        }
        receiptStore.markProcessed(command.id)
        return WatchCommandMutationOutcome(
            result: .stopped(segmentID),
            events: outcome.events
        )
    }
}
