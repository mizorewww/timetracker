#if DEBUG
import Foundation

/// The single registry of `deviceID` values that mark a row as synthetic
/// rather than something the user created. Every producer of synthetic rows
/// stamps one of these, and the maintenance cleanup matches on `marks(_:)`,
/// so adding a new kind of synthetic data means adding its ID here.
enum SyntheticDataOrigin {
    /// Rows built by `SeedData.buildDemoData`.
    static let demo = "demo"

    /// True when a row carrying this `deviceID` is synthetic, not user data.
    static func marks(_ deviceID: String) -> Bool {
        deviceID == demo
    }
}
#endif
