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
    enum SyncRefreshReason: Sendable {
        case remoteStoreChanged
        case cloudImportFinished
        case cloudExportFinished(eventID: UUID, succeeded: Bool, reportsConflict: Bool)
        case cloudConflictReported

        var priority: Int {
            switch self {
            case .remoteStoreChanged:
                return 0
            case let .cloudExportFinished(_, _, reportsConflict):
                return reportsConflict ? 3 : 1
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
            if SyncConflictService.isConflictLikeCloudError(event.error) {
                return .cloudConflictReported
            }
            guard event.error == nil else { return .remoteStoreChanged }
            return .cloudImportFinished
        case .export:
            return .cloudExportFinished(
                eventID: event.identifier,
                succeeded: event.error == nil,
                reportsConflict: SyncConflictService.isConflictLikeCloudError(event.error)
            )
        case .setup:
            return .remoteStoreChanged
        @unknown default:
            return .remoteStoreChanged
        }
    }

    private func scheduleQuietRefresh(reason: SyncRefreshReason) {
        if case let .cloudExportFinished(eventID, succeeded, _) = reason {
            completedCloudExportResults[eventID] = succeeded
        }
        scheduledSyncRefreshReason = [scheduledSyncRefreshReason, reason]
            .compactMap { $0 }
            .max { lhs, rhs in lhs.priority < rhs.priority }
        scheduledSyncRefreshTask?.cancel()
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
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

    private func recordCloudExportStart(eventID: UUID) {
        do {
            try syncConflictService.markCloudExportStarted(eventID: eventID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateConflictState(after reason: SyncRefreshReason) throws {
        guard let modelContext else { return }
        let completedExports = completedCloudExportResults
        completedCloudExportResults.removeAll()
        for (eventID, succeeded) in completedExports {
            try syncConflictService.markCloudExportFinished(eventID: eventID, succeeded: succeeded)
        }
        switch reason {
        case .cloudImportFinished, .cloudConflictReported:
            if let conflict = try syncConflictService.handleCloudImport(context: modelContext) {
                pendingSyncConflict = conflict
            }
        case let .cloudExportFinished(_, _, reportsConflict):
            if reportsConflict,
               let conflict = try syncConflictService.handleCloudImport(context: modelContext) {
                pendingSyncConflict = conflict
            } else {
                pendingSyncConflict = syncConflictService.prompt()
            }
        case .remoteStoreChanged:
            pendingSyncConflict = syncConflictService.prompt()
        }
    }
}
