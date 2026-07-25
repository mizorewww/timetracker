import Foundation

enum WatchConnectivityPayloadCodec {
    private nonisolated static let kindKey = "kind"
    private nonisolated static let commandKind = "timerCommand"
    private nonisolated static let commandResultKind = "commandResult"
    private nonisolated static let stateKind = "stateSnapshot"

    private nonisolated static let idKey = "id"
    private nonisolated static let typeKey = "type"
    private nonisolated static let taskIDKey = "taskID"
    private nonisolated static let segmentIDKey = "segmentID"
    private nonisolated static let issuedAtKey = "issuedAt"
    private nonisolated static let deviceIDKey = "deviceID"
    private nonisolated static let commandIDKey = "commandID"
    private nonisolated static let statusKey = "status"
    private nonisolated static let completedAtKey = "completedAt"
    private nonisolated static let relatedIDKey = "relatedID"
    private nonisolated static let failureCodeKey = "failureCode"
    private nonisolated static let receivedKey = "received"

    private nonisolated static let generatedAtKey = "generatedAt"
    private nonisolated static let todayGrossSecondsKey = "todayGrossSeconds"
    private nonisolated static let todayWallSecondsKey = "todayWallSeconds"
    private nonisolated static let activeTimersKey = "activeTimers"
    private nonisolated static let recentTasksKey = "recentTasks"
    private nonisolated static let titleKey = "title"
    private nonisolated static let pathKey = "path"
    private nonisolated static let startedAtKey = "startedAt"
    private nonisolated static let colorHexKey = "colorHex"
    private nonisolated static let iconNameKey = "iconName"
    private nonisolated static let quickStartRankKey = "quickStartRank"
    private nonisolated static let allTasksRankKey = "allTasksRank"

    nonisolated static func encode(command: WatchTimerCommand) -> [String: Any] {
        var payload: [String: Any] = [
            kindKey: commandKind,
            idKey: command.id.uuidString,
            typeKey: command.type.rawValue,
            issuedAtKey: command.issuedAt.timeIntervalSinceReferenceDate,
            deviceIDKey: command.deviceID,
        ]
        payload[taskIDKey] = command.taskID?.uuidString
        payload[segmentIDKey] = command.segmentID?.uuidString
        return payload
    }

    nonisolated static func decodeCommand(from payload: [String: Any]) -> WatchTimerCommand? {
        guard payload[kindKey] as? String == commandKind,
              let idString = payload[idKey] as? String,
              let id = UUID(uuidString: idString),
              let typeString = payload[typeKey] as? String,
              let type = WatchTimerCommandType(rawValue: typeString),
              let issuedAtInterval = payload[issuedAtKey] as? TimeInterval,
              let deviceID = payload[deviceIDKey] as? String
        else {
            return nil
        }

        let command = WatchTimerCommand(
            id: id,
            type: type,
            taskID: uuid(from: payload[taskIDKey]),
            segmentID: uuid(from: payload[segmentIDKey]),
            issuedAt: Date(timeIntervalSinceReferenceDate: issuedAtInterval),
            deviceID: deviceID
        )
        return command.isStructurallyValid ? command : nil
    }

    nonisolated static func encode(result: WatchCommandResult) -> [String: Any] {
        var payload: [String: Any] = [
            kindKey: commandResultKind,
            commandIDKey: result.commandID.uuidString,
            statusKey: result.status.rawValue,
            completedAtKey: result.completedAt.timeIntervalSinceReferenceDate,
            // Preserve the legacy receipt bit for older watch builds while newer
            // builds use the typed terminal status above.
            receivedKey: true,
        ]
        payload[relatedIDKey] = result.relatedID?.uuidString
        payload[failureCodeKey] = result.failureCode
        return payload
    }

    nonisolated static func decodeCommandResult(from payload: [String: Any]) -> WatchCommandResult? {
        guard payload[kindKey] as? String == commandResultKind,
              let commandID = uuid(from: payload[commandIDKey]),
              let statusValue = payload[statusKey] as? String,
              let status = WatchCommandResultStatus(rawValue: statusValue),
              let completedAtInterval = payload[completedAtKey] as? TimeInterval
        else {
            return nil
        }

        let result = WatchCommandResult(
            commandID: commandID,
            status: status,
            completedAt: Date(timeIntervalSinceReferenceDate: completedAtInterval),
            relatedID: uuid(from: payload[relatedIDKey]),
            failureCode: payload[failureCodeKey] as? String
        )
        return result.isValid(at: Date()) ? result : nil
    }

