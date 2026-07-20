import SwiftData

enum TimeTrackerModelRegistry {
    static var currentSchema: Schema {
        Schema(versionedSchema: TimeTrackerSchemaV13.self)
    }

    static var currentModels: [any PersistentModel.Type] {
        TimeTrackerSchemaV13.models
    }

    static var cloudSyncedUserModelNames: Set<String> {
        Set(currentModels.map { String(describing: $0) })
    }
}
