import SwiftData

enum TimeTrackerModelRegistry {
    static var currentSchema: Schema {
        Schema(versionedSchema: TimeTrackerSchemaV10.self)
    }

    static var currentModels: [any PersistentModel.Type] {
        TimeTrackerSchemaV10.models
    }

    static var cloudSyncedUserModelNames: Set<String> {
        Set(currentModels.map { String(describing: $0) })
    }
}
