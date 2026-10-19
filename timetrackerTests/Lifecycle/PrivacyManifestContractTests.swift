import Foundation
import Testing

@Suite(.serialized)
struct PrivacyManifestContractTests {
    @Test
    func mainAppUsesTheCanonicalAPSEntitlementKey() throws {
        let root = try projectRootURL()
        let url = root.appending(path: "timetracker/timetracker.entitlements")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        )
        let entitlements = try #require(propertyList as? [String: Any])

        #expect(entitlements["aps-environment"] as? String == "development")
        #expect(entitlements["com.apple.developer.aps-environment"] == nil)
    }

    @Test
    func privacyManifestsDoNotDeclareTrackingOrCollectedData() throws {
        let root = try projectRootURL()
        let paths = [
            "timetracker/PrivacyInfo.xcprivacy",
            "timetrackerWidgetExtension/PrivacyInfo.xcprivacy",
            "timetrackerWatchApp/PrivacyInfo.xcprivacy",
        ]

        for path in paths {
            let manifest = try manifest(at: root.appending(path: path))
            #expect(manifest["NSPrivacyTracking"] as? Bool == false, Comment(rawValue: path))
            #expect(
                (manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true,
                Comment(rawValue: path)
            )
        }
    }

    private func manifest(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(value as? [String: Any])
    }
}
