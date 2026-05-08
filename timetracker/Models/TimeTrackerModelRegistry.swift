import SwiftData

enum TimeTrackerModelRegistry {
    static var currentSchema: Schema {
        Schema(versionedSchema: TimeTrackerSchemaV8.self)
    }

    static var currentModels: [any PersistentModel.Type] {
        TimeTrackerSchemaV8.models
    }

    static var cloudSyncedUserModelNames: Set<String> {
        Set(currentModels.map { String(describing: $0) })
    }
}
