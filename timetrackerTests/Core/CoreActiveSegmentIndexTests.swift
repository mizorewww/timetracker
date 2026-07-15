import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreActiveSegmentIndexTests {
    @Test @MainActor
    func activeSegmentIndexTracksReplacementAndPreservesCanonicalFirstMatch() {
        let store = TimeTrackerStore()
        let taskID = UUID()
        let first = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let duplicate = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSinceReferenceDate: 200)
        )

        store.activeSegments = [first, duplicate]
        #expect(store.activeSegment(for: taskID)?.id == first.id)

        store.activeSegments = [duplicate]
        #expect(store.activeSegment(for: taskID)?.id == duplicate.id)

        store.activeSegments = []
        #expect(store.activeSegment(for: taskID) == nil)
        #expect(store.activeSegmentByTaskID.isEmpty)
    }

    @Test
    func taskRowsUseTheIndexedActiveSegmentReadModel() throws {
        let files = [
            "timetracker/Features/Tasks/Management/TaskManagementRowViews.swift",
            "timetracker/Features/Tasks/Management/TaskRowComponents.swift",
            "timetracker/Features/Tasks/Detail/TaskDetailView.swift"
        ]
        let source = try files.map(sourceText).joined(separator: "\n")

        #expect(source.contains("store.activeSegment(for: task.id)"))
        #expect(source.contains("store.activeSegments.first { $0.taskID == task.id }") == false)
        #expect(source.contains("store.activeSegments.contains { $0.taskID == task.id }") == false)
    }
}
