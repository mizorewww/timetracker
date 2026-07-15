import Foundation

enum DeviceIdentity {
    nonisolated static let current: String = {
        let storageKey = "TimeTrackerDeviceID"
        if let existing = UserDefaults.standard.string(forKey: storageKey) {
            return existing
        }

        #if os(macOS)
        let prefix = "mac"
        #elseif os(watchOS)
        let prefix = "watch"
        #else
        let prefix = "ios"
        #endif

        let identifier = "\(prefix)-\(UUID().uuidString)"
        UserDefaults.standard.set(identifier, forKey: storageKey)
        return identifier
    }()
}
