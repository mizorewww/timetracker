import Foundation

nonisolated struct WatchTimerCommand: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var type: WatchTimerCommandType
    var taskID: UUID?
    var segmentID: UUID?
    var issuedAt: Date
    var deviceID: String

    nonisolated func isReflected(in snapshot: WatchStateSnapshot) -> Bool {
        // Ignore an application context generated before this command was issued.
        guard snapshot.generatedAt >= issuedAt else { return false }

        switch type {
        case .startTask:
            guard let taskID else { return false }
            return snapshot.activeTimers.contains { $0.taskID == taskID }
        case .stopSegment:
            guard let segmentID else { return false }
            return snapshot.activeTimers.contains { $0.id == segmentID } == false
        }
    }
}

nonisolated extension WatchTimerCommand {
    func targetsSameAction(as other: WatchTimerCommand) -> Bool {
        type == other.type && taskID == other.taskID && segmentID == other.segmentID
    }

    var isStructurallyValid: Bool {
        guard WatchTransportLimits.isFinite(issuedAt),
              deviceID.isEmpty == false,
              WatchTransportLimits.isBounded(
                deviceID,
                maximumUTF8Bytes: WatchTransportLimits.maximumDeviceIDBytes
              ) else {
            return false
        }
        switch type {
        case .startTask:
            return taskID != nil && segmentID == nil
        case .stopSegment:
            return taskID == nil && segmentID != nil
        }
    }

    func isValid(at now: Date) -> Bool {
        guard isStructurallyValid, WatchTransportLimits.isFinite(now) else { return false }
        let age = now.timeIntervalSince(issuedAt)
        return age.isFinite &&
            age >= -WatchTransportLimits.maximumFutureClockSkew &&
            age <= WatchTransportLimits.maximumCommandAge
    }
}

nonisolated enum WatchTimerCommandType: String, Codable, Equatable, Sendable {
    case startTask
    case stopSegment
}

nonisolated enum WatchCommandProcessingResult: Equatable, Sendable {
    case started(UUID)
    case stopped(UUID)
    case duplicate(UUID)
    case missingTask(UUID)
    case missingSegment(UUID)
    case invalid

    var isProcessed: Bool {
        switch self {
        case .started, .stopped:
            return true
        case .duplicate, .missingTask, .missingSegment, .invalid:
            return false
        }
    }
}

/// A terminal acknowledgement for one command submitted by Apple Watch.
///
/// `commandID` is the idempotency key. Retrying a failed or timed-out command
/// keeps that identifier so a command that actually completed cannot run twice.
nonisolated struct WatchCommandResult: Codable, Equatable, Identifiable, Sendable {
    var commandID: UUID
    var status: WatchCommandResultStatus
    var completedAt: Date
    var relatedID: UUID?
    var failureCode: String?

    var id: UUID { commandID }

    var completesWithoutUserAction: Bool {
        status == .success || status == .duplicate
    }

    static func failed(
        commandID: UUID,
        completedAt: Date = Date(),
        failureCode: String = "processing"
    ) -> WatchCommandResult {
        WatchCommandResult(
            commandID: commandID,
            status: .failed,
            completedAt: completedAt,
            relatedID: nil,
            failureCode: failureCode
        )
    }
}

nonisolated extension WatchCommandResult {
    var isStructurallyValid: Bool {
        guard WatchTransportLimits.isFinite(completedAt) else { return false }
        guard let failureCode else { return true }
        return WatchTransportLimits.isBounded(
            failureCode,
            maximumUTF8Bytes: WatchTransportLimits.maximumFailureCodeBytes
        )
    }

    func isValid(at now: Date) -> Bool {
        guard isStructurallyValid, WatchTransportLimits.isFinite(now) else { return false }
        return completedAt.timeIntervalSince(now) <= WatchTransportLimits.maximumFutureClockSkew
    }
}

nonisolated enum WatchCommandResultStatus: String, Codable, Equatable, Sendable {
    case success
    case duplicate
    case missingTask
    case missingSegment
    case invalid
    case failed
    case timeout
}

nonisolated extension WatchCommandProcessingResult {
    func terminalResult(
        commandID: UUID,
        completedAt: Date = Date()
    ) -> WatchCommandResult {
        switch self {
        case .started(let segmentID), .stopped(let segmentID):
            WatchCommandResult(
                commandID: commandID,
                status: .success,
                completedAt: completedAt,
                relatedID: segmentID,
                failureCode: nil
            )
        case .duplicate:
            WatchCommandResult(
                commandID: commandID,
                status: .duplicate,
                completedAt: completedAt,
                relatedID: nil,
                failureCode: nil
            )
        case .missingTask(let taskID):
            WatchCommandResult(
                commandID: commandID,
                status: .missingTask,
                completedAt: completedAt,
                relatedID: taskID,
                failureCode: nil
            )
        case .missingSegment(let segmentID):
            WatchCommandResult(
                commandID: commandID,
                status: .missingSegment,
                completedAt: completedAt,
                relatedID: segmentID,
                failureCode: nil
            )
        case .invalid:
            WatchCommandResult(
                commandID: commandID,
                status: .invalid,
                completedAt: completedAt,
                relatedID: nil,
                failureCode: nil
            )
        }
    }
}

