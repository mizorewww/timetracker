import Foundation
import SwiftData

extension TimeTrackerStore {
    func materializeAppleHealthTaskCatalog(
        clearRecoveryTaskIDs: Set<UUID>
    ) {
        guard hasCompletedStartupConfiguration,
              effectivePersistenceWriteSafety == .ready,
              let modelContext
        else {
            return
        }

        do {
            let outcome =
                try StoreScopedAppleHealthTaskCatalogCommandCoordinator(
                    container: modelContext.container,
                    writeAuthorization: writeAuthorization
                ).apply(
                    roles: AppleHealthTaskCatalog.allRoles,
                    clearRecoveryTaskIDs: clearRecoveryTaskIDs
                )
            appleHealthTaskCatalogErrorMessage = nil
            if outcome.consumedClearRecoveryTaskIDs.isEmpty == false {
                var pendingRecoveryTaskIDs =
                    appleHealthTimelinePreferenceStore
                        .taskCatalogClearRecoveryTaskIDs
                pendingRecoveryTaskIDs.subtract(
                    outcome.consumedClearRecoveryTaskIDs
                )
                appleHealthTimelinePreferenceStore
                    .taskCatalogClearRecoveryTaskIDs =
                    pendingRecoveryTaskIDs
            }
            finishStoreScopedMutation(events: outcome.events)
        } catch {
            appleHealthTaskCatalogErrorMessage = error.localizedDescription
        }
    }

    func appleHealthGeneratedTaskID(
        for subject: TimelineEntrySubject
    ) -> UUID? {
        guard let role = subject.appleHealthTaskRole else { return nil }
        let id = AppleHealthTaskCatalog.taskDefinition(for: role).id
        return task(for: id) == nil ? nil : id
    }

    /// A visible generated task is enough to authorize one fresh-template
    /// rebuild after Clear All. The receipt intentionally stores task roles,
    /// not physical rows or relationship payloads: Clear All discards those
    /// user edits, and the rebuild reconstitutes one complete default graph.
    func visibleAppleHealthTaskCatalogTaskIDsForClear() throws -> Set<UUID> {
        guard let modelContext else { return [] }
        let catalogTaskIDs = Set(AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        ).tasks.map(\.id))
        return try Set(modelContext.fetch(
            FetchDescriptor<TaskNode>()
        ).visibleDeduplicatedByID().compactMap {
            catalogTaskIDs.contains($0.id) ? $0.id : nil
        })
    }
}
