import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TestHostIsolationTests {
    @Test
    func unitTestHostDetectionRecognizesXCTestEnvironment() {
        #expect(timetrackerApp.isUnitTestHost(environment: [
            "XCTestConfigurationFilePath": "/tmp/timetracker.xctestconfiguration",
        ]))
        #expect(timetrackerApp.isUnitTestHost(environment: [
            "XCTestBundlePath": "/tmp/timetrackerTests.xctest",
        ]))
        #expect(timetrackerApp.isUnitTestHost(environment: [:]) == false)
    }

    @Test
    func hostDetectionCoversUnitAndUITestProcesses() {
        #expect(AppRuntimeEnvironment.isTestHost(
            environment: ["XCTestBundlePath": "/tmp/timetrackerTests.xctest"],
            arguments: ["timetracker"]
        ))
        #expect(AppRuntimeEnvironment.isTestHost(
            environment: [:],
            arguments: ["timetracker", "--uitesting"]
        ))
        #expect(AppRuntimeEnvironment.isTestHost(
            environment: [:],
            arguments: ["timetracker"]
        ) == false)
    }

    @Test
    func thisProcessIsRecognizedAsATestHost() {
        // Every isolation expectation below depends on this being true.
        #expect(AppRuntimeEnvironment.isTestHost)
    }

    @Test
    func sharedDefaultsResolveToTheIsolatedSuiteNotTheInstalledAppDomain() {
        #expect(AppDefaults.shared !== UserDefaults.standard)

        let probeKey = "TimeTrackerTestHostIsolationProbe"
        UserDefaults.standard.removeObject(forKey: probeKey)
        defer {
            AppDefaults.shared.removeObject(forKey: probeKey)
            UserDefaults.standard.removeObject(forKey: probeKey)
        }

        AppDefaults.shared.set("written-by-test", forKey: probeKey)

        #expect(AppDefaults.shared.string(forKey: probeKey) == "written-by-test")
        // The installed app reads `.standard`; the write must be invisible there.
        #expect(UserDefaults.standard.string(forKey: probeKey) == nil)
    }

    @Test
    func armingCloudRecoveryFlagsNeverReachesTheInstalledAppDomain() {
        let keys = [
            AppCloudSync.pendingCloudUploadResetKey,
            AppCloudSync.pendingCloudDownloadResetKey,
            AppCloudSync.queuedCloudReconciliationKey,
            AppCloudSync.activeCloudReconciliationKey,
            AppCloudSync.cloudRecoveryStoreResetKey,
            AppCloudSync.activeCloudDownloadRecoveryKey,
        ]
        let standard = UserDefaults.standard
        let before = standard.dictionaryWithValues(forKeys: keys) as NSDictionary
        defer { keys.forEach { AppDefaults.shared.removeObject(forKey: $0) } }

        // The exact shape of write that used to leak out of an interrupted test
        // run and arm a destructive reset on the next real launch.
        keys.forEach { AppDefaults.shared.set(true, forKey: $0) }

        #expect(keys.allSatisfy { AppDefaults.shared.bool(forKey: $0) })
        #expect(before == standard.dictionaryWithValues(forKeys: keys) as NSDictionary)
    }

    @Test
    func demoDataOverrideWritesStayOutOfTheInstalledAppDomain() {
        let overrideKey = AppDemoDataConfiguration.overrideKey
        let seedingKey = SeedData.automaticDemoSeedingDisabledKey
        let standard = UserDefaults.standard
        let beforeOverride = standard.string(forKey: overrideKey)
        let beforeSeeding = standard.object(forKey: seedingKey) as? Bool
        defer {
            AppDefaults.shared.removeObject(forKey: overrideKey)
            AppDefaults.shared.removeObject(forKey: seedingKey)
        }

        AppDefaults.shared.set(
            AutomaticDemoDataMode.replaceOnLaunch.rawValue,
            forKey: overrideKey
        )
        AppDefaults.shared.set(false, forKey: seedingKey)

        #expect(standard.string(forKey: overrideKey) == beforeOverride)
        #expect(standard.object(forKey: seedingKey) as? Bool == beforeSeeding)
    }

    @Test
    func syncConflictStateDirectoryIsNamespacedAwayFromTheInstalledApp() throws {
        let directory = try SyncConflictService.defaultStateDirectoryURL()
        let productionName = SyncConflictService.stateDirectoryName

        // A snapshot written here must never be replayed into the real store,
        // which is what resurrected deleted Inbox items.
        #expect(directory.lastPathComponent != productionName)
        #expect(directory.lastPathComponent.hasPrefix(productionName))
        #expect(directory.lastPathComponent.hasSuffix(
            AppRuntimeEnvironment.testNamespaceSuffix
        ))
    }

    @Test
    func widgetSnapshotSuiteIsNamespacedAwayFromTheSharedAppGroup() {
        #expect(
            SharedWidgetSnapshotStore.effectiveSuiteName
                == SharedWidgetSnapshotStore.testSuiteName
        )
        #expect(
            SharedWidgetSnapshotStore.effectiveSuiteName
                != SharedWidgetSnapshotStore.suiteName
        )
    }

    @Test @MainActor
    func unitTestHostContainerLeavesApplicationRecoveryStateUntouched() throws {
        let keys = [
            AppCloudSync.enabledKey,
            AppCloudSync.modeKey,
            AppCloudSync.errorKey,
            AppCloudSync.accountStatusKey,
            AppCloudSync.pendingCloudUploadResetKey,
            AppCloudSync.pendingCloudDownloadResetKey,
            AppCloudSync.queuedCloudReconciliationKey,
            AppCloudSync.activeCloudReconciliationKey,
            AppCloudSync.cloudRecoveryStoreResetKey,
            AppCloudSync.activeCloudDownloadRecoveryKey,
        ]
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryWithValues(forKeys: keys) as NSDictionary

        let container = try timetrackerApp.makeUnitTestHostModelContainer()

        #expect(container.configurations.count == 1)
        #expect(before == defaults.dictionaryWithValues(forKeys: keys) as NSDictionary)
    }
}
