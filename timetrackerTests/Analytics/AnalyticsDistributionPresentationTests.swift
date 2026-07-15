import Foundation
import Testing
@testable import timetracker

struct AnalyticsDistributionPresentationTests {
    @Test @MainActor
    func distributionAggregatesHiddenAndUnattributedTimeIntoOther() {
        let tasks = (0..<5).map { index in
            TaskAnalyticsPoint(
                taskID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                title: "Task \(index + 1)",
                path: "Project \(index + 1)",
                colorHex: nil,
                iconName: nil,
                status: .active,
                grossSeconds: (5 - index) * 100,
                wallSeconds: (5 - index) * 100
            )
        }

        let presentation = TaskDistributionPresentation.make(
            tasks: tasks,
            reportedTotalSeconds: 1_650,
            maximumSliceCount: 4,
            otherTitle: "Other"
        )

        #expect(presentation.totalSeconds == 1_650)
        #expect(presentation.slices.count == 4)
        #expect(presentation.slices.prefix(3).map(\.title) == ["Task 1", "Task 2", "Task 3"])
        #expect(presentation.slices[0].subtitle == "Project 1")
        #expect(presentation.slices.last?.title == "Other")
        #expect(presentation.slices.last?.grossSeconds == 450)
        #expect(presentation.slices.reduce(0) { $0 + $1.grossSeconds } == 1_650)
    }

    @Test @MainActor
    func distributionAddsUnattributedSliceWithoutDroppingVisibleTasks() {
        let task = TaskAnalyticsPoint(
            taskID: UUID(),
            title: "Tracked",
            path: "Work",
            colorHex: nil,
            iconName: nil,
            status: .active,
            grossSeconds: 600,
            wallSeconds: 600
        )

        let presentation = TaskDistributionPresentation.make(
            tasks: [task],
            reportedTotalSeconds: 900,
            otherTitle: "Other"
        )

        #expect(presentation.slices.map(\.grossSeconds) == [600, 300])
        #expect(presentation.slices.map(\.title) == ["Tracked", "Other"])
    }
}
