import CoreData
import Foundation

extension CloudRecoveryContainerEventReceipt {
    init?(event: NSPersistentCloudKitContainer.Event) {
        guard let completedAt = event.endDate else { return nil }

        let kind: EventKind
        switch event.type {
        case .setup:
            kind = .setup
        case .import:
            kind = .import
        case .export:
            kind = .export
        @unknown default:
            return nil
        }

        self.init(
            storeIdentifier: event.storeIdentifier,
            kind: kind,
            startedAt: event.startDate,
            completedAt: completedAt,
            succeeded: event.succeeded
        )
    }
}

extension SyncConflictService {
    func beginCloudRecoveryImportSession(
        kind: CloudRecoveryImportKind,
        startedAt: Date = Date()
    ) throws {
        try withExclusiveStateAccess {
            var state = try loadState()
            state.cloudRecoveryImportSession = CloudRecoveryImportSession(
                id: UUID(),
                kind: kind,
                startedAt: startedAt
            )
            state.cloudDownloadRecoveryCompleted = nil
            try saveState(state)
        }
    }

    func recordCloudRecoveryContainerEvent(
        _ receipt: CloudRecoveryContainerEventReceipt
    ) throws {
        try withExclusiveStateAccess {
            var state = try loadState()
            guard var session = state.cloudRecoveryImportSession else { return }
            let previousSession = session
            session.record(receipt)
            guard session != previousSession else { return }
            state.cloudRecoveryImportSession = session
            try saveState(state)
        }
    }

    func recordCloudRecoveryContainerEvent(
        _ event: NSPersistentCloudKitContainer.Event
    ) throws {
        guard let receipt = CloudRecoveryContainerEventReceipt(event: event) else { return }
        try recordCloudRecoveryContainerEvent(receipt)
    }

    func hasCompletedCloudRecoveryImportSession(
        kind: CloudRecoveryImportKind
    ) throws -> Bool {
        guard let session = try loadState().cloudRecoveryImportSession else {
            return false
        }
        return session.kind == kind && session.hasCompletedInitialImport
    }

    func hasCompletedCloudRecoveryImportReceipt() throws -> Bool {
        cloudRecoveryImportIsReady(in: try loadState())
    }

    func cloudRecoveryImportIsReady(in state: SyncConflictState) -> Bool {
        guard let session = state.cloudRecoveryImportSession,
              session.hasCompletedInitialImport else {
            return false
        }
        if AppCloudSync.isCloudDownloadRecoveryActive {
            return session.kind == .downloadCloud
        }
        if AppCloudSync.isCloudReconciliationActive {
            return session.kind == .reconcileWithCloud
        }
        return false
    }
}
