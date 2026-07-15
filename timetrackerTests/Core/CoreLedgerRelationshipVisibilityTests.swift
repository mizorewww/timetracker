import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLedgerRelationshipVisibilityTests {
    @Test @MainActor
    func missingTaskRowsAreQuarantinedUntilTheTaskImports() throws {
        let context = try makeTestContext()
        let now = try stableReferenceDate()
        let missingTaskID = UUID()
        let session = TimeSession(
            taskID: missingTaskID,
            source: .manual,
            deviceID: "remote",
            startedAt: now.addingTimeInterval(-300)
        )
        session.endedAt = now
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: missingTaskID,
            source: .manual,
            deviceID: "remote",
            startedAt: now.addingTimeInterval(-300),
            endedAt: now
        )
        context.insert(session)
        context.insert(segment)
        try context.save()

        let store = try refreshedStore(context: context)

        #expect(store.allSegments.isEmpty)
        #expect(store.todaySegments.isEmpty)
        #expect(store.todayGrossSeconds(now: now) == 0)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).map(\.id) == [segment.id])

        let importedTask = TaskNode(title: "Imported later", parentID: nil, deviceID: "remote")
        importedTask.id = missingTaskID
        context.insert(importedTask)
        try context.save()
        try store.refresh()

        #expect(store.allSegments.map(\.id) == [segment.id])
        #expect(store.todayGrossSeconds(now: now) == 300)
    }

    @Test @MainActor
    func missingSessionRowsAreQuarantinedUntilTheSessionImports() throws {
        let context = try makeTestContext()
        let now = try stableReferenceDate()
        let task = TaskNode(title: "Existing task", parentID: nil, deviceID: "remote")
        let missingSessionID = UUID()
        let segment = TimeSegment(
            sessionID: missingSessionID,
            taskID: task.id,
            source: .manual,
            deviceID: "remote",
            startedAt: now.addingTimeInterval(-120),
            endedAt: now
        )
        context.insert(task)
        context.insert(segment)
        try context.save()

        let store = try refreshedStore(context: context)
        #expect(store.allSegments.isEmpty)

        let importedSession = TimeSession(
            taskID: task.id,
            source: .manual,
            deviceID: "remote",
            startedAt: segment.startedAt
        )
        importedSession.id = missingSessionID
        importedSession.endedAt = now
        context.insert(importedSession)
        try context.save()
        try store.refresh()

        #expect(store.allSegments.map(\.id) == [segment.id])
        #expect(store.todayGrossSeconds(now: now) == 120)
    }

    @Test @MainActor
    func mismatchedSessionTaskNeverEntersAnalyticsOrSystemSurfaces() throws {
        let context = try makeTestContext()
        let now = try stableReferenceDate()
        let sessionTask = TaskNode(title: "Session task", parentID: nil, deviceID: "remote")
        let segmentTask = TaskNode(title: "Segment task", parentID: nil, deviceID: "remote")
        let session = TimeSession(
            taskID: sessionTask.id,
            source: .manual,
            deviceID: "remote",
            startedAt: now.addingTimeInterval(-60)
        )
        session.endedAt = now
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: segmentTask.id,
            source: .manual,
            deviceID: "remote",
            startedAt: now.addingTimeInterval(-60),
            endedAt: now
        )
        context.insert(sessionTask)
        context.insert(segmentTask)
        context.insert(session)
        context.insert(segment)
        try context.save()

        let store = try refreshedStore(context: context)

        #expect(store.allSegments.isEmpty)
        #expect(store.activeSegments.isEmpty)
        #expect(store.todayGrossSeconds(now: now) == 0)
        #expect(store.analyticsSnapshot(for: .today, now: now).overview.grossSeconds == 0)
    }

    @MainActor
    private func refreshedStore(context: ModelContext) throws -> TimeTrackerStore {
        let store = TimeTrackerStore()
        store.configureRepositoriesIfNeeded(context: context)
        try store.refresh()
        return store
    }

    private func stableReferenceDate(calendar: Calendar = .current) throws -> Date {
        let currentDayStart = calendar.startOfDay(for: Date())
        let previousDayStart = try #require(
            calendar.date(byAdding: .day, value: -1, to: currentDayStart)
        )
        return previousDayStart.addingTimeInterval(12 * 3_600)
    }
}
