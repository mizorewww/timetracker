import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TestHostIsolationTests {
    @Test
    func hostDetectionCoversUnitAndUITestProcesses() {
        // Every isolation expectation below depends on this being true.
        #expect(AppRuntimeEnvironment.isTestHost)
        #expect(AppRuntimeEnvironment.isTestHost(
            environment: ["XCTestConfigurationFilePath": "/tmp/timetracker.xctestconfiguration"],
            arguments: ["timetracker"]
        ))
        #expect(AppRuntimeEnvironment.isTestHost(
            environment: [:],
            arguments: ["timetracker", AppRuntimeEnvironment.uiTestingArgument]
        ))
        #expect(AppRuntimeEnvironment.isTestHost(
            environment: [:],
            arguments: ["timetracker"]
        ) == false)
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

    #if DEBUG
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
    #endif

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
    func unitTestHostContainerLeavesApplicationPersistenceStateUntouched() throws {
        let keys = [
            AppCloudSync.enabledKey,
            AppCloudSync.modeKey,
            AppCloudSync.errorKey,
        ]
        let defaults = UserDefaults.standard
        let before = defaults.dictionaryWithValues(forKeys: keys) as NSDictionary

        let container = try timetrackerApp.makeUnitTestHostModelContainer()

        #expect(container.configurations.count == 1)
        #expect(before == defaults.dictionaryWithValues(forKeys: keys) as NSDictionary)
    }
}
