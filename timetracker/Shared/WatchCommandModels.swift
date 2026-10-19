import Foundation

nonisolated struct WatchTimerCommand: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var type: WatchTimerCommandType
    var taskID: UUID?
    var segmentID: UUID?
    var issuedAt: Date
    var deviceID: String
}

nonisolated extension WatchTimerCommand {
    func targetsSameAction(as other: WatchTimerCommand) -> Bool {
        type == other.type && taskID == other.taskID && segmentID == other.segmentID
    }

    var isStructurallyValid: Bool {
        guard SystemSurfaceTextBounds.isFinite(issuedAt),
              deviceID.isEmpty == false,
              SystemSurfaceTextBounds.isBounded(
                  deviceID,
                  maximumUTF8Bytes: WatchTransportLimits.maximumDeviceIDBytes
              )
        else {
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
        guard isStructurallyValid, SystemSurfaceTextBounds.isFinite(now) else { return false }
        let age = now.timeIntervalSince(issuedAt)
        return age.isFinite &&
            age >= -SystemSurfaceLimits.maximumFutureClockSkew &&
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
    case missingTask(UUID)
    case missingSegment(UUID)
    case invalid

    var isProcessed: Bool {
        switch self {
        case .started, .stopped:
            true
        case .missingTask, .missingSegment, .invalid:
            false
        }
    }
}

/// A terminal acknowledgement for one command submitted by Apple Watch.
///
/// Start and stop are idempotent on the iPhone (an already-running task keeps
/// its segment; a stopped segment stays stopped), so a retry is always safe.
nonisolated struct WatchCommandResult: Codable, Equatable, Identifiable, Sendable {
    var commandID: UUID
    var status: WatchCommandResultStatus
    var completedAt: Date
    var relatedID: UUID?
    var failureCode: String?

    var id: UUID {
        commandID
    }

    var completesWithoutUserAction: Bool {
        status == .success
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
        guard SystemSurfaceTextBounds.isFinite(completedAt) else { return false }
        guard let failureCode else { return true }
        return SystemSurfaceTextBounds.isBounded(
            failureCode,
            maximumUTF8Bytes: WatchTransportLimits.maximumFailureCodeBytes
        )
    }

    func isValid(at now: Date) -> Bool {
        guard isStructurallyValid, SystemSurfaceTextBounds.isFinite(now) else { return false }
        return completedAt.timeIntervalSince(now) <= SystemSurfaceLimits.maximumFutureClockSkew
    }
}

nonisolated enum WatchCommandResultStatus: String, Codable, Equatable, Sendable {
    case success
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
        case let .started(segmentID), let .stopped(segmentID):
            WatchCommandResult(
                commandID: commandID,
                status: .success,
                completedAt: completedAt,
                relatedID: segmentID,
                failureCode: nil
            )
        case let .missingTask(taskID):
            WatchCommandResult(
                commandID: commandID,
                status: .missingTask,
                completedAt: completedAt,
                relatedID: taskID,
                failureCode: nil
            )
        case let .missingSegment(segmentID):
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

nonisolated struct WatchFailedCommand: Equatable, Identifiable, Sendable {
    var command: WatchTimerCommand
    var result: WatchCommandResult

    var id: UUID {
        command.id
    }
}

/// In-memory command lifecycle for the watch UI: a command is pending until
/// the iPhone answers or it times out, then retryable from the failed list.
nonisolated struct WatchCommandQueueState: Equatable, Sendable {
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
            pendingCommands.count - WatchTransportLimits.maximumPendingCommands
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

    private mutating func appendFailedCommand(_ failedCommand: WatchFailedCommand) {
        failedCommands.removeAll { $0.id == failedCommand.id }
        failedCommands.append(failedCommand)
        let overflowCount = max(
            0,
            failedCommands.count - WatchTransportLimits.maximumFailedCommands
        )
        if overflowCount > 0 {
            failedCommands.removeFirst(overflowCount)
        }
    }
}
