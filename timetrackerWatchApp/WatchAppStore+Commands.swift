import Foundation
import OSLog

extension WatchAppStore {
    func startTask(taskID: UUID) {
        submit(
            WatchTimerCommand(
                id: UUID(),
                type: .startTask,
                taskID: taskID,
                segmentID: nil,
                issuedAt: Date(),
                deviceID: deviceID
            )
        )
    }

    func stopTimer(segmentID: UUID) {
        submit(
            WatchTimerCommand(
                id: UUID(),
                type: .stopSegment,
                taskID: nil,
                segmentID: segmentID,
                issuedAt: Date(),
                deviceID: deviceID
            )
        )
    }

    func retryCommand(commandID: UUID) {
        guard let command = commandQueue.retry(commandID: commandID) else { return }
        scheduleConfirmationTimeout(for: command)
        transmit(command)
    }

    func discardCommand(commandID: UUID) {
        confirmationTasks[commandID]?.cancel()
        confirmationTasks[commandID] = nil
        commandQueue.discard(commandID: commandID)
    }

    func submit(_ command: WatchTimerCommand) {
        guard commandQueue.enqueue(command) else { return }
        scheduleConfirmationTimeout(for: command)
        transmit(command)
    }

    func scheduleConfirmationTimeout(for command: WatchTimerCommand) {
        confirmationTasks[command.id]?.cancel()
        let remaining = max(
            0,
            command.issuedAt.addingTimeInterval(confirmationTimeout).timeIntervalSinceNow
        )
        confirmationTasks[command.id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(remaining))
            } catch {
                return
            }
            guard let self,
                  commandQueue.pendingCommands.contains(where: { $0.id == command.id })
            else {
                return
            }
            confirmationTasks[command.id] = nil
            _ = commandQueue.timeOut(commandID: command.id)
        }
    }

    func persistCommandQueue() {
        guard !commandQueue.pendingCommands.isEmpty || !commandQueue.failedCommands.isEmpty else {
            defaults.removeObject(forKey: Self.commandQueueKey)
            return
        }
        guard commandQueue.isSafeForRestoration,
              let data = try? JSONEncoder().encode(commandQueue),
              data.count <= WatchTransportLimits.maximumQueueEncodedBytes
        else {
            defaults.removeObject(forKey: Self.commandQueueKey)
            Self.logger.error("Could not persist an unsafe watch command queue")
            return
        }
        defaults.set(data, forKey: Self.commandQueueKey)
    }
}