    nonisolated static func encode(state: WatchStateSnapshot) -> [String: Any] {
        [
            kindKey: stateKind,
            generatedAtKey: state.generatedAt.timeIntervalSinceReferenceDate,
            todayGrossSecondsKey: state.todayGrossSeconds,
            todayWallSecondsKey: state.todayWallSeconds,
            activeTimersKey: state.activeTimers.map(encode(activeTimer:)),
            recentTasksKey: state.recentTasks.map(encode(recentTask:)),
        ]
    }

    nonisolated static func decodeState(from payload: [String: Any]) -> WatchStateSnapshot? {
        guard payload[kindKey] as? String == stateKind,
              let generatedAtInterval = payload[generatedAtKey] as? TimeInterval,
              let todayGrossSeconds = payload[todayGrossSecondsKey] as? Int,
              let todayWallSeconds = payload[todayWallSecondsKey] as? Int,
              let activePayloads = payload[activeTimersKey] as? [[String: Any]],
              let recentPayloads = payload[recentTasksKey] as? [[String: Any]],
              activePayloads.count <= WatchTransportLimits.maximumActiveTimers,
              recentPayloads.count <= WatchTransportLimits.maximumRecentTasks
        else {
            return nil
        }

        let activeTimers = activePayloads.compactMap(decodeActiveTimer(from:))
        let recentTasks = recentPayloads.compactMap(decodeRecentTask(from:))
        guard activeTimers.count == activePayloads.count, recentTasks.count == recentPayloads.count else {
            return nil
        }

        let snapshot = WatchStateSnapshot(
            generatedAt: Date(timeIntervalSinceReferenceDate: generatedAtInterval),
            todayGrossSeconds: todayGrossSeconds,
            todayWallSeconds: todayWallSeconds,
            activeTimers: activeTimers,
            recentTasks: recentTasks
        )
        return snapshot.isValid(at: Date()) ? snapshot : nil
    }

    private nonisolated static func encode(activeTimer: WatchActiveTimerSnapshot) -> [String: Any] {
        var payload: [String: Any] = [
            idKey: activeTimer.id.uuidString,
            taskIDKey: activeTimer.taskID.uuidString,
            titleKey: activeTimer.title,
            pathKey: activeTimer.path,
            startedAtKey: activeTimer.startedAt.timeIntervalSinceReferenceDate,
        ]
        payload[colorHexKey] = activeTimer.colorHex
        payload[iconNameKey] = activeTimer.iconName
        return payload
    }

    private nonisolated static func encode(recentTask: WatchRecentTaskSnapshot) -> [String: Any] {
        var payload: [String: Any] = [
            taskIDKey: recentTask.taskID.uuidString,
            titleKey: recentTask.title,
            pathKey: recentTask.path,
        ]
        payload[colorHexKey] = recentTask.colorHex
        payload[iconNameKey] = recentTask.iconName
        payload[quickStartRankKey] = recentTask.quickStartRank
        payload[allTasksRankKey] = recentTask.allTasksRank
        return payload
    }

    private nonisolated static func decodeActiveTimer(from payload: [String: Any]) -> WatchActiveTimerSnapshot? {
        guard let id = uuid(from: payload[idKey]),
              let taskID = uuid(from: payload[taskIDKey]),
              let title = payload[titleKey] as? String,
              let path = payload[pathKey] as? String,
              let startedAtInterval = payload[startedAtKey] as? TimeInterval
        else {
            return nil
        }

        return WatchActiveTimerSnapshot(
            id: id,
            taskID: taskID,
            title: title,
            path: path,
            startedAt: Date(timeIntervalSinceReferenceDate: startedAtInterval),
            colorHex: payload[colorHexKey] as? String,
            iconName: payload[iconNameKey] as? String
        )
    }

    private nonisolated static func decodeRecentTask(from payload: [String: Any]) -> WatchRecentTaskSnapshot? {
        guard let taskID = uuid(from: payload[taskIDKey]),
              let title = payload[titleKey] as? String,
              let path = payload[pathKey] as? String
        else {
            return nil
        }

        return WatchRecentTaskSnapshot(
            taskID: taskID,
            title: title,
            path: path,
            colorHex: payload[colorHexKey] as? String,
            iconName: payload[iconNameKey] as? String,
            quickStartRank: payload[quickStartRankKey] as? Int,
            allTasksRank: payload[allTasksRankKey] as? Int
        )
    }

    private nonisolated static func uuid(from value: Any?) -> UUID? {
        guard let string = value as? String else { return nil }
        return UUID(uuidString: string)
    }
}
