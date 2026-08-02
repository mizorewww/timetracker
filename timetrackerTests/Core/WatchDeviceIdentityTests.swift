import Foundation
import Testing
@testable import timetracker

struct WatchDeviceIdentityTests {
    @Test
    func canonicalWatchIdentityIsPersistedAndReused() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let uuid = UUID(uuidString: "12345678-1234-5678-9ABC-DEF012345678")!
        var generationCount = 0

        let first = WatchDeviceIdentity.loadOrCreate(defaults: defaults) {
            generationCount += 1
            return uuid
        }
        let second = WatchDeviceIdentity.loadOrCreate(defaults: defaults) {
            generationCount += 1
            return UUID()
        }

        #expect(first == "watch-12345678-1234-5678-9ABC-DEF012345678")
        #expect(second == first)
        #expect(generationCount == 1)
        #expect(defaults.string(forKey: DeviceIdentityPolicy.storageKey) == first)
    }

    @Test(arguments: [
        "watch",
        "ios-12345678-1234-5678-9ABC-DEF012345678",
        "watch-not-a-uuid",
        "watch-12345678-1234-5678-9abc-def012345678",
        "watch-12345678-1234-5678-9ABC-DEF012345678\n",
        "watch-12345678-1234-5678-9ABC-DEF012345678-extra",
    ])
    func invalidPersistedIdentityIsReplaced(_ invalid: String) throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(invalid, forKey: DeviceIdentityPolicy.storageKey)
        let replacementUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let identity = WatchDeviceIdentity.loadOrCreate(defaults: defaults) {
            replacementUUID
        }

        #expect(identity == "watch-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(defaults.string(forKey: DeviceIdentityPolicy.storageKey) == identity)
    }

    @Test
    func independentWatchStoresReceiveDifferentOpaqueIdentities() throws {
        let (firstDefaults, firstSuiteName) = try makeDefaults()
        let (secondDefaults, secondSuiteName) = try makeDefaults()
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuiteName)
            secondDefaults.removePersistentDomain(forName: secondSuiteName)
        }

        let first = WatchDeviceIdentity.loadOrCreate(defaults: firstDefaults) {
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        }
        let second = WatchDeviceIdentity.loadOrCreate(defaults: secondDefaults) {
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        }

        #expect(first != second)
        #expect(DeviceIdentityPolicy.isValid(first, for: .watch))
        #expect(DeviceIdentityPolicy.isValid(second, for: .watch))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "WatchDeviceIdentityTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
