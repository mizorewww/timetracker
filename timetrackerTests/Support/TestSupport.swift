import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
func makeTestContext() throws -> ModelContext {
    let schema = TimeTrackerModelRegistry.currentSchema
    let configuration = ModelConfiguration(
        "TimeTrackerTests",
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(
        for: schema,
        migrationPlan: TimeTrackerMigrationPlan.self,
        configurations: [configuration]
    )
    return ModelContext(container)
}

func projectRootURL() throws -> URL {
    var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while current.path != "/" {
        if FileManager.default.fileExists(atPath: current.appending(path: "timetracker.xcodeproj").path) {
            return current
        }
        current.deleteLastPathComponent()
    }

    struct ProjectRootError: Error {}
    throw ProjectRootError()
}

func sourceText(_ relativePath: String) throws -> String {
    try String(contentsOf: projectRootURL().appending(path: relativePath), encoding: .utf8)
}
