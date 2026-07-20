import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TodayActivityHeatmapTests {
    @Test
    func fixedIntensityThresholdsStayComparableAcrossWeeks() {
        #expect(ActivityHeatmapIntensity(completionCount: -1) == .none)
        #expect(ActivityHeatmapIntensity(completionCount: 0) == .none)
        #expect(ActivityHeatmapIntensity(completionCount: 1) == .low)
        #expect(ActivityHeatmapIntensity(completionCount: 2) == .medium)
        #expect(ActivityHeatmapIntensity(completionCount: 3) == .high)
        #expect(ActivityHeatmapIntensity(completionCount: 4) == .maximum)
        #expect(ActivityHeatmapIntensity(completionCount: 100) == .maximum)
    }

    @Test @MainActor
    func selectedBranchesCountChecklistCompletionsOnceAndRetainArchivedHistory() throws {
        let calendar = try testCalendar()
        let now = try testDate(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12,
            calendar: calendar
        )
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        let outsideWindow = try #require(
            calendar.date(byAdding: .weekOfYear, value: -53, to: today)
        )
        let root = task("Archived parent")
        root.statusRaw = LegacyTaskStatusRaw.archived
        let child = task("Child", parentID: root.id)
        child.archivedAt = now.addingTimeInterval(-100)
        let grandchild = task("Grandchild", parentID: child.id)
        let unrelated = task("Unrelated")
        let deleted = task("Deleted", parentID: root.id)
        deleted.deletedAt = now.addingTimeInterval(-50)
        let orphanID = UUID()
        let olderActive = checklist(
            taskID: child.id,
            completedAt: today.addingTimeInterval(800)
        )
        olderActive.updatedAt = now.addingTimeInterval(-100)
        let newerTombstone = checklist(
            taskID: child.id,
            completedAt: today.addingTimeInterval(800),
            deletedAt: now
        )
        newerTombstone.id = olderActive.id
        newerTombstone.updatedAt = now

        let items = [
            checklist(taskID: root.id, completedAt: now),
            checklist(taskID: child.id, completedAt: today.addingTimeInterval(200)),
            checklist(taskID: grandchild.id, completedAt: today.addingTimeInterval(300)),
            checklist(taskID: child.id, completedAt: yesterday.addingTimeInterval(400)),
            checklist(taskID: unrelated.id, completedAt: today.addingTimeInterval(500)),
            checklist(taskID: deleted.id, completedAt: today.addingTimeInterval(600)),
            checklist(taskID: orphanID, completedAt: today.addingTimeInterval(650)),
            checklist(
                taskID: child.id,
                isCompleted: false,
                completedAt: today.addingTimeInterval(700)
            ),
            checklist(taskID: child.id, completedAt: nil),
            checklist(
                taskID: child.id,
                completedAt: now.addingTimeInterval(86_400)
            ),
            checklist(taskID: child.id, completedAt: outsideWindow),
            olderActive,
            newerTombstone,
        ]
        let service = TodayActivityHeatmapSnapshotService()
        let tasks = [root, child, grandchild, unrelated, deleted]
        let snapshot = service.snapshot(
            selectedTaskIDs: [
                root.id,
                child.id,
                root.id,
                deleted.id,
                orphanID,
            ],
            tasks: tasks,
            checklistItems: items,
            now: now,
            calendar: calendar
        )

        #expect(
            service.contributingTaskIDs(
                selectedTaskIDs: [root.id, child.id],
                tasks: tasks
            ) == Set([root.id, child.id, grandchild.id])
        )
        #expect(snapshot.totalCompletionCount == 4)
        #expect(snapshot.activeDayCount == 2)
        #expect(day(today, in: snapshot, calendar: calendar)?.completionCount == 3)
        #expect(day(today, in: snapshot, calendar: calendar)?.intensity == .high)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.completionCount == 1)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.intensity == .low)
    }

    @Test @MainActor
    func completionHistoryIsDerivedFromCurrentChecklistState() throws {
        let calendar = try testCalendar()
        let now = try testDate(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12,
            calendar: calendar
        )
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        let root = task("Root")
        let item = checklist(
            taskID: root.id,
            completedAt: today.addingTimeInterval(60)
        )
        let service = TodayActivityHeatmapSnapshotService()

        var snapshot = service.snapshot(
            selectedTaskIDs: [root.id],
            tasks: [root],
            checklistItems: [item],
            now: now,
            calendar: calendar
        )
        #expect(day(today, in: snapshot, calendar: calendar)?.completionCount == 1)

        item.isCompleted = false
        item.completedAt = nil
        snapshot = service.snapshot(
            selectedTaskIDs: [root.id],
            tasks: [root],
            checklistItems: [item],
            now: now,
            calendar: calendar
        )
        #expect(snapshot.totalCompletionCount == 0)

        item.isCompleted = true
        item.completedAt = yesterday.addingTimeInterval(60)
        snapshot = service.snapshot(
            selectedTaskIDs: [root.id],
            tasks: [root],
            checklistItems: [item],
            now: now,
            calendar: calendar
        )
        #expect(day(today, in: snapshot, calendar: calendar)?.completionCount == 0)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.completionCount == 1)
    }

    @Test @MainActor
    func calendarProducesFiftyThreeLocaleWeeksAndMarksFutureCells() throws {
        var calendar = try testCalendar(
            timeZone: TimeZone(identifier: "America/Los_Angeles")
        )
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = try testDate(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12,
            calendar: calendar
        )
        let root = task("Root")
        let snapshot = TodayActivityHeatmapSnapshotService().snapshot(
            selectedTaskIDs: [root.id, UUID()],
            tasks: [root],
            checklistItems: [],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.weeks.count == 53)
        #expect(snapshot.weeks.allSatisfy { $0.days.count == 7 })
        #expect(
            calendar.component(
                .weekday,
                from: try #require(snapshot.weeks.first?.startDate)
            ) == calendar.firstWeekday
        )
        let cells = snapshot.weeks.flatMap(\.days)
        #expect(cells.filter(\.isToday).count == 1)
        #expect(cells.contains { $0.isFuture })
        #expect(cells.filter(\.isFuture).allSatisfy { $0.intensity == .none })
        #expect(
            cells.allSatisfy {
                calendar.startOfDay(for: $0.date) == $0.date
            }
        )
        let daylightSavingStart = try testDate(
            year: 2026,
            month: 3,
            day: 8,
            hour: 0,
            calendar: calendar
        )
        let dayAfter = try #require(
            calendar.date(
                byAdding: .day,
                value: 1,
                to: daylightSavingStart
            )
        )
        #expect(dayAfter.timeIntervalSince(daylightSavingStart) == 23 * 60 * 60)
        #expect(
            cells.contains {
                $0.date == daylightSavingStart
            }
        )
        #expect(cells.contains { $0.date == dayAfter })
        #expect(snapshot.totalCompletionCount == 0)
    }

    @MainActor
    private func task(
        _ title: String,
        parentID: UUID? = nil
    ) -> TaskNode {
        TaskNode(
            title: title,
            parentID: parentID,
            deviceID: "test"
        )
    }

    @MainActor
    private func checklist(
        taskID: UUID,
        isCompleted: Bool = true,
        completedAt: Date?,
        deletedAt: Date? = nil
    ) -> ChecklistItem {
        let item = ChecklistItem(
            taskID: taskID,
            title: "Item",
            isCompleted: false,
            deviceID: "test"
        )
        item.isCompleted = isCompleted
        item.completedAt = completedAt
        item.deletedAt = deletedAt
        return item
    }

    private func testCalendar(
        timeZone: TimeZone? = nil
    ) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        if let timeZone {
            calendar.timeZone = timeZone
        } else {
            calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        }
        return calendar
    }

    private func testDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        calendar: Calendar
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour
                )
            )
        )
    }

    private func day(
        _ date: Date,
        in snapshot: ActivityHeatmapSnapshot,
        calendar: Calendar
    ) -> ActivityHeatmapDay? {
        snapshot.weeks
            .lazy
            .flatMap(\.days)
            .first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
