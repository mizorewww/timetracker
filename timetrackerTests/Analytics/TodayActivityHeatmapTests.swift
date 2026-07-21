import Foundation
import SwiftData
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
        let snapshots = service.taskSnapshots(
            selectedTaskIDs: [
                root.id,
                child.id,
                root.id,
                deleted.id,
                orphanID,
            ],
            tasks: tasks,
            segments: [],
            checklistItems: items,
            quantityGoals: [],
            quantityEntries: [],
            now: now,
            calendar: calendar
        )
        let snapshot = try #require(snapshots.first)

        #expect(
            service.contributingTaskIDs(
                selectedTaskIDs: [root.id, child.id],
                tasks: tasks
            ) == Set([root.id, child.id, grandchild.id])
        )
        #expect(snapshots.map(\.taskID) == [root.id, child.id])
        #expect(snapshot.totalValue == 4)
        #expect(snapshot.activeDayCount == 2)
        #expect(day(today, in: snapshot, calendar: calendar)?.value == 3)
        #expect(day(today, in: snapshot, calendar: calendar)?.intensity == .maximum)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.value == 1)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.intensity == .medium)
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

        var snapshot = try #require(service.taskSnapshots(
            selectedTaskIDs: [root.id],
            tasks: [root],
            segments: [],
            checklistItems: [item],
            quantityGoals: [],
            quantityEntries: [],
            now: now,
            calendar: calendar
        ).first)
        #expect(day(today, in: snapshot, calendar: calendar)?.value == 1)

        item.isCompleted = false
        item.completedAt = nil
        snapshot = try #require(service.taskSnapshots(
            selectedTaskIDs: [root.id],
            tasks: [root],
            segments: [],
            checklistItems: [item],
            quantityGoals: [],
            quantityEntries: [],
            now: now,
            calendar: calendar
        ).first)
        #expect(snapshot.totalValue == 0)

        item.isCompleted = true
        item.completedAt = yesterday.addingTimeInterval(60)
        snapshot = try #require(service.taskSnapshots(
            selectedTaskIDs: [root.id],
            tasks: [root],
            segments: [],
            checklistItems: [item],
            quantityGoals: [],
            quantityEntries: [],
            now: now,
            calendar: calendar
        ).first)
        #expect(day(today, in: snapshot, calendar: calendar)?.value == 0)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.value == 1)
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
        let snapshot = try #require(
            TodayActivityHeatmapSnapshotService().taskSnapshots(
            selectedTaskIDs: [root.id, UUID()],
            tasks: [root],
            segments: [],
            checklistItems: [],
            quantityGoals: [],
            quantityEntries: [],
            now: now,
            calendar: calendar
            ).first
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
        #expect(snapshot.totalValue == 0)
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
    func quantityAggregatesMatchingUnitSubtasksAgainstDeclaredGoals() throws {
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
        let tomorrow = try #require(
            calendar.date(byAdding: .day, value: 1, to: today)
        )
        let quantityTask = task("Push-ups", colorHex: "16A34A")
        let matchingChild = task(
            "Morning set",
            parentID: quantityTask.id
        )
        let differentUnitChild = task(
            "Workout sets",
            parentID: quantityTask.id
        )
        let deletedChild = task(
            "Deleted set",
            parentID: quantityTask.id
        )
        deletedChild.deletedAt = now.addingTimeInterval(-60)
        let rootGoal = quantityGoal(
            taskID: quantityTask.id,
            targetAmount: 100,
            unitLabel: "reps"
        )
        let matchingChildGoal = quantityGoal(
            taskID: matchingChild.id,
            targetAmount: 50,
            unitLabel: " RePs "
        )
        let differentUnitGoal = quantityGoal(
            taskID: differentUnitChild.id,
            targetAmount: 10,
            unitLabel: "sets"
        )
        let deletedChildGoal = quantityGoal(
            taskID: deletedChild.id,
            targetAmount: 100,
            unitLabel: "reps"
        )
        let service = TodayActivityHeatmapSnapshotService()
        let tasks = [
            quantityTask,
            matchingChild,
            differentUnitChild,
            deletedChild,
        ]
        let snapshots = service.taskSnapshots(
            selectedTaskIDs: [quantityTask.id],
            tasks: tasks,
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
            quantityGoals: [
                rootGoal,
                matchingChildGoal,
                differentUnitGoal,
                deletedChildGoal,
            ],
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
                    taskID: matchingChild.id,
                    amount: 10,
                    recordedAt: yesterday.addingTimeInterval(120)
                ),
                quantityEntry(
                    taskID: matchingChild.id,
                    amount: 30,
                    recordedAt: today.addingTimeInterval(120)
                ),
                quantityEntry(
                    taskID: differentUnitChild.id,
                    amount: 9,
                    recordedAt: today.addingTimeInterval(180)
                ),
                quantityEntry(
                    taskID: deletedChild.id,
                    amount: 100,
                    recordedAt: today.addingTimeInterval(240)
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

        #expect(
            service.contributingTaskIDs(
                selectedTaskIDs: [quantityTask.id],
                tasks: tasks
            ) == Set([
                quantityTask.id,
                matchingChild.id,
                differentUnitChild.id,
            ])
        )
        #expect(snapshot.metric == .quantity(unitLabel: "reps"))
        #expect(snapshot.totalValue == 125)
        #expect(snapshot.maximumDailyValue == 90)
        #expect(snapshot.activeDayCount == 2)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.value == 35)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.referenceValue == 150)
        #expect(day(yesterday, in: snapshot, calendar: calendar)?.intensity == .low)
        #expect(day(today, in: snapshot, calendar: calendar)?.value == 90)
        #expect(day(today, in: snapshot, calendar: calendar)?.referenceValue == 150)
        #expect(day(today, in: snapshot, calendar: calendar)?.intensity == .high)
        #expect(day(tomorrow, in: snapshot, calendar: calendar)?.value == 0)
        #expect(
            day(tomorrow, in: snapshot, calendar: calendar)?.intensity
                == ActivityHeatmapIntensity.none
        )
    }

    @Test @MainActor
    func heatmapSelectionPersistsAcrossContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "TodayHeatmapPersistenceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "heatmap.store")
        let selectedTaskIDs = [UUID(), UUID()]

        try writeHeatmapSelection(selectedTaskIDs, to: storeURL)

        let reopenedContainer = try heatmapPersistenceContainer(at: storeURL)
        let reopenedContext = ModelContext(reopenedContainer)
        let stored = try reopenedContext.fetch(
            FetchDescriptor<SyncedPreference>()
        )
        let preferences = AppPreferences(syncedPreferences: stored)

        #expect(preferences.todayHeatmapTaskIDs == selectedTaskIDs)
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
        in snapshot: TaskActivityHeatmapSnapshot,
        calendar: Calendar
    ) -> ActivityHeatmapDay? {
        snapshot.weeks
            .lazy
            .flatMap(\.days)
            .first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    @MainActor
    private func writeHeatmapSelection(
        _ taskIDs: [UUID],
        to storeURL: URL
    ) throws {
        let container = try heatmapPersistenceContainer(at: storeURL)
        try StoreScopedPreferenceCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness
        ).set(
            key: .todayHeatmapTaskIDs,
            valueJSON: PreferenceJSON.encode(taskIDs.map(\.uuidString))
        )
    }

    @MainActor
    private func heatmapPersistenceContainer(
        at storeURL: URL
    ) throws -> ModelContainer {
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "TodayHeatmapPersistenceTests",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
