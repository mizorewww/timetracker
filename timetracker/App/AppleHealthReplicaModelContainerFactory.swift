import Foundation
import SwiftData

enum AppleHealthReplicaModelContainerFactory {
    @MainActor private static let applicationRepository:
        any AppleHealthReplicaRepository = makeApplicationRepository()

    static var persistentStoreURL: URL {
        AppCloudSync.persistentStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("AppleHealthReplica.store")
    }

    static func makePersistentContainer(
        at storeURL: URL = persistentStoreURL,
        name: String = "AppleHealthReplica"
    ) throws -> ModelContainer {
        try preparePersistentDirectory(at: storeURL)
        let schema = AppleHealthReplicaModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppleHealthReplicaMigrationPlan.self,
            configurations: [configuration]
        )
        try excludeStoreFilesFromBackup(at: storeURL)
        return container
    }

    static func makeInMemoryContainer(
        name: String = "AppleHealthReplicaMemory"
    ) throws -> ModelContainer {
        let schema = AppleHealthReplicaModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: AppleHealthReplicaMigrationPlan.self,
            configurations: [configuration]
        )
    }

    @MainActor
    static func platformDefaultRepository()
        -> any AppleHealthReplicaRepository
    {
        if AppRuntimeEnvironment.isTestHost {
            return makeRepository(
                container: {
                    try makeInMemoryContainer(
                        name: "AppleHealthReplicaTests-\(UUID().uuidString)"
                    )
                }
            )
        }
        return applicationRepository
    }

    @MainActor
    private static func makeApplicationRepository()
        -> any AppleHealthReplicaRepository
    {
        makeRepository(container: { try makePersistentContainer() })
    }

    @MainActor
    private static func makeRepository(
        container: () throws -> ModelContainer
    ) -> any AppleHealthReplicaRepository {
        do {
            return try SwiftDataAppleHealthReplicaRepository(
                container: container()
            )
        } catch {
            return UnavailableAppleHealthReplicaRepository(error: error)
        }
    }

    private static func preparePersistentDirectory(at storeURL: URL) throws {
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        #endif
        try excludeFromBackup(directory)
    }

    private static func excludeStoreFilesFromBackup(at storeURL: URL) throws {
        for url in [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal"),
        ] where FileManager.default.fileExists(atPath: url.path) {
            try excludeFromBackup(url)
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)
    }
}
