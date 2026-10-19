import Foundation

nonisolated enum TaskHierarchyMetadata {
    static func canonicalPath(for taskID: UUID) -> String {
        "/\(taskID.uuidString)"
    }
}
