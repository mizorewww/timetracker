import Foundation

nonisolated enum AppIdentity {
    static let bundleIdentifier = "me.mezorewww.timetracker"

    static var loggingSubsystem: String {
        Bundle.main.bundleIdentifier ?? bundleIdentifier
    }
}

/// Describes whether the current process is the shipping app or a test host.
///
/// The macOS target is deliberately unsandboxed, so an `xctest` host process and
/// the installed `/Applications/timetracker.app` share one preference domain,
/// one Application Support directory, and one App Group container. A test that
/// arms a CloudKit recovery flag and then crashes before its `defer` cleanup
/// leaves that flag set for the next *real* launch, which then performs a
/// destructive download reset or force upload against the user's iCloud data.
///
/// Everything that would otherwise write into those shared locations routes
/// through this type so a test host gets its own namespace instead.
nonisolated enum AppRuntimeEnvironment {
    /// Launch argument passed by every XCUITest target.
    static let uiTestingArgument = "--uitesting"

    /// True when this process is an XCTest host or a UI-test run of the app.
    static let isTestHost: Bool = isTestHost(
        environment: ProcessInfo.processInfo.environment,
        arguments: CommandLine.arguments
    )

    /// Pure form, so the decision itself is testable without a live process.
    static func isTestHost(
        environment: [String: String],
        arguments: [String]
    ) -> Bool {
        isUnitTestHost(environment: environment)
            || arguments.contains(uiTestingArgument)
    }

    /// Xcode sets one of these for every unit- and UI-test host process.
    static func isUnitTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }

    /// Suffix appended to shared on-disk and defaults namespaces under test.
    static let testNamespaceSuffix = "Tests"

    /// Namespaces a shared identifier so a test host can never collide with the
    /// installed app's copy of the same resource.
    static func namespaced(_ identifier: String) -> String {
        isTestHost ? "\(identifier)-\(testNamespaceSuffix)" : identifier
    }
}

/// The single entry point for app-level `UserDefaults` access.
///
/// Production returns `.standard`. A test host returns a private suite that is
/// wiped when it is first resolved, so no test can arm a recovery flag, a demo
/// data override, or a persistence-mode marker in the installed app's domain.
nonisolated enum AppDefaults {
    /// Suite backing every test-host read and write.
    static let testSuiteName = "me.mezorewww.timetracker.testhost"

    /// Foundation documents UserDefaults reads and writes as thread-safe even
    /// though the reference type does not yet conform to Sendable.
    nonisolated(unsafe) static let shared: UserDefaults =
        resolveShared()

    private static func resolveShared() -> UserDefaults {
        guard AppRuntimeEnvironment.isTestHost else { return .standard }
        guard let suite = UserDefaults(suiteName: testSuiteName) else {
            // A volatile in-memory fallback is still better than handing a test
            // host the installed app's domain.
            return UserDefaults()
        }
        // Start every test host from a clean slate. A previous run that was
        // interrupted must not leak flags into this one either.
        suite.removePersistentDomain(forName: testSuiteName)
        return suite
    }

    /// Clears the test suite. No-op in production so a shipping build can never
    /// wipe the user's preferences through this path.
    static func resetForTesting() {
        guard AppRuntimeEnvironment.isTestHost else { return }
        shared.removePersistentDomain(forName: testSuiteName)
    }
}
