import Foundation
import Testing
@testable import timetracker

@MainActor
struct WatchStateProjectionServiceTests {
    @Test
    func wireOrderFollowsUsageAndQuickStartRankFollowsQuickStartOrder() {
        let mostUsed = TaskNode(title: "Most used", parentID: nil, deviceID: "fixture")
        let middle = TaskNode(title: "Middle", parentID: nil, deviceID: "fixture")
        let pinned = TaskNode(title: "Pinned", parentID: nil, deviceID: "fixture")
        let generatedAt = Date(timeIntervalSinceReferenceDate: 0)

        let snapshot = WatchStateProjectionService().snapshot(
            widgetSnapshot: WidgetSnapshot(
                generatedAt: generatedAt,
                todayGrossSeconds: 0,
                todayWallSeconds: 0,
                activeTimers: []
            ),
            rankedTasks: [mostUsed, middle, pinned],
            quickStartTasks: [pinned, mostUsed],
            taskParentPathByID: [:]
        )

        #expect(snapshot.recentTasks.map(\.taskID) == [mostUsed.id, middle.id, pinned.id])
        #expect(snapshot.recentTasks.map(\.quickStartRank) == [1, nil, 0])
    }
}
