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

    init(receiptStore: WatchCommandReceiptStore) {
        self.receiptStore = receiptStore
    }

    init() {
        self.receiptStore = UserDefaultsWatchCommandReceiptStore()
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
        try AppCloudSync.requireUserWritesAllowed()

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
        let taskRepository = SwiftDataTaskRepository(context: context)
        guard try taskRepository.task(id: taskID) != nil else {
            return .missingTask(taskID)
        }

        let segmentID = try SystemActionCommandHandler().startTimer(
            taskID: taskID,
            allowParallelTimers: allowParallelTimers,
            source: .watch,
            context: context
        )
        guard let segmentID else { return .invalid }
        receiptStore.markProcessed(command.id)
        return .started(segmentID)
    }

    private func stopSegment(
        _ command: WatchTimerCommand,
        context: ModelContext
    ) throws -> WatchCommandProcessingResult {
        guard let segmentID = command.segmentID else { return .invalid }
        let timeRepository = SwiftDataTimeTrackingRepository(context: context)
        guard let segment = try timeRepository.activeSegments().first(where: { $0.id == segmentID }) else {
            return .missingSegment(segmentID)
        }
        try context.performAtomicMutation {
            let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository)
            try TimerCommandHandler().stop(
                segment: segment,
                pomodoroRuns: try pomodoroRepository.runs(),
                timeRepository: timeRepository,
                context: context
            )
        }
        receiptStore.markProcessed(command.id)
        return .stopped(segmentID)
    }
}
