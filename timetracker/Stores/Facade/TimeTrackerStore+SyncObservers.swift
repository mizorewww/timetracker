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
    func installStoreMutationObserverIfNeeded() {
        guard storeMutationObserver == nil else { return }

        let token = NotificationCenter.default.addObserver(
            forName: StoreMutationBroadcaster.notification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                if let source = notification.object as? TimeTrackerStore, source === self {
                    return
                }
                guard let events = StoreMutationBroadcaster.events(from: notification) else {
                    return
                }
                refreshExternalStoreMutationReadModels(events: events)
            }
        }
        storeMutationObserver = SyncNotificationObserverToken(token)
    }

    /// Another scene or system action has already committed. Refresh only this
    /// scene's read models: catching up must not record the mutation again or
    /// start automatic suggestion requests as a side effect.
    func refreshExternalStoreMutationReadModels(events: Set<StoreDomainEvent>) {
        guard events.isEmpty == false else { return }

        do {
            let plan = StoreRefreshPlanner.plan(after: events)
            try StoreRefreshCoordinator.refreshReadModels(self, plan: plan)
            if plan.validateSelection {
                validateSelectedTask()
            }
        } catch {
            errorMessage = savedRefreshFailedMessage(error)
        }
    }

    func installSyncObservers() {
        installStoreMutationObserverIfNeeded()
        guard syncObservers.isEmpty else { return }
        // UI tests use an isolated in-memory container and inject deterministic
        // sync states explicitly. Remote-store callbacks from that container
        // can otherwise race the injected route and erase it after launch.
        guard AppCloudSync.persistenceMode != AppCloudSync.modeUITest else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSPersistentStoreRemoteChange,
            NSPersistentCloudKitContainer.eventChangedNotification,
        ]
        syncObservers = names.map { name in
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated { [weak self] in
                    guard let store = self,
                          let reason = store.syncRefreshReason(for: name, notification: notification)
                    else { return }
                    store.scheduleQuietRefresh(reason: reason)
                }
            }
            return SyncNotificationObserverToken(token)
        }
    }

    private nonisolated func syncRefreshReason(for name: Notification.Name, notification: Notification) -> SyncRefreshReason? {
        guard name == NSPersistentCloudKitContainer.eventChangedNotification else {
            return .remoteStoreChanged
        }
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
              event.endDate != nil
        else {
            return nil
        }
        switch event.type {
        case .import:
            return .cloudImportFinished(
                succeeded: event.succeeded,
                failureMessage: event.error?.localizedDescription
            )
        case .export:
            return .cloudExportFinished(
                succeeded: event.succeeded,
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
