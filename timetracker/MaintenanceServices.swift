import Foundation
import SwiftData

@MainActor
struct DatabaseMaintenanceService {
    @discardableResult
    func optimizeDatabase(context: ModelContext) throws -> Int {
        let allTasks = try context.fetch(FetchDescriptor<TaskNode>())
        let validTaskIDs = Set(allTasks.map(\.id))
        let allSegments = try context.fetch(FetchDescriptor<TimeSegment>())
        let allSessions = try context.fetch(FetchDescriptor<TimeSession>())
        let allRuns = try context.fetch(FetchDescriptor<PomodoroRun>())

        let orphanSegments = allSegments.filter { !validTaskIDs.contains($0.taskID) }
        let orphanSessions = allSessions.filter { !validTaskIDs.contains($0.taskID) }
        let orphanRuns = allRuns.filter { !validTaskIDs.contains($0.taskID) }
        let orphanSegmentIDs = Set(orphanSegments.map(\.id))
        let sessionIDsWithSegments = Set(allSegments.filter { !orphanSegmentIDs.contains($0.id) }.map(\.sessionID))
        let emptySessions = allSessions.filter { !sessionIDsWithSegments.contains($0.id) }
        var removedSessionIDs = Set<UUID>()
        let removableSessions = (orphanSessions + emptySessions).filter { removedSessionIDs.insert($0.id).inserted }

        for segment in orphanSegments {
            context.delete(segment)
        }
        for session in removableSessions {
            context.delete(session)
        }
        for run in orphanRuns {
            context.delete(run)
        }

        try context.save()
        return orphanSegments.count + removableSessions.count + orphanRuns.count
    }
}

struct CSVExportService {
    func export(
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskByID: [UUID: TaskNode],
        taskParentPathByID: [UUID: String],
        now: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let header = ["Task", "Path", "Start", "End", "Duration Seconds", "Source", "Note"]
        let rows = segments
            .filter { $0.deletedAt == nil }
            .sorted { $0.startedAt < $1.startedAt }
            .map { segment in
                let session = sessionByID[segment.sessionID]
                return [
                    title(for: segment, taskByID: taskByID, session: session),
                    path(for: segment, taskByID: taskByID, taskParentPathByID: taskParentPathByID),
                    formatter.string(from: segment.startedAt),
                    segment.endedAt.map { formatter.string(from: $0) } ?? "",
                    "\(Int((segment.endedAt ?? now).timeIntervalSince(segment.startedAt)))",
                    segment.source.rawValue,
                    session?.note ?? ""
                ]
            }
        return ([header] + rows)
            .map { $0.map(Self.csvEscaped).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private func title(for segment: TimeSegment, taskByID: [UUID: TaskNode], session: TimeSession?) -> String {
        taskByID[segment.taskID]?.title ?? session?.titleSnapshot ?? AppStrings.localized("task.deleted")
    }

    private func path(
        for segment: TimeSegment,
        taskByID: [UUID: TaskNode],
        taskParentPathByID: [UUID: String]
    ) -> String {
        guard taskByID[segment.taskID] != nil else { return AppStrings.localized("task.deleted.path") }
        return taskParentPathByID[segment.taskID] ?? ""
    }

    nonisolated static func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
