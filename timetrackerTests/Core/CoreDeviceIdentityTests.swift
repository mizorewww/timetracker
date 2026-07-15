import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreDeviceIdentityTests {
    private let canonicalUUID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let replacementUUID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test
    func policyAcceptsOnlyCanonicalIdentifiersForTheRequestedPlatform() {
        for platform in DeviceIdentityPlatform.allCases {
            let identifier = DeviceIdentityPolicy.identifier(platform: platform, uuid: canonicalUUID)
            #expect(DeviceIdentityPolicy.isValid(identifier, for: platform))

            for otherPlatform in DeviceIdentityPlatform.allCases where otherPlatform != platform {
                #expect(!DeviceIdentityPolicy.isValid(identifier, for: otherPlatform))
            }
        }

        let lowercaseUUID = canonicalUUID.uuidString.lowercased()
        #expect(!DeviceIdentityPolicy.isValid("mac-\(lowercaseUUID)", for: .mac))
        #expect(!DeviceIdentityPolicy.isValid("mac-\(canonicalUUID.uuidString)-suffix", for: .mac))
    }

    @Test
    func storageReusesAValidPersistedIdentifierWithoutGeneratingAnotherUUID() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = DeviceIdentityPolicy.identifier(platform: .mac, uuid: canonicalUUID)
        defaults.set(expected, forKey: DeviceIdentityPolicy.storageKey)
        var generatedUUIDCount = 0

        let loaded = DeviceIdentityStorage.loadOrCreate(
            defaults: defaults,
            storageKey: DeviceIdentityPolicy.storageKey,
            platform: .mac
        ) {
            generatedUUIDCount += 1
            return replacementUUID
        }

        #expect(loaded == expected)
        #expect(defaults.string(forKey: DeviceIdentityPolicy.storageKey) == expected)
        #expect(generatedUUIDCount == 0)
    }

    @Test
    func storageReplacesWrongPlatformOversizedControlAndMalformedValues() throws {
        let invalidValues = [
            "ios-\(canonicalUUID.uuidString)",
            String(repeating: "x", count: DeviceIdentityPolicy.maximumIdentifierByteCount + 1),
            "mac-\u{0000}\(canonicalUUID.uuidString.dropFirst())",
            "mac-01234567-89AB-CDEF-0123-456789ABCDEG"
        ]
        let expected = DeviceIdentityPolicy.identifier(platform: .mac, uuid: replacementUUID)

        for invalidValue in invalidValues {
            let (defaults, suiteName) = try makeIsolatedDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set(invalidValue, forKey: DeviceIdentityPolicy.storageKey)

            let loaded = DeviceIdentityStorage.loadOrCreate(
                defaults: defaults,
                storageKey: DeviceIdentityPolicy.storageKey,
                platform: .mac,
                makeUUID: { replacementUUID }
            )

            #expect(loaded == expected)
            #expect(defaults.string(forKey: DeviceIdentityPolicy.storageKey) == expected)
        }
    }

    @Test
    func generatedIdentifierIsStableAndContainsOnlyPlatformAndUUID() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = DeviceIdentityPolicy.identifier(platform: .mac, uuid: canonicalUUID)

        let generated = DeviceIdentityStorage.loadOrCreate(
            defaults: defaults,
            storageKey: DeviceIdentityPolicy.storageKey,
            platform: .mac,
            makeUUID: { canonicalUUID }
        )
        let reused = DeviceIdentityStorage.loadOrCreate(
            defaults: defaults,
            storageKey: DeviceIdentityPolicy.storageKey,
            platform: .mac,
            makeUUID: { replacementUUID }
        )

        #expect(generated == expected)
        #expect(reused == expected)
        #expect(generated.utf8.count == "mac-".utf8.count + canonicalUUID.uuidString.utf8.count)
        #expect(!generated.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))

        #if os(macOS)
        #expect(!generated.contains(ProcessInfo.processInfo.hostName))
        #expect(!generated.contains(NSUserName()))
        #endif
    }

    @Test
    func currentPlatformMatchesTheBuildPlatform() {
        #if os(macOS)
        #expect(DeviceIdentityPlatform.current == .mac)
        #elseif os(watchOS)
        #expect(DeviceIdentityPlatform.current == .watch)
        #else
        #expect(DeviceIdentityPlatform.current == .ios)
        #endif
    }

    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "CoreDeviceIdentityTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