nonisolated struct WatchFailedCommand: Codable, Equatable, Identifiable, Sendable {
    var command: WatchTimerCommand
    var result: WatchCommandResult

    var id: UUID { command.id }
}

/// Pure, codable command lifecycle state shared by the watch UI and unit tests.
/// Persistence lets an interrupted watch launch recover pending and retryable
/// actions instead of silently forgetting them.
nonisolated struct WatchCommandQueueState: Codable, Equatable, Sendable {
    private(set) var pendingCommands: [WatchTimerCommand] = []
    private(set) var failedCommands: [WatchFailedCommand] = []

    @discardableResult
    mutating func enqueue(_ command: WatchTimerCommand) -> Bool {
        let queuedCommands = pendingCommands + failedCommands.map(\.command)
        guard queuedCommands.allSatisfy({
            $0.id != command.id || $0.targetsSameAction(as: command)
        }), !queuedCommands.contains(where: {
            $0.id != command.id && $0.targetsSameAction(as: command)
        }) else {
            return false
        }
        pendingCommands.removeAll { $0.id == command.id }
        failedCommands.removeAll { $0.id == command.id }
        pendingCommands.append(command)
        let overflowCount = max(
            0,
            pendingCommands.count - WatchTransportLimits.maximumPersistedPendingCommands
        )
        guard overflowCount > 0 else { return true }
        let overflowedCommands = pendingCommands.prefix(overflowCount)
        pendingCommands.removeFirst(overflowCount)
        for overflowedCommand in overflowedCommands {
            appendFailedCommand(
                WatchFailedCommand(
                    command: overflowedCommand,
                    result: .failed(
                        commandID: overflowedCommand.id,
                        failureCode: "queueOverflow"
                    )
                )
            )
        }
        return true
    }

    @discardableResult
    mutating func resolve(_ result: WatchCommandResult) -> WatchTimerCommand? {
        let command = pendingCommands.first { $0.id == result.commandID }
            ?? failedCommands.first { $0.id == result.commandID }?.command
        guard let command else { return nil }

        pendingCommands.removeAll { $0.id == result.commandID }
        failedCommands.removeAll { $0.id == result.commandID }
        if !result.completesWithoutUserAction {
            appendFailedCommand(WatchFailedCommand(command: command, result: result))
        }
        return command
    }

    @discardableResult
    mutating func timeOut(
        commandID: UUID,
        completedAt: Date = Date()
    ) -> WatchCommandResult? {
        guard pendingCommands.contains(where: { $0.id == commandID }) else { return nil }
        let result = WatchCommandResult(
            commandID: commandID,
            status: .timeout,
            completedAt: completedAt,
            relatedID: nil,
            failureCode: nil
        )
        resolve(result)
        return result
    }

    @discardableResult
    mutating func retry(
        commandID: UUID,
        issuedAt: Date = Date()
    ) -> WatchTimerCommand? {
        guard var command = failedCommands.first(where: { $0.id == commandID })?.command else {
            return nil
        }
        command.issuedAt = issuedAt
        guard enqueue(command) else { return nil }
        return command
    }

    mutating func discard(commandID: UUID) {
        failedCommands.removeAll { $0.id == commandID }
    }

    /// Snapshot reflection remains as a compatibility fallback for older iPhone
    /// versions that don't send typed results.
    @discardableResult
    mutating func confirmReflectedCommands(in snapshot: WatchStateSnapshot) -> Set<UUID> {
        let commands = pendingCommands + failedCommands.map(\.command)
        let confirmedIDs = Set(
            commands.lazy
                .filter { $0.isReflected(in: snapshot) }
                .map(\.id)
        )
        guard !confirmedIDs.isEmpty else { return [] }
        pendingCommands.removeAll { confirmedIDs.contains($0.id) }
        failedCommands.removeAll { confirmedIDs.contains($0.id) }
        return confirmedIDs
    }

    var isSafeForRestoration: Bool {
        guard pendingCommands.count <= WatchTransportLimits.maximumPersistedPendingCommands,
              failedCommands.count <= WatchTransportLimits.maximumPersistedFailedCommands,
              pendingCommands.allSatisfy(\.isStructurallyValid),
              failedCommands.allSatisfy({
                  $0.command.isStructurallyValid &&
                      $0.result.isStructurallyValid &&
                      $0.command.id == $0.result.commandID
              }) else {
            return false
        }
        let commands = pendingCommands + failedCommands.map(\.command)
        guard Set(commands.map(\.id)).count == commands.count else { return false }
        return commands.indices.allSatisfy { index in
            !commands[..<index].contains { $0.targetsSameAction(as: commands[index]) }
        }
    }

    private mutating func appendFailedCommand(_ failedCommand: WatchFailedCommand) {
        failedCommands.removeAll { $0.id == failedCommand.id }
        failedCommands.append(failedCommand)
        let overflowCount = max(
            0,
            failedCommands.count - WatchTransportLimits.maximumPersistedFailedCommands
        )
        if overflowCount > 0 {
            failedCommands.removeFirst(overflowCount)
        }
    }
}
