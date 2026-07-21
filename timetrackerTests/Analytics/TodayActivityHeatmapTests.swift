import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TodayActivityHeatmapTests {
    @Test
    func dynamicIntensityUsesFourQuartilesOfItsReference() {
        #expect(ActivityHeatmapIntensity(value: -1, referenceValue: 100) == .none)
        #expect(ActivityHeatmapIntensity(value: 0, referenceValue: 100) == .none)
        #expect(ActivityHeatmapIntensity(value: 1, referenceValue: 100) == .low)
        #expect(ActivityHeatmapIntensity(value: 25, referenceValue: 100) == .low)
        #expect(ActivityHeatmapIntensity(value: 26, referenceValue: 100) == .medium)
        #expect(ActivityHeatmapIntensity(value: 50, referenceValue: 100) == .medium)
        #expect(ActivityHeatmapIntensity(value: 51, referenceValue: 100) == .high)
        #expect(ActivityHeatmapIntensity(value: 75, referenceValue: 100) == .high)
        #expect(ActivityHeatmapIntensity(value: 76, referenceValue: 100) == .maximum)
        #expect(ActivityHeatmapIntensity(value: 100, referenceValue: 100) == .maximum)
        #expect(ActivityHeatmapIntensity(value: 200, referenceValue: 100) == .maximum)
        #expect(ActivityHeatmapIntensity(value: 1, referenceValue: 0) == .none)
    }

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

    @Test @MainActor
    func selectedTasksProduceIndependentChecklistAndDurationSnapshots() throws {
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
        let checklistRoot = task("Checklist Root", colorHex: "7C3AED")
        let checklistChild = task("Checklist Child", parentID: checklistRoot.id)
        let durationRoot = task("Duration Root", colorHex: "F97316")
        let service = TodayActivityHeatmapSnapshotService()
        let snapshots = service.taskSnapshots(
            selectedTaskIDs: [durationRoot.id, checklistRoot.id, durationRoot.id],
            tasks: [checklistRoot, checklistChild, durationRoot],
            segments: [
                segment(
                    taskID: durationRoot.id,
                    start: yesterday.addingTimeInterval(9 * 3_600),
                    end: yesterday.addingTimeInterval(10 * 3_600)
                ),
                segment(
                    taskID: durationRoot.id,
                    start: today.addingTimeInterval(8 * 3_600),
                    end: today.addingTimeInterval(10 * 3_600)
                ),
            ],
            checklistItems: [
                checklist(
                    taskID: checklistChild.id,
                    completedAt: yesterday.addingTimeInterval(60)
                ),
                checklist(
                    taskID: checklistChild.id,
                    completedAt: today.addingTimeInterval(60)
                ),
                checklist(
                    taskID: checklistChild.id,
                    completedAt: today.addingTimeInterval(120)
                ),
            ],
            quantityGoals: [],
            quantityEntries: [],
            now: now,
            calendar: calendar
        )

        #expect(snapshots.map(\.taskID) == [durationRoot.id, checklistRoot.id])
        let duration = try #require(snapshots.first)
        #expect(duration.metric == .trackedDuration)
        #expect(duration.colorHex == "F97316")
        #expect(duration.totalValue == 3 * 3_600)
        #expect(duration.maximumDailyValue == 2 * 3_600)
        #expect(duration.activeDayCount == 2)
        #expect(day(yesterday, in: duration, calendar: calendar)?.value == 3_600)
        #expect(day(yesterday, in: duration, calendar: calendar)?.intensity == .medium)
        #expect(day(today, in: duration, calendar: calendar)?.value == 2 * 3_600)
        #expect(day(today, in: duration, calendar: calendar)?.intensity == .maximum)

        let checklistSnapshot = try #require(snapshots.last)
        #expect(checklistSnapshot.metric == .checklistCompletions)
        #expect(checklistSnapshot.colorHex == "7C3AED")
        #expect(checklistSnapshot.totalValue == 3)
        #expect(checklistSnapshot.maximumDailyValue == 2)
        #expect(day(yesterday, in: checklistSnapshot, calendar: calendar)?.value == 1)
        #expect(day(yesterday, in: checklistSnapshot, calendar: calendar)?.intensity == .medium)
        #expect(day(today, in: checklistSnapshot, calendar: calendar)?.value == 2)
        #expect(day(today, in: checklistSnapshot, calendar: calendar)?.intensity == .maximum)
    }

    @Test @MainActor
    func durationSplitsAtCalendarMidnightAndClipsActiveAndFutureSegments() throws {
        var calendar = try testCalendar(
            timeZone: TimeZone(identifier: "America/Los_Angeles")
        )
        calendar.firstWeekday = 2
        let now = try testDate(
            year: 2026,
            month: 3,
            day: 8,
            hour: 4,
            calendar: calendar
        )
        let today = calendar.startOfDay(for: now)
        let yesterday = try #require(
            calendar.date(byAdding: .day, value: -1, to: today)
        )
        let root = task("Duration")
        let snapshots = TodayActivityHeatmapSnapshotService().taskSnapshots(
            selectedTaskIDs: [root.id],
            tasks: [root],
            segments: [
                segment(
                    taskID: root.id,
                    start: yesterday.addingTimeInterval(23 * 3_600),
                    end: today.addingTimeInterval(2 * 3_600)
                ),
                segment(
                    taskID: root.id,
                    start: now.addingTimeInterval(-3_600),
                    end: nil
                ),
                segment(
                    taskID: root.id,
                    start: now.addingTimeInterval(3_600),
                    end: now.addingTimeInterval(7_200)
                ),
            ],
            checklistItems: [],
            quantityGoals: [],
            quantityEntries: [],
            now: now,
            calendar: calendar
        )
        let snapshot = try #require(snapshots.first)

        #expect(day(yesterday, in: snapshot, calendar: calendar)?.value == 3_600)
        #expect(day(today, in: snapshot, calendar: calendar)?.value == 3 * 3_600)
        #expect(snapshot.totalValue == 4 * 3_600)
        #expect(snapshot.weeks.flatMap(\.days).filter(\.isFuture).allSatisfy {
            $0.value == 0 && $0.intensity == .none
        })
    }

    @Test @MainActor
    func quantityUsesDeclaredGoalInsteadOfObservedMaximum() throws {
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
        let quantityTask = task("Push-ups", colorHex: "16A34A")
        let goal = quantityGoal(
            taskID: quantityTask.id,
            targetAmount: 50,
            unitLabel: "reps"
        )
        let snapshots = TodayActivityHeatmapSnapshotService().taskSnapshots(
            selectedTaskIDs: [quantityTask.id],
            tasks: [quantityTask],
            segments: [
                segment(
                    taskID: quantityTask.id,
                    start: today,
                    end: today.addingTimeInterval(10_000)
                ),
            ],
            checklistItems: [
                checklist(
                    taskID: quantityTask.id,
                    completedAt: today.addingTimeInterval(60)
                ),
            ],
            quantityGoals: [goal],
            quantityEntries: [
                quantityEntry(
                    taskID: quantityTask.id,
                    amount: 25,
                    recordedAt: yesterday.addingTimeInterval(60)
                ),
                quantityEntry(
                    taskID: quantityTask.id,
                    amount: 60,
                    recordedAt: today.addingTimeInterval(60)
                ),
                quantityEntry(
                    taskID: quantityTask.id,
                    amount: 5,
                    recordedAt: now.addingTimeInterval(3_600)
                ),
            ],
            now: now,
            calendar: calendar
        )
        let snapshot = try #require(snapshots.first)

        #expect(snapshot.metric == .quantity(unitLabel: "reps"))
        #expect(snapshot.totalValue == 85)
        #expect(snapshot.maximumDailyValue == 60)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.value == 25)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.referenceValue == 50)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.intensity == .medium)
        #expect(day(today, in: snapshot, calendar: calendar)?.value == 60)
        #expect(day(today, in: snapshot, calendar: calendar)?.intensity == .maximum)
    }

    @MainActor
    private func task(
        _ title: String,
        parentID: UUID? = nil,
        colorHex: String? = nil
    ) -> TaskNode {
        TaskNode(
            title: title,
            parentID: parentID,
            deviceID: "test",
            colorHex: colorHex
        )
    }

    @MainActor
    private func segment(
        taskID: UUID,
        start: Date,
        end: Date?
    ) -> TimeSegment {
        TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: end
        )
    }

    @MainActor
    private func quantityGoal(
        taskID: UUID,
        targetAmount: Int,
        unitLabel: String
    ) -> TaskQuantityGoal {
        TaskQuantityGoal(
            taskID: taskID,
            targetAmount: targetAmount,
            unitLabel: unitLabel,
            deviceID: "test"
        )
    }

    @MainActor
    private func quantityEntry(
        taskID: UUID,
        amount: Int,
        recordedAt: Date
    ) -> TaskQuantityEntry {
        TaskQuantityEntry(
            id: UUID(),
            taskID: taskID,
            amount: amount,
            recordedAt: recordedAt,
            createdAt: recordedAt,
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

    private func day(
        _ date: Date,
        in snapshot: TaskActivityHeatmapSnapshot,
        calendar: Calendar
    ) -> ActivityHeatmapDay? {
        snapshot.weeks
            .lazy
            .flatMap(\.days)
            .first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
