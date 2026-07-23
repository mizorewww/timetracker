import Foundation
import SwiftData

extension timetrackerApp {
    static func makeUnitTestHostModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TimeTrackerUnitTestHost",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeUITestModelContainer() throws -> ModelContainer {
        let arguments = CommandLine.arguments
        let usesPersistentStore = arguments.contains(
            "--uitesting-persistent-store"
        )
        if arguments.contains("--uitesting-reset-persistent-store") ||
            arguments.contains("--uitesting-clean-persistent-store") {
            try removePersistentUITestStoreFiles()
        }

        guard usesPersistentStore else {
            let configuration = ModelConfiguration(
                "TimeTrackerUITests",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            AppCloudSync.recordUITesting()
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
        }

        try FileManager.default.createDirectory(
            at: persistentUITestStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let configuration = ModelConfiguration(
            "TimeTrackerUITests",
            schema: schema,
            url: persistentUITestStoreURL,
            cloudKitDatabase: .none
        )
        AppCloudSync.recordUITesting()
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static var persistentUITestStoreURL: URL {
        AppCloudSync.persistentStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("TimeTracker-UITests.store")
    }

    private static func removePersistentUITestStoreFiles() throws {
        let fileManager = FileManager.default
        let directory = persistentUITestStoreURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: directory.path) else { return }

        let storePrefix = persistentUITestStoreURL.lastPathComponent
        for file in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) where file.lastPathComponent.hasPrefix(storePrefix) {
            try fileManager.removeItem(at: file)
        }
    }

    static func isUnitTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}
