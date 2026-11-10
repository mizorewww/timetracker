import Foundation
import SwiftData
@testable import timetracker

/// Seeds a legacy-schema store and reopens it through the current schema so
/// every migration fixture shares one container/autoreleasepool scaffold.
@MainActor
struct LegacyStoreFixture<Seed> {
    let name: String
    let directory: URL
    let storeURL: URL
    let seed: Seed

    static func create<LegacySchema: VersionedSchema>(
        name: String,
        schema _: LegacySchema.Type,
        directoryPrefix: String? = nil,
        seed: (ModelContext) throws -> Seed
    ) throws -> LegacyStoreFixture<Seed> {
        pruneStaleDirectories()
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "TimeTracker\(directoryPrefix ?? name)-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appending(path: "store.sqlite")
        let seeded = try autoreleasepool {
            let legacySchema = Schema(versionedSchema: LegacySchema.self)
            let configuration = ModelConfiguration(
                name,
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: legacySchema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            let seed = try seed(context)
            try context.save()
            return seed
        }

        return LegacyStoreFixture(
            name: name,
            directory: directory,
            storeURL: storeURL,
            seed: seeded
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
            let currentSchema = TimeTrackerModelRegistry.currentSchema
            let configuration = ModelConfiguration(
                name,
                schema: currentSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: currentSchema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
            return try body(ModelContext(container))
        }
    }

    private static func pruneStaleDirectories() {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-10)
        guard let entries = try? fm.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("TimeTrackerLegacy") {
            if let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
               created < cutoff
            {
                try? fm.removeItem(at: url)
            }
        }
    }
}
