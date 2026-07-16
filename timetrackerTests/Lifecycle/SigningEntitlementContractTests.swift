import Foundation
import Testing

@Suite(.serialized)
struct SigningEntitlementContractTests {
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
}
