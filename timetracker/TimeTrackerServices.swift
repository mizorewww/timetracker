import Foundation
import CloudKit
import SwiftData

enum AppCloudSync {
    static let containerIdentifier = "iCloud.me.mezorewww.timetracker"
    static let enabledKey = "TimeTrackerCloudSyncEnabled"
    static let modeKey = "TimeTrackerPersistenceMode"
    static let errorKey = "TimeTrackerPersistenceError"
    static let accountStatusKey = "TimeTrackerCloudAccountStatus"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var persistenceMode: String {
        UserDefaults.standard.string(forKey: modeKey) ?? "Local"
    }

    static var lastError: String? {
        UserDefaults.standard.string(forKey: errorKey)
    }

    static var accountStatus: String {
        UserDefaults.standard.string(forKey: accountStatusKey) ?? "未检查"
    }

    static func recordCloudKitEnabled() {
        UserDefaults.standard.set("iCloud", forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
    }

    static func recordCloudKitDisabledByUser() {
        UserDefaults.standard.set("Local", forKey: modeKey)
        UserDefaults.standard.set("用户已关闭 iCloud 同步，下次启动继续使用本地存储。", forKey: accountStatusKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
    }

    static func recordLocalFallback(error: Error) {
        UserDefaults.standard.set("Local fallback", forKey: modeKey)
        UserDefaults.standard.set(error.localizedDescription, forKey: errorKey)
    }

    static func recordEmergencyInMemoryFallback(error: Error) {
        UserDefaults.standard.set("In-memory fallback", forKey: modeKey)
        UserDefaults.standard.set(
            "持久化存储启动失败，已临时使用内存存储：\(error.localizedDescription)",
            forKey: errorKey
        )
        UserDefaults.standard.set("本次启动使用临时存储", forKey: accountStatusKey)
    }

    static func recordUITesting() {
        UserDefaults.standard.set("UI Test", forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        UserDefaults.standard.set("UI 测试内存存储", forKey: accountStatusKey)
    }

    static func refreshAccountStatus() async {
        let container = CKContainer(identifier: containerIdentifier)
        let statusText: String
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                statusText = "Apple ID 可用"
            case .noAccount:
                statusText = "未登录 iCloud"
            case .restricted:
                statusText = "iCloud 受限制"
            case .couldNotDetermine:
                statusText = "无法确定"
            case .temporarilyUnavailable:
                statusText = "暂时不可用"
            @unknown default:
                statusText = "未知状态"
            }
        } catch {
            statusText = error.localizedDescription
        }
        UserDefaults.standard.set(statusText, forKey: accountStatusKey)
    }
}

struct TimerCommand: Codable, Hashable, Identifiable {
    enum CommandType: String, Codable {
        case startTask
        case stopSegment
        case startPomodoro
    }

    let id: UUID
    let type: CommandType
    let taskID: UUID?
    let segmentID: UUID?
    let issuedAt: Date
    let deviceID: String
}

struct TimeAggregationService {
    func totalSeconds(segments: [TimeSegment], mode: AggregationMode, now: Date = Date()) -> Int {
        switch mode {
        case .gross:
            return grossSeconds(segments, now: now)
        case .wallClock:
            return wallClockSeconds(segments, now: now)
        }
    }

    func grossSeconds(_ segments: [TimeSegment], now: Date = Date()) -> Int {
        segments.reduce(0) { result, segment in
            guard segment.deletedAt == nil else { return result }
            let end = segment.endedAt ?? now
            return result + max(0, Int(end.timeIntervalSince(segment.startedAt)))
        }
    }

    func wallClockSeconds(_ segments: [TimeSegment], now: Date = Date()) -> Int {
        let intervals = segments.compactMap { segment -> DateInterval? in
            guard segment.deletedAt == nil else { return nil }
            let end = segment.endedAt ?? now
            guard end > segment.startedAt else { return nil }
            return DateInterval(start: segment.startedAt, end: end)
        }

        return mergeOverlappingIntervals(intervals).reduce(0) { result, interval in
            result + Int(interval.end.timeIntervalSince(interval.start))
        }
    }

    func mergeOverlappingIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                let end = max(last.end, interval.end)
                merged[merged.count - 1] = DateInterval(start: last.start, end: end)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }
}

enum DurationFormatter {
    static func compact(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func clock(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let second = safeSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, second)
        }
        return String(format: "%02d:%02d", minutes, second)
    }
}

enum DeviceIdentity {
    static let current: String = {
        let storageKey = "TimeTrackerDeviceID"
        if let existing = UserDefaults.standard.string(forKey: storageKey) {
            return existing
        }

        #if os(macOS)
        let prefix = "mac-\(Host.current().localizedName ?? "local")"
        #elseif os(watchOS)
        let prefix = "watch"
        #else
        let prefix = "ios"
        #endif

        let identifier = "\(prefix)-\(UUID().uuidString)"
        UserDefaults.standard.set(identifier, forKey: storageKey)
        return identifier
    }()
}
