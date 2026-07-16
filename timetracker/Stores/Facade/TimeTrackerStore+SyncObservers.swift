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
                MainActor.assumeIsolated { [weak self] in
                    guard let store = self else { return }
                    if let event = notification.userInfo?[
                        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                    ] as? NSPersistentCloudKitContainer.Event,
                        event.endDate != nil {
                        do {
                            try store.syncConflictService.recordCloudRecoveryContainerEvent(event)
                        } catch {
                            store.recordCloudExportStateFailure(error)
                            return
                        }
                    }
                    if let exportID = store.cloudExportStartIdentifier(
                        for: name,
                        notification: notification
                    ) {
                        store.recordCloudExportStart(eventID: exportID)
                        return
                    }
                    guard let reason = store.syncRefreshReason(
                        for: name,
                        notification: notification
                    ) else { return }
                    store.scheduleQuietRefresh(reason: reason)
                }
            }
            return SyncNotificationObserverToken(token)
        }
        let recoveryToken = center.addObserver(
            forName: .appCloudRecoveryStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                self?.refreshCloudRecoveryPresentationState()
            }
        }
        syncObservers.append(SyncNotificationObserverToken(recoveryToken))
        for reason in CloudRecoveryImportBuffer.shared.stopAndDrain() {
            scheduleQuietRefresh(reason: reason)
        }
        do {
            if AppCloudSync.isCloudImportRecoveryActive,
               try syncConflictService.hasCompletedCloudRecoveryImportReceipt() {
                scheduleQuietRefresh(
                    reason: .cloudImportFinished(
                        succeeded: true,
                        reportsConflict: false,
                        failureMessage: nil
                    )
                )
            }
        } catch {
            recordCloudExportStateFailure(error)
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
                succeeded: event.succeeded,
                reportsConflict: SyncConflictService.isConflictLikeCloudError(event.error),
                failureMessage: event.error?.localizedDescription
            )
        case .export:
            return .cloudExportFinished(
                eventID: event.identifier,
                succeeded: event.succeeded,
                reportsConflict: SyncConflictService.isConflictLikeCloudError(event.error),
                failureMessage: event.error?.localizedDescription
            )
        case .setup:
            return .cloudSetupFinished(
                succeeded: event.succeeded,
                failureMessage: event.error?.localizedDescription
            )
        @unknown default:
            return .remoteStoreChanged
        }
    }

}
