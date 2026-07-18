import Foundation

enum WatchConnectivityPayloadCodec {
    nonisolated private static let kindKey = "kind"
    nonisolated private static let commandKind = "timerCommand"
    nonisolated private static let commandResultKind = "commandResult"
    nonisolated private static let stateKind = "stateSnapshot"

    nonisolated private static let idKey = "id"
    nonisolated private static let typeKey = "type"
    nonisolated private static let taskIDKey = "taskID"
    nonisolated private static let segmentIDKey = "segmentID"
    nonisolated private static let issuedAtKey = "issuedAt"
    nonisolated private static let deviceIDKey = "deviceID"
    nonisolated private static let commandIDKey = "commandID"
    nonisolated private static let statusKey = "status"
    nonisolated private static let completedAtKey = "completedAt"
    nonisolated private static let relatedIDKey = "relatedID"
    nonisolated private static let failureCodeKey = "failureCode"
    nonisolated private static let receivedKey = "received"

    nonisolated private static let generatedAtKey = "generatedAt"
    nonisolated private static let todayGrossSecondsKey = "todayGrossSeconds"
    nonisolated private static let todayWallSecondsKey = "todayWallSeconds"
    nonisolated private static let activeTimersKey = "activeTimers"
    nonisolated private static let recentTasksKey = "recentTasks"
    nonisolated private static let titleKey = "title"
    nonisolated private static let pathKey = "path"
    nonisolated private static let startedAtKey = "startedAt"
    nonisolated private static let colorHexKey = "colorHex"
    nonisolated private static let iconNameKey = "iconName"
    nonisolated private static let quickStartRankKey = "quickStartRank"
    nonisolated private static let allTasksRankKey = "allTasksRank"

    nonisolated static func encode(command: WatchTimerCommand) -> [String: Any] {
        var payload: [String: Any] = [
            kindKey: commandKind,
            idKey: command.id.uuidString,
            typeKey: command.type.rawValue,
            issuedAtKey: command.issuedAt.timeIntervalSinceReferenceDate,
            deviceIDKey: command.deviceID
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
              let deviceID = payload[deviceIDKey] as? String else {
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
            receivedKey: true
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
              let completedAtInterval = payload[completedAtKey] as? TimeInterval else {
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
            recentTasksKey: state.recentTasks.map(encode(recentTask:))
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
              recentPayloads.count <= WatchTransportLimits.maximumRecentTasks else {
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

    nonisolated private static func encode(activeTimer: WatchActiveTimerSnapshot) -> [String: Any] {
        var payload: [String: Any] = [
            idKey: activeTimer.id.uuidString,
            taskIDKey: activeTimer.taskID.uuidString,
            titleKey: activeTimer.title,
            pathKey: activeTimer.path,
            startedAtKey: activeTimer.startedAt.timeIntervalSinceReferenceDate
        ]
        payload[colorHexKey] = activeTimer.colorHex
        payload[iconNameKey] = activeTimer.iconName
        return payload
    }

    nonisolated private static func encode(recentTask: WatchRecentTaskSnapshot) -> [String: Any] {
        var payload: [String: Any] = [
            taskIDKey: recentTask.taskID.uuidString,
            titleKey: recentTask.title,
            pathKey: recentTask.path
        ]
        payload[colorHexKey] = recentTask.colorHex
        payload[iconNameKey] = recentTask.iconName
        payload[quickStartRankKey] = recentTask.quickStartRank
        payload[allTasksRankKey] = recentTask.allTasksRank
        return payload
    }

    nonisolated private static func decodeActiveTimer(from payload: [String: Any]) -> WatchActiveTimerSnapshot? {
        guard let id = uuid(from: payload[idKey]),
              let taskID = uuid(from: payload[taskIDKey]),
              let title = payload[titleKey] as? String,
              let path = payload[pathKey] as? String,
              let startedAtInterval = payload[startedAtKey] as? TimeInterval else {
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

    nonisolated private static func decodeRecentTask(from payload: [String: Any]) -> WatchRecentTaskSnapshot? {
        guard let taskID = uuid(from: payload[taskIDKey]),
              let title = payload[titleKey] as? String,
              let path = payload[pathKey] as? String else {
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

    nonisolated private static func uuid(from value: Any?) -> UUID? {
        guard let string = value as? String else { return nil }
        return UUID(uuidString: string)
    }
}
