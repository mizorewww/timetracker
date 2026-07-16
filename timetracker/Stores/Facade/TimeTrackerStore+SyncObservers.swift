import CoreData
import Foundation

final class SyncNotificationObserverToken {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

extension TimeTrackerStore {
    func recordSyncActivity(
        for reason: SyncRefreshReason,
        completedAt: Date = Date(),
        processingFailureMessage: String? = nil
    ) {
        guard let outcome = reason.activityOutcome(
            completedAt: completedAt,
            processingFailureMessage: processingFailureMessage
        ) else {
            return
        }
        lastSyncActivity = outcome
    }

    func recordCloudExportStateFailure(_ error: Error, at date: Date = Date()) {
        lastSyncActivity = SyncActivityOutcome(
            kind: .exportData,
            completedAt: date,
            result: .failed(message: error.localizedDescription)
        )
    }

    func installSyncObservers() {
        guard syncObservers.isEmpty else { return }
        // UI tests use an isolated in-memory container and inject deterministic
        // sync states explicitly. Remote-store callbacks from that container
        // can otherwise race the injected route and erase it after launch.
        guard AppCloudSync.persistenceMode != AppCloudSync.modeUITest else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSPersistentStoreRemoteChange,
            NSPersistentCloudKitContainer.eventChangedNotification
        ]
        syncObservers = names.map { name in
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let store = self else { return }
                if let exportID = store.cloudExportStartIdentifier(for: name, notification: notification) {
                    Task { @MainActor in
                        store.recordCloudExportStart(eventID: exportID)
                    }
                    return
                }
                guard let reason = store.syncRefreshReason(for: name, notification: notification) else { return }
                Task { @MainActor in
                    store.scheduleQuietRefresh(reason: reason)
                }
            }
            return SyncNotificationObserverToken(token)
        }
    }

    nonisolated private func cloudExportStartIdentifier(
        for name: Notification.Name,
        notification: Notification
    ) -> UUID? {
        guard name == NSPersistentCloudKitContainer.eventChangedNotification,
              let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
              event.type == .export,
              event.endDate == nil else {
            return nil
        }
        return event.identifier
    }

    nonisolated private func syncRefreshReason(for name: Notification.Name, notification: Notification) -> SyncRefreshReason? {
        guard name == NSPersistentCloudKitContainer.eventChangedNotification else {
            return .remoteStoreChanged
        }
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
              event.endDate != nil else {
            return nil
        }
        switch event.type {
        case .import:
            return .cloudImportFinished(
                succeeded: event.error == nil,
                reportsConflict: SyncConflictService.isConflictLikeCloudError(event.error),
                failureMessage: event.error?.localizedDescription
            )
        case .export:
            return .cloudExportFinished(
                eventID: event.identifier,
                succeeded: event.error == nil,
                reportsConflict: SyncConflictService.isConflictLikeCloudError(event.error),
                failureMessage: event.error?.localizedDescription
            )
        case .setup:
            return .cloudSetupFinished(
                succeeded: event.error == nil,
                failureMessage: event.error?.localizedDescription
            )
        @unknown default:
            return .remoteStoreChanged
        }
    }

    private func scheduleQuietRefresh(reason: SyncRefreshReason) {
        if case let .cloudExportFinished(eventID, succeeded, _, _) = reason {
            completedCloudExportResults[eventID] = succeeded
        }
        var batch = scheduledSyncRefreshBatch ?? SyncRefreshBatch()
        batch.insert(reason)
        scheduledSyncRefreshBatch = batch
        scheduledSyncRefreshTask?.cancel()
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let batch = scheduledSyncRefreshBatch ?? {
                var fallback = SyncRefreshBatch()
                fallback.insert(reason)
                return fallback
            }()
            scheduledSyncRefreshBatch = nil
            var processingFailure: Error?
            do {
                try updateConflictState(after: batch)
            } catch {
                processingFailure = error
            }
            do {
                try refresh(plan: refreshPlanner.plan(after: [.remoteImportCompleted]))
            } catch {
                processingFailure = processingFailure ?? error
            }
            guard let activityReason = batch.activityReason else { return }
            if let processingFailure {
                recordSyncActivity(
                    for: activityReason,
                    processingFailureMessage: processingFailure.localizedDescription
                )
            } else {
                recordSyncActivity(for: activityReason)
            }
        }
    }

    private func recordCloudExportStart(eventID: UUID) {
        do {
            try syncConflictService.markCloudExportStarted(eventID: eventID)
        } catch {
            recordCloudExportStateFailure(error)
        }
    }

    private func updateConflictState(after batch: SyncRefreshBatch) throws {
        guard let modelContext else { return }
        let completedExports = completedCloudExportResults
        completedCloudExportResults.removeAll()
        for (eventID, succeeded) in completedExports {
            try syncConflictService.markCloudExportFinished(eventID: eventID, succeeded: succeeded)
        }
        if batch.requiresCloudImportHandling {
            pendingSyncConflict = try syncConflictService.handleCloudImport(
                context: modelContext
            )
        } else {
            pendingSyncConflict = try syncConflictService.prompt()
        }
    }
}
