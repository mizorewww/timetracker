import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSystemActionCommandTests {
    @Test
    func appIntentsAreThinWrappersAroundSystemActionCommands() throws {
        let source = try sourceText("timetracker/AppIntents/TimeTrackerAppIntents.swift")

        #expect(source.contains("import AppIntents"))
        #expect(source.contains("struct AddInboxItemIntent: AppIntent"))
        #expect(source.contains("struct StartTimerIntent: AppIntent"))
        #expect(source.contains("struct StopTimerIntent: AppIntent"))
        #expect(source.contains("SystemActionCommandHandler()"))
        #expect(source.contains("TimeSegment(") == false)
        #expect(source.contains("TimeSession(") == false)
        #expect(source.contains("context.insert") == false)
    }

    @Test @MainActor
    func systemActionAddInboxItemUsesSharedCommandHandler() throws {
        let context = try makeTestContext()
        let handler = SystemActionCommandHandler()

        let itemID = try #require(try handler.addInboxItem(title: "Capture from shortcut", context: context, deviceID: "test"))

        let items = try context.fetch(FetchDescriptor<InboxItem>())
        #expect(items.map(\.id) == [itemID])
        #expect(items.map(\.title) == ["Capture from shortcut"])
        #expect(items.map(\.deviceID) == ["test"])
    }

    @Test @MainActor
    func systemActionStartTimerCreatesTimerLedgerSegment() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Shortcut task", parentID: nil, colorHex: nil, iconName: nil)
        let handler = SystemActionCommandHandler()

        let segmentID = try #require(try handler.startTimer(
            taskID: task.id,
            allowParallelTimers: true,
            context: context
        ))

        let segments = try context.fetch(FetchDescriptor<TimeSegment>())
        #expect(segments.map(\.id) == [segmentID])
        #expect(segments.map(\.taskID) == [task.id])
        #expect(segments.map(\.source) == [.timer])
        #expect(segments.first?.endedAt == nil)
    }

    @Test @MainActor
    func systemActionStopTimerClosesActiveSegment() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Running task", parentID: nil, colorHex: nil, iconName: nil)
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        let handler = SystemActionCommandHandler()

        let stoppedID = try #require(try handler.stopTimer(taskID: task.id, context: context))

        #expect(stoppedID == segment.id)
        let stoppedSegment = try #require(try timeRepository.allSegments().first)
        #expect(stoppedSegment.endedAt != nil)
    }
}
