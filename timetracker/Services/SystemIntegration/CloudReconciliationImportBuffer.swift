import CoreData
import Foundation

/// Temporarily observes CloudKit imports during the gap between creating the
/// model container and installing the scene-owned store observers.
@MainActor
final class CloudRecoveryImportBuffer {
    static let shared = CloudRecoveryImportBuffer()

    private let center: NotificationCenter
    private let recordReceipt: @MainActor (CloudRecoveryContainerEventReceipt) throws -> Void
    private var token: NSObjectProtocol?
    private var reasons: [TimeTrackerStore.SyncRefreshReason] = []

    init(
        center: NotificationCenter = .default,
        recordReceipt: @escaping @MainActor (CloudRecoveryContainerEventReceipt) throws -> Void = {
            try SyncConflictService().recordCloudRecoveryContainerEvent($0)
        }
    ) {
        self.center = center
        self.recordReceipt = recordReceipt
    }

    var isObserving: Bool { token != nil }

    func startIfNeeded() {
        guard token == nil else { return }
        token = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
                event.endDate != nil else {
                return
            }
            MainActor.assumeIsolated { [weak self] in
                guard let self else { return }
                if let receipt = CloudRecoveryContainerEventReceipt(event: event) {
                    do {
                        try recordReceipt(receipt)
                    } catch {
                        if event.type == .import {
                            record(
                                .cloudImportFinished(
                                    succeeded: false,
                                    reportsConflict: false,
                                    failureMessage: error.localizedDescription
                                )
                            )
                        }
                        return
                    }
                }
                guard event.type == .import else { return }
                record(
                    .cloudImportFinished(
                        succeeded: event.succeeded,
                        reportsConflict: SyncConflictService.isConflictLikeCloudError(event.error),
                        failureMessage: event.error?.localizedDescription
                    )
                )
            }
        }
    }

    func stopAndDrain() -> [TimeTrackerStore.SyncRefreshReason] {
        stopObserving()
        defer { reasons.removeAll() }
        return reasons
    }

    func stopAndDiscard() {
        stopObserving()
        reasons.removeAll()
    }

    func record(_ reason: TimeTrackerStore.SyncRefreshReason) {
        reasons.append(reason)
    }

    private func stopObserving() {
        guard let token else { return }
        center.removeObserver(token)
        self.token = nil
    }
}
