import Foundation
import SwiftData

@MainActor
struct DatabaseMaintenanceService {
    @discardableResult
    func optimizeDatabase(context: ModelContext) throws -> Int {
        let allTasks = try context.fetch(FetchDescriptor<TaskNode>())
        let visibleTaskIDs = Set(allTasks.filter { $0.deletedAt == nil }.map(\.id))
        let allSegments = try context.fetch(FetchDescriptor<TimeSegment>())
        let allSessions = try context.fetch(FetchDescriptor<TimeSession>())
        let allRuns = try context.fetch(FetchDescriptor<PomodoroRun>())

        let orphanSessions = allSessions.filter { !visibleTaskIDs.contains($0.taskID) }
        let orphanSessionIDsByTask = Set(orphanSessions.map(\.id))
        let orphanSegments = allSegments.filter {
            !visibleTaskIDs.contains($0.taskID) || orphanSessionIDsByTask.contains($0.sessionID)
        }
        let orphanRuns = allRuns.filter { !visibleTaskIDs.contains($0.taskID) }
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
