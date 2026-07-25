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
