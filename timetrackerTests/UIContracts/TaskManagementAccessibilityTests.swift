import Foundation
import Testing
@testable import timetracker

struct TaskManagementAccessibilityTests {
    @Test
    func snapshotPreservesExtendedMetadataWhenTheVisualRowIsCondensed() {
        let task = TaskNode(title: "Release audit", parentID: nil, deviceID: "test")
        let path = "Work / Release audit"
        let progress = ChecklistProgress(taskID: task.id, totalCount: 3, completedCount: 1)
        let rollup = TaskRollup(
            taskID: task.id,
            workedSeconds: 3_600,
            estimatedTotalSeconds: 10_800,
            remainingSeconds: 7_200,
            projectedDays: 2,
            historicalDailyAverageSeconds: 1_800,
            historicalActiveDayCount: 2,
            checklistProgress: progress,
            confidence: .medium,
            reason: "test",
            forecastState: .ready,
            forecastSourceTaskCount: 1,
            forecastSourceTaskIDs: [task.id],
            forecastSourceLabel: nil
        )
        let presentation = TaskManagementRowPresentation(
            identity: identity(
                for: task,
                parentPath: "Work",
                fullPath: path
            ),
            identityContext: .hierarchical,
            progress: progress,
            rollup: rollup,
            workedSeconds: 3_600,
            childCount: 2,
            isRunning: true
        )

        let snapshot = TaskManagementRowAccessibilitySnapshot(
            task: task,
            presentation: presentation
        )

        #expect(snapshot.label == task.title)
        #expect(snapshot.valueComponents == [
            path,
            AppStrings.running,
            String(
                format: AppStrings.localized("tasks.workedFormat"),
                DurationFormatter.compact(3_600)
            ),
            String(format: AppStrings.localized("checklist.progressFormat"), 1, 3),
            String(
                format: AppStrings.localized("forecast.remainingFormat"),
                DurationFormatter.compact(7_200)
            ),
            rollup.projectedDaysDisplayText,
            String(format: AppStrings.localized("tasks.childCount"), 2)
        ])
    }

    @Test
    func snapshotAvoidsDuplicatePathAndOmitsWorkflowStatus() {
        let task = TaskNode(title: "Ordinary task", parentID: nil, deviceID: "test")
        let presentation = TaskManagementRowPresentation(
            identity: identity(
                for: task,
                parentPath: nil,
                fullPath: task.title
            ),
            identityContext: .hierarchical,
            progress: ChecklistProgress(taskID: task.id, totalCount: 0, completedCount: 0),
            rollup: nil,
            workedSeconds: 0,
            childCount: 0,
            isRunning: false
        )

        let snapshot = TaskManagementRowAccessibilitySnapshot(
            task: task,
            presentation: presentation
        )

        #expect(snapshot.valueComponents == [
            String(
                format: AppStrings.localized("tasks.workedFormat"),
                DurationFormatter.compact(0)
            )
        ])
    }

    @Test
    func snapshotDistinguishesRecurringQuantityRows() {
        let task = TaskNode(
            title: "Daily Push-ups",
            parentID: nil,
            deviceID: "test"
        )
        let quantity = TaskQuantityProgressSnapshot(
            taskID: task.id,
            goalBaseline: TaskQuantityGoalMutationBaseline(
                goalID: TaskProgressIdentity.quantityGoalID(
                    taskID: task.id
                ),
                taskID: task.id,
                clientMutationID: UUID()
            ),
            targetAmount: 50,
            unitLabel: "reps",
            totalAmount: 20,
            entryCount: 1,
            entryRevision: UUID(),
            isRecordingAllowed: true
        )
        let presentation = TaskManagementRowPresentation(
            identity: identity(
                for: task,
                parentPath: "Fitness",
                fullPath: "Fitness / Daily Push-ups"
            ),
            identityContext: .hierarchical,
            progress: ChecklistProgress(
                taskID: task.id,
                totalCount: 0,
                completedCount: 0
            ),
            rollup: nil,
            workedSeconds: 0,
            childCount: 0,
            isRunning: false,
            recurrenceRole: .generated(nil),
            quantityProgress: quantity
        )

        let snapshot = TaskManagementRowAccessibilitySnapshot(
            task: task,
            presentation: presentation
        )

        #expect(
            Array(snapshot.valueComponents.prefix(3)) == [
                "Fitness / Daily Push-ups",
                AppStrings.localized("task.recurrence.row.generated"),
                String.localizedStringWithFormat(
                    AppStrings.localized(
                        "task.quantity.row.progressFormat"
                    ),
                    Int64(20),
                    Int64(50),
                    "reps"
                )
            ]
        )
    }

    @Test
    func generatedRoleDistinguishesTodayFromHistoricalOccurrences()
        throws {
        let timeZone = try #require(
            TimeZone(identifier: "Asia/Singapore")
        )
        let today = try #require(
            TaskRecurrenceDayKey.date(
                from: "2026-07-21",
                timeZone: timeZone
            )
        )
        let historicalDate = try #require(
            TaskRecurrenceDayKey.date(
                from: "2026-07-20",
                timeZone: timeZone
            )
        )
        let occurrence = TaskRecurrenceOccurrenceSnapshot(
            id: UUID(),
            templateTaskID: UUID(),
            dayKey: "2026-07-20",
            timeZoneIdentifier: timeZone.identifier,
            localDate: historicalDate
        )
        let role = TaskManagementRecurrenceRole.generated(occurrence)

        #expect(
            role.title(relativeTo: historicalDate) ==
                AppStrings.localized("task.recurrence.row.today")
        )
        #expect(
            role.title(relativeTo: today) ==
                String.localizedStringWithFormat(
                    AppStrings.localized(
                        "task.recurrence.row.generatedDateFormat"
                    ),
                    occurrence.formattedDateText()
                )
        )
    }

    @Test
    @MainActor
    func recurrenceRoleIndexPreservesIncompleteParticipants() {
        let templateTaskID = UUID()
        let generatedTaskID = UUID()

        let index = TaskManagementRecurrenceRole.index(
            rules: [],
            occurrences: [],
            incompleteTemplateTaskIDs: [templateTaskID],
            incompleteGeneratedTaskIDs: [templateTaskID, generatedTaskID]
        )

        #expect(index[templateTaskID] == .template)
        #expect(
            index[generatedTaskID] ==
                TaskManagementRecurrenceRole.generated(nil)
        )
    }

    private func identity(
        for task: TaskNode,
        parentPath: String?,
        fullPath: String
    ) -> TaskIdentityPresentation {
        TaskIdentityPresentation(
            id: task.id,
            title: task.title,
            parentPath: parentPath,
            fullPath: fullPath,
            visual: TaskVisualPresentation(
                iconName: task.iconName,
                colorHex: task.colorHex
            ),
            breadcrumb: .root(title: task.title)
        )
    }
}
