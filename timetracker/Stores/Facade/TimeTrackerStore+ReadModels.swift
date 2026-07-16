import Foundation

extension TimeTrackerStore {
    var syncStatus: SyncStatus {
        SyncStatus(
            mode: AppCloudSync.persistenceMode,
            containerIdentifier: AppCloudSync.containerIdentifier,
            deviceID: DeviceIdentity.current,
            lastError: AppCloudSync.lastError,
            accountCheck: cloudAccountCheck
        )
    }
}
