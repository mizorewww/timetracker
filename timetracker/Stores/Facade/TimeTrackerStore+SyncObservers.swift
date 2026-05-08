import CoreData
import Foundation

extension TimeTrackerStore {
    func installSyncObservers() {
        guard syncObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSPersistentStoreRemoteChange,
            NSPersistentCloudKitContainer.eventChangedNotification
        ]
        syncObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let store = self else { return }
                Task { @MainActor in
                    store.scheduleQuietRefresh()
                }
            }
        }
    }

    private func scheduleQuietRefresh() {
        scheduledSyncRefreshTask?.cancel()
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try refresh(plan: refreshPlanner.plan(after: [.remoteImportCompleted]))
                lastSyncRefreshAt = Date()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
