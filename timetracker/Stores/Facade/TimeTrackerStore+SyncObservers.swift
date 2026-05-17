import CoreData
import Foundation

extension TimeTrackerStore {
    enum SyncRefreshReason: Sendable {
        case remoteStoreChanged
        case cloudImportFinished
        case cloudExportFinished
        case cloudConflictReported

        var priority: Int {
            switch self {
            case .remoteStoreChanged:
                return 0
            case .cloudExportFinished:
                return 1
            case .cloudImportFinished:
                return 2
            case .cloudConflictReported:
                return 3
            }
        }
    }

    func installSyncObservers() {
        guard syncObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSPersistentStoreRemoteChange,
            NSPersistentCloudKitContainer.eventChangedNotification
        ]
        syncObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let store = self else { return }
                guard let reason = store.syncRefreshReason(for: name, notification: notification) else { return }
                Task { @MainActor in
                    store.scheduleQuietRefresh(reason: reason)
                }
            }
        }
    }

    nonisolated private func syncRefreshReason(for name: Notification.Name, notification: Notification) -> SyncRefreshReason? {
        guard name == NSPersistentCloudKitContainer.eventChangedNotification else {
            return .remoteStoreChanged
        }
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
              event.endDate != nil else {
            return nil
        }
        if SyncConflictService.isConflictLikeCloudError(event.error) {
            return .cloudConflictReported
        }
        guard event.error == nil else { return .remoteStoreChanged }
        switch event.type {
        case .import:
            return .cloudImportFinished
        case .export:
            return .cloudExportFinished
        case .setup:
            return .remoteStoreChanged
        @unknown default:
            return .remoteStoreChanged
        }
    }

    private func scheduleQuietRefresh(reason: SyncRefreshReason) {
        scheduledSyncRefreshReason = [scheduledSyncRefreshReason, reason]
            .compactMap { $0 }
            .max { lhs, rhs in lhs.priority < rhs.priority }
        scheduledSyncRefreshTask?.cancel()
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let reason = scheduledSyncRefreshReason ?? reason
            scheduledSyncRefreshReason = nil
            do {
                try refresh(plan: refreshPlanner.plan(after: [.remoteImportCompleted]))
                lastSyncRefreshAt = Date()
                try updateConflictState(after: reason)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateConflictState(after reason: SyncRefreshReason) throws {
        guard let modelContext else { return }
        switch reason {
        case .cloudImportFinished, .cloudConflictReported:
            if let conflict = try syncConflictService.handleCloudImport(context: modelContext) {
                pendingSyncConflict = conflict
            }
        case .cloudExportFinished:
            try syncConflictService.markCloudExportAccepted(context: modelContext)
            pendingSyncConflict = nil
        case .remoteStoreChanged:
            pendingSyncConflict = syncConflictService.prompt()
        }
    }
}
