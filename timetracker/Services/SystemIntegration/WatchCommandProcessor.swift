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
        defaults: UserDefaults = .standard,
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
        self.receiptStore = UserDefaultsWatchCommandReceiptStore()
        self.writeAuthorization = writeAuthorization
    }

    func process(
        _ command: WatchTimerCommand,
        allowParallelTimers: Bool,
        context: ModelContext,
        now: Date = Date()
    ) throws -> WatchCommandProcessingResult {
        guard receiptStore.contains(command.id) == false else {
            return .duplicate(command.id)
        }
        guard command.isValid(at: now) else {
            return .invalid
        }

        switch command.type {
        case .startTask:
            return try startTask(command, allowParallelTimers: allowParallelTimers, context: context)
        case .stopSegment:
            return try stopSegment(command, context: context)
        }
    }

    private func startTask(
        _ command: WatchTimerCommand,
        allowParallelTimers: Bool,
        context: ModelContext
    ) throws -> WatchCommandProcessingResult {
        guard let taskID = command.taskID else { return .invalid }
        let segmentID: UUID?
        do {
            segmentID = try SystemActionCommandHandler(
                writeAuthorization: writeAuthorization
            ).startTimerMutation(
                taskID: taskID,
                allowParallelTimers: allowParallelTimers,
                source: .watch,
                container: context.container
            ).subjectSegmentID
        } catch SystemActionCommandError.taskNotFound {
            return .missingTask(taskID)
        }
        guard let segmentID else { return .invalid }
        receiptStore.markProcessed(command.id)
        return .started(segmentID)
    }

    private func stopSegment(
        _ command: WatchTimerCommand,
        context: ModelContext
    ) throws -> WatchCommandProcessingResult {
        guard let segmentID = command.segmentID else { return .invalid }
        let stoppedID = try SystemActionCommandHandler(
            writeAuthorization: writeAuthorization
        ).stopTimerMutation(
            segmentID: segmentID,
            container: context.container
        ).subjectSegmentID
        guard stoppedID == segmentID else { return .missingSegment(segmentID) }
        receiptStore.markProcessed(command.id)
        return .stopped(segmentID)
    }
}
