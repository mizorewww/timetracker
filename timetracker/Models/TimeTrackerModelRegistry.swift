import SwiftData

enum TimeTrackerModelRegistry {
    static var currentSchema: Schema {
        Schema(versionedSchema: TimeTrackerSchemaV9.self)
    }

    static var currentModels: [any PersistentModel.Type] {
        TimeTrackerSchemaV9.models
    }

    static var cloudSyncedUserModelNames: Set<String> {
        Set(currentModels.map { String(describing: $0) })
    }
}
