#if DEBUG
import CoreData
import Foundation
import SwiftData
#if os(macOS)
import AppKit
#else
import Darwin
#endif

@MainActor
enum CloudSyncSmokeTestRunner {
    private static let argument = "--cloud-smoke-test"
    private static let tokenKey = "TimeTrackerCloudSmokeToken"
    private static let taskIDKey = "TimeTrackerCloudSmokeTaskID"
    private static let deviceID = SyntheticDataOrigin.cloudSmokeTest

    enum Mode: String {
        case seed
        case queueUpload
        case verifyUploadRestart
        case queueDownloadFromDemo
        case verifyDownloadRestart
    }

    static func runIfRequested(context: ModelContext, store: TimeTrackerStore) async -> Bool {
        guard let argumentIndex = CommandLine.arguments.firstIndex(of: argument),
              CommandLine.arguments.indices.contains(argumentIndex + 1),
              let mode = Mode(rawValue: CommandLine.arguments[argumentIndex + 1])
        else {
            return false
        }

        do {
            try await run(mode: mode, context: context, store: store)
            log("PASS \(mode.rawValue)")
        } catch {
            log("FAIL \(mode.rawValue): \(error.localizedDescription)")
        }

        #if os(macOS)
        NSApplication.shared.terminate(nil)
        return true
        #else
        Darwin.exit(0)
        #endif
    }

    private static func run(mode: Mode, context: ModelContext, store: TimeTrackerStore) async throws {
        log("mode=\(mode.rawValue)")
        log("persistenceMode(before)=\(AppCloudSync.persistenceMode)")
        let accountCheck = await AppCloudSync.checkAccountStatus()
        log("accountStatus=\(String(describing: accountCheck.result))")
        let observers = installCloudEventLogging()
        defer { removeCloudEventLogging(observers) }

        switch mode {
        case .seed:
            try seedVisibleTask(context: context)
            try SyncConflictService().recordLocalMutation(context: context)
            try store.refresh()
            logVisibleState(context: context, prefix: "after-seed")

        case .queueUpload:
            logVisibleState(context: context, prefix: "before-queue")
            AppDefaults.shared.set(AppCloudSync.modeLocalFallback, forKey: AppCloudSync.modeKey)
            let result = try SyncConflictService().forceUploadLocalData(context: context)
            try store.refresh()
            log("queueUploadResult=\(String(describing: result))")
            log("pendingUploadReset=\(AppDefaults.shared.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))")
            logVisibleState(context: context, prefix: "after-queue")

        case .verifyUploadRestart:
            try await verifyRecoveredCloudData(
                context: context,
                store: store,
                prefix: "verify",
                requireStoredTask: true
            )

        case .queueDownloadFromDemo:
            try SeedData.clearDemoData(context: context)
            try store.refresh()
            logVisibleState(context: context, prefix: "after-clear-demo")
            let result = try SyncConflictService().acceptCurrentCloudData(context: context)
            try store.refresh()
            log("queueDownloadResult=\(String(describing: result))")
            log("demoMode(afterQueue)=\(AppDemoDataConfiguration.currentMode.rawValue)")
            log("demoOverride(afterQueue)=\(AppDefaults.shared.string(forKey: AppDemoDataConfiguration.overrideKey) ?? "nil")")
            log("pendingDownloadReset=\(AppDefaults.shared.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))")
            logVisibleState(context: context, prefix: "after-download-queue")

        case .verifyDownloadRestart:
            try await verifyRecoveredCloudData(
                context: context,
                store: store,
                prefix: "download-verify",
                requireStoredTask: false
            )
        }
    }

    private static func verifyRecoveredCloudData(
        context: ModelContext,
        store: TimeTrackerStore,
        prefix: String,
        requireStoredTask: Bool
    ) async throws {
        let expectedID = storedTaskID()
        log("pendingUploadReset=\(AppDefaults.shared.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))")
        log("pendingDownloadReset=\(AppDefaults.shared.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))")
        log("persistenceMode(after)=\(AppCloudSync.persistenceMode)")
        log("demoMode(after)=\(AppDemoDataConfiguration.currentMode.rawValue)")

        let deadline = Date().addingTimeInterval(60)
        var attempt = 0
        while true {
            attempt += 1
            try store.refresh()
            let visibleTasks = try visibleTasks(context: context)
            logVisibleState(context: context, prefix: "\(prefix)-attempt-\(attempt)")
            if let expectedID,
               visibleTasks.contains(where: { $0.id == expectedID })
            {
                log("recoveredTaskID=\(expectedID.uuidString)")
                return
            }
            if !requireStoredTask, !visibleTasks.isEmpty {
                return
            }
            guard Date() < deadline else {
                throw SmokeTestError.recoveredTaskMissing
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private static func seedVisibleTask(context: ModelContext) throws {
        let token = AppDefaults.shared.string(forKey: tokenKey) ?? UUID().uuidString
        AppDefaults.shared.set(token, forKey: tokenKey)
        if let existingID = storedTaskID(),
           try visibleTasks(context: context).contains(where: { $0.id == existingID })
        {
            log("seedTaskAlreadyExists=\(existingID.uuidString)")
            return
        }

        let repository = SwiftDataTaskRepository(context: context, deviceID: deviceID)
        let task = try repository.createTask(
            title: "Cloud Smoke \(token.prefix(8))",
            parentID: nil,
            categoryID: nil,
            colorHex: "0EA5E9",
            iconName: "icloud"
        )
        AppDefaults.shared.set(task.id.uuidString, forKey: taskIDKey)
        log("seedTaskID=\(task.id.uuidString)")
    }

    private static func storedTaskID() -> UUID? {
        AppDefaults.shared.string(forKey: taskIDKey).flatMap(UUID.init(uuidString:))
    }

    private static func visibleTasks(context: ModelContext) throws -> [TaskNode] {
        try context.fetch(FetchDescriptor<TaskNode>())
            .visibleDeduplicatedByID()
    }

    private static func logVisibleState(context: ModelContext, prefix: String) {
        do {
            let tasks = try visibleTasks(context: context)
            let taskTitles = tasks.map(\.title).sorted().joined(separator: ", ")
            log("\(prefix).visibleTaskCount=\(tasks.count)")
            log("\(prefix).visibleTasks=\(taskTitles)")
        } catch {
            log("\(prefix).visibleTaskError=\(error.localizedDescription)")
        }
    }

    private nonisolated static func log(_ message: String) {
        let line = "[CloudSmoke] \(message)"
        print(line)
        NSLog("%@", line)
    }

    private static func installCloudEventLogging() -> [NSObjectProtocol] {
        let center = NotificationCenter.default
        return [
            center.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
                log("remoteChange")
            },
            center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
                else {
                    log("cloudEvent=unknown")
                    return
                }
                let error = event.error.map { String(describing: $0) } ?? "none"
                log("cloudEvent type=\(cloudEventTypeName(event.type)) finished=\(event.endDate != nil) error=\(error)")
            },
        ]
    }

    private static func removeCloudEventLogging(_ observers: [NSObjectProtocol]) {
        let center = NotificationCenter.default
        observers.forEach { center.removeObserver($0) }
    }

    private nonisolated static func cloudEventTypeName(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:
            "setup"
        case .import:
            "import"
        case .export:
            "export"
        @unknown default:
            "unknown"
        }
    }

    enum SmokeTestError: LocalizedError {
        case recoveredTaskMissing

        var errorDescription: String? {
            "Cloud smoke recovered data is missing after waiting for CloudKit import."
        }
    }
}
#endif
