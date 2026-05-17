import Foundation
import CloudKit
import OSLog
import SwiftData

enum AppCloudSync {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "CloudSync"
    )

    nonisolated static let containerIdentifier = "iCloud.me.mezorewww.timetracker"
    nonisolated static let enabledKey = "TimeTrackerCloudSyncEnabled"
    nonisolated static let modeKey = "TimeTrackerPersistenceMode"
    nonisolated static let errorKey = "TimeTrackerPersistenceError"
    nonisolated static let accountStatusKey = "TimeTrackerCloudAccountStatus"
    nonisolated static let pendingCloudUploadResetKey = "TimeTrackerPendingCloudUploadReset"
    nonisolated static let pendingCloudDownloadResetKey = "TimeTrackerPendingCloudDownloadReset"
    nonisolated static let modeICloud = "iCloud"
    nonisolated static let modeLocal = "Local"
    nonisolated static let modeLocalFallback = "Local fallback"
    nonisolated static let modeInMemoryFallback = "In-memory fallback"
    nonisolated static let modeUITest = "UI Test"
    nonisolated static let modeDemoData = "Demo data"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var persistenceMode: String {
        UserDefaults.standard.string(forKey: modeKey) ?? modeLocal
    }

    static var lastError: String? {
        UserDefaults.standard.string(forKey: errorKey)
    }

    static var allowsAutomaticDemoSeeding: Bool {
        guard lastError?.isEmpty ?? true else { return false }
        switch persistenceMode {
        case modeLocal, modeUITest, modeDemoData:
            return true
        default:
            return false
        }
    }

    static var accountStatus: String {
        UserDefaults.standard.string(forKey: accountStatusKey) ?? AppStrings.localized("sync.unchecked")
    }

    static var persistentStoreURL: URL {
        ModelConfiguration(
            "TimeTracker",
            schema: nil,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        ).url
    }

    static func recordCloudKitEnabled() {
        AppDemoDataConfiguration.disableLocalDemoStoreForCloudSync()
        UserDefaults.standard.set(modeICloud, forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        UserDefaults.standard.removeObject(forKey: pendingCloudUploadResetKey)
        UserDefaults.standard.removeObject(forKey: pendingCloudDownloadResetKey)
        logger.info("CloudKit storage is active")
    }

    static func requestCloudRetryAfterRecovery() {
        AppDemoDataConfiguration.disableLocalDemoStoreForCloudSync()
        UserDefaults.standard.set(true, forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
    }

    static func requestCloudUploadReset() {
        UserDefaults.standard.set(true, forKey: pendingCloudUploadResetKey)
        requestCloudRetryAfterRecovery()
        logger.warning("Queued CloudKit upload recovery reset")
    }

    static func requestCloudDownloadReset() {
        UserDefaults.standard.set(true, forKey: pendingCloudDownloadResetKey)
        requestCloudRetryAfterRecovery()
        logger.warning("Queued CloudKit download recovery reset")
    }

    @discardableResult
    static func performPendingCloudRecoveryResetIfNeeded(canResetUpload: Bool = true) throws -> CloudRecoveryReset {
        let defaults = UserDefaults.standard
        let shouldResetForDownload = defaults.bool(forKey: pendingCloudDownloadResetKey)
        let shouldResetForUpload = defaults.bool(forKey: pendingCloudUploadResetKey)
        guard shouldResetForDownload || shouldResetForUpload else {
            return .none
        }
        guard shouldResetForDownload || canResetUpload else {
            logger.error("Skipped CloudKit upload recovery reset because no protected upload snapshot was found")
            return .none
        }
        try removePersistentStoreFiles(at: persistentStoreURL)
        logger.warning(
            "Removed persistent store files for CloudKit recovery reset: \(shouldResetForDownload ? "download" : "upload", privacy: .public)"
        )
        return shouldResetForDownload ? .download : .upload
    }

    static func recordCloudKitDisabledByUser() {
        UserDefaults.standard.set(modeLocal, forKey: modeKey)
        UserDefaults.standard.set(AppStrings.localized("sync.disabledMessage"), forKey: accountStatusKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        logger.info("CloudKit storage is disabled by user preference")
    }

    static func recordLocalFallback(error: Error) {
        UserDefaults.standard.set(modeLocalFallback, forKey: modeKey)
        UserDefaults.standard.set(error.localizedDescription, forKey: errorKey)
        logger.error("CloudKit storage fell back to local store: \(error.localizedDescription, privacy: .public)")
    }

    static func recordEmergencyInMemoryFallback(error: Error) {
        UserDefaults.standard.set(modeInMemoryFallback, forKey: modeKey)
        UserDefaults.standard.set(
            String(format: AppStrings.localized("sync.temporaryStoreError"), error.localizedDescription),
            forKey: errorKey
        )
        UserDefaults.standard.set(AppStrings.localized("sync.temporaryStore"), forKey: accountStatusKey)
        logger.fault("Persistent storage fell back to in-memory store: \(error.localizedDescription, privacy: .public)")
    }

    static func recordUITesting() {
        UserDefaults.standard.set(modeUITest, forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        UserDefaults.standard.set(AppStrings.localized("sync.uiTestStore"), forKey: accountStatusKey)
    }

    static func recordDemoDataMode() {
        UserDefaults.standard.set(modeDemoData, forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        UserDefaults.standard.set(modeDemoData, forKey: accountStatusKey)
    }

    static func refreshAccountStatus() async {
        let container = CKContainer(identifier: containerIdentifier)
        let statusText: String
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                statusText = AppStrings.localized("sync.account.available")
            case .noAccount:
                statusText = AppStrings.localized("sync.account.noAccount")
            case .restricted:
                statusText = AppStrings.localized("sync.account.restricted")
            case .couldNotDetermine:
                statusText = AppStrings.localized("sync.account.couldNotDetermine")
            case .temporarilyUnavailable:
                statusText = AppStrings.localized("sync.account.temporarilyUnavailable")
            @unknown default:
                statusText = AppStrings.localized("sync.account.unknown")
            }
        } catch {
            statusText = error.localizedDescription
        }
        UserDefaults.standard.set(statusText, forKey: accountStatusKey)
        logger.info("CloudKit account status: \(statusText, privacy: .public)")
    }

    private static func removePersistentStoreFiles(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let storePrefix = storeURL.lastPathComponent
        let storeFiles = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix(storePrefix) }

        for file in storeFiles {
            try fileManager.removeItem(at: file)
        }
    }

    enum CloudRecoveryReset {
        case none
        case upload
        case download
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
    nonisolated static func compact(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    nonisolated static func clock(_ seconds: Int) -> String {
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

enum TimeDisplayFormatter {
    nonisolated static func hourMinute(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    nonisolated static func monthDayHourMinute(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(
            format: "%02d/%02d %02d:%02d",
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}

enum DeviceIdentity {
    nonisolated static let current: String = {
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
