import Foundation

nonisolated enum DeviceIdentityPlatform: String, CaseIterable, Sendable {
    case mac
    case ios
    case watch

    static var current: DeviceIdentityPlatform {
        #if os(macOS)
        .mac
        #elseif os(watchOS)
        .watch
        #else
        .ios
        #endif
    }
}

nonisolated enum DeviceIdentityPolicy {
    static let storageKey = "TimeTrackerDeviceID"
    static let maximumIdentifierByteCount = 42

    static func identifier(platform: DeviceIdentityPlatform, uuid: UUID) -> String {
        "\(platform.rawValue)-\(uuid.uuidString)"
    }

    static func isValid(_ identifier: String, for platform: DeviceIdentityPlatform) -> Bool {
        guard identifier.utf8.count <= maximumIdentifierByteCount,
              !identifier.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return false
        }

        let prefix = "\(platform.rawValue)-"
        guard identifier.hasPrefix(prefix) else { return false }

        let uuidString = String(identifier.dropFirst(prefix.count))
        guard let uuid = UUID(uuidString: uuidString),
              uuid.uuidString == uuidString
        else {
            return false
        }
        return identifier == self.identifier(platform: platform, uuid: uuid)
    }
}

nonisolated enum DeviceIdentityStorage {
    static func loadOrCreate(
        defaults: UserDefaults,
        storageKey: String,
        platform: DeviceIdentityPlatform,
        makeUUID: () -> UUID
    ) -> String {
        if let existing = defaults.string(forKey: storageKey),
           DeviceIdentityPolicy.isValid(existing, for: platform)
        {
            return existing
        }

        let identifier = DeviceIdentityPolicy.identifier(platform: platform, uuid: makeUUID())
        defaults.set(identifier, forKey: storageKey)
        return identifier
    }
}

enum DeviceIdentity {
    nonisolated static let current = DeviceIdentityStorage.loadOrCreate(
        defaults: .standard,
        storageKey: DeviceIdentityPolicy.storageKey,
        platform: .current,
        makeUUID: UUID.init
    )
}
