import Foundation
import Testing
@testable import timetracker

struct TaskManagementAccessibilityTests {
    @Test
    func snapshotPreservesEveryVisibleTaskMetadataField() {
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
            path: path,
            progress: progress,
            rollup: rollup,
            workedSeconds: 3_600,
            childCount: 2,
            isAvailableForTracking: true,
            isRunning: true
        )

        let snapshot = TaskManagementRowAccessibilitySnapshot(
            task: task,
            presentation: presentation
        )

        #expect(snapshot.label == task.title)
        #expect(snapshot.valueComponents == [
            task.status.displayName,
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
    func snapshotReplacesActiveWithBlockedAndAvoidsDuplicatePath() {
        let task = TaskNode(title: "Blocked task", parentID: nil, deviceID: "test")
        let presentation = TaskManagementRowPresentation(
            path: task.title,
            progress: ChecklistProgress(taskID: task.id, totalCount: 0, completedCount: 0),
            rollup: nil,
            workedSeconds: 0,
            childCount: 0,
            isAvailableForTracking: false,
            isRunning: false
        )

        let snapshot = TaskManagementRowAccessibilitySnapshot(
            task: task,
            presentation: presentation
        )

        #expect(snapshot.valueComponents == [
            AppStrings.localized("task.status.blockedByCompletion"),
            String(
                format: AppStrings.localized("tasks.workedFormat"),
                DurationFormatter.compact(0)
            )
        ])
    }
}
