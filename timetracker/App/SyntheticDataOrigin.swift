import Foundation

/// The single registry of `deviceID` values that mark a row as synthetic —
/// demo content, cloud smoke-test probes, or UI-test fixtures — rather than
/// something the user created.
///
/// Every producer of synthetic rows stamps one of these, and the maintenance
/// cleanup matches on `marks(_:)`. Keeping both sides on one list is what makes
/// "clear demo data" able to remove *all* non-user residue: the cloud
/// smoke-test task used to survive it, because the cleanup only knew `demo`.
///
/// Adding a new kind of synthetic data means adding its ID here, and nowhere
/// else, for it to become removable.
enum SyntheticDataOrigin {
    /// Rows built by `SeedData.buildDemoData`.
    static let demo = "demo"
    /// Probe rows written by `CloudSyncSmokeTestRunner`.
    static let cloudSmokeTest = "cloud-smoke"
    /// Rows attributed to a UI-test fixture.
    static let uiTest = "ui-test"

    static let all: Set<String> = [demo, cloudSmokeTest, uiTest]

    /// True when a row carrying this `deviceID` is synthetic, not user data.
    static func marks(_ deviceID: String) -> Bool {
        all.contains(deviceID)
    }
}
