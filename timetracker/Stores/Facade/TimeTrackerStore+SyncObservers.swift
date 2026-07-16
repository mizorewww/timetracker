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
        case cloudImportFinished(
            succeeded: Bool,
            reportsConflict: Bool,
            failureMessage: String?
        )
        case cloudExportFinished(
            eventID: UUID,
            succeeded: Bool,
            reportsConflict: Bool,
            failureMessage: String?
        )
        case cloudSetupFinished(succeeded: Bool, failureMessage: String?)

        var priority: Int {
            switch self {
            case .remoteStoreChanged:
                return 0
            case let .cloudExportFinished(_, succeeded, reportsConflict, _):
                return reportsConflict ? 4 : (succeeded ? 1 : 3)
            case let .cloudImportFinished(succeeded, reportsConflict, _):
                return reportsConflict ? 4 : (succeeded ? 2 : 3)
            case let .cloudSetupFinished(succeeded, _):
                return succeeded ? 1 : 3
            }
        }

        var activityKind: SyncActivityKind {
            switch self {
            case .remoteStoreChanged:
                return .remoteRefresh
            case .cloudImportFinished:
                return .importData
            case .cloudExportFinished:
                return .exportData
            case .cloudSetupFinished:
                return .setup
            }
        }

        func activityOutcome(
            completedAt: Date,
            processingFailureMessage: String? = nil
        ) -> SyncActivityOutcome? {
            if let processingFailureMessage {
                return SyncActivityOutcome(
                    kind: activityKind,
                    completedAt: completedAt,
                    result: .failed(message: processingFailureMessage)
                )
            }
            switch self {
            case .remoteStoreChanged:
                return nil
            case let .cloudImportFinished(succeeded, _, failureMessage),
                 let .cloudSetupFinished(succeeded, failureMessage):
                return eventOutcome(
                    succeeded: succeeded,
                    failureMessage: failureMessage,
                    completedAt: completedAt
                )
            case let .cloudExportFinished(_, succeeded, _, failureMessage):
                return eventOutcome(
                    succeeded: succeeded,
                    failureMessage: failureMessage,
                    completedAt: completedAt
                )
            }
        }

        private func eventOutcome(
            succeeded: Bool,
            failureMessage: String?,
            completedAt: Date
        ) -> SyncActivityOutcome {
            let result: SyncActivityResult = succeeded
                ? .succeeded
                : .failed(
                    message: failureMessage
                        ?? AppStrings.localized("sync.activity.unknownFailure")
                )
            return SyncActivityOutcome(
                kind: activityKind,
                completedAt: completedAt,
                result: result
            )
        }
    }

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
                try updateConflictState(after: reason)
                recordSyncActivity(for: reason)
            } catch {
                recordSyncActivity(
                    for: reason,
                    processingFailureMessage: error.localizedDescription
                )
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

    private func updateConflictState(after reason: SyncRefreshReason) throws {
        guard let modelContext else { return }
        let completedExports = completedCloudExportResults
        completedCloudExportResults.removeAll()
        for (eventID, succeeded) in completedExports {
            try syncConflictService.markCloudExportFinished(eventID: eventID, succeeded: succeeded)
        }
        switch reason {
        case let .cloudImportFinished(succeeded, reportsConflict, _):
            if succeeded || reportsConflict {
                if let conflict = try syncConflictService.handleCloudImport(context: modelContext) {
                    pendingSyncConflict = conflict
                }
            } else {
                pendingSyncConflict = try syncConflictService.prompt()
            }
        case let .cloudExportFinished(_, _, reportsConflict, _):
            if reportsConflict,
               let conflict = try syncConflictService.handleCloudImport(context: modelContext) {
                pendingSyncConflict = conflict
            } else {
                pendingSyncConflict = try syncConflictService.prompt()
            }
        case .remoteStoreChanged, .cloudSetupFinished:
            pendingSyncConflict = try syncConflictService.prompt()
        }
    }
}
