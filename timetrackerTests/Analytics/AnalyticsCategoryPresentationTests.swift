import Foundation
import Testing
@testable import timetracker

struct AnalyticsCategoryPresentationTests {
    @Test @MainActor
    func homePrioritizesReviewThenCoversEveryExploreDestinationOnce() {
        #expect(AnalyticsCategory.reviewCategories == [.decisions, .quality])
        #expect(
            AnalyticsCategory.exploreCategories == [
                .time,
                .tasks,
                .pomodoro,
                .overview,
            ]
        )
        let homeCategories =
            AnalyticsCategory.reviewCategories + AnalyticsCategory.exploreCategories
        #expect(homeCategories.count == AnalyticsCategory.allCases.count)
        #expect(Set(homeCategories) == Set(AnalyticsCategory.allCases))
    }

    @Test @MainActor
    func everyQuestionUsesTheSameNoRecordedTimeAnswerForAnEmptyRange() {
        let snapshot = makeSnapshot()
        let expected = AppStrings.localized("analytics.question.answer.noRecordedTime")

        let homeCategories =
            AnalyticsCategory.reviewCategories + AnalyticsCategory.exploreCategories
        for category in homeCategories {
            #expect(category.answerPreview(from: snapshot) == expected)
        }
    }

    @Test @MainActor
    func taskQuestionNamesTheLeadingTaskAndCategoryDestination() {
        let topTask = TaskAnalyticsPoint(
            taskID: UUID(),
            title: "Read Apple HIG",
            path: "Study / Read Apple HIG",
            colorHex: "16A34A",
            iconName: "book.pages",
            grossSeconds: 2400,
            wallSeconds: 2400
        )
        let snapshot = makeSnapshot(
            grossSeconds: 3600,
            taskBreakdown: [topTask]
        )
        let expected = String(
            format: AppStrings.localized(
                "analytics.question.answer.taskCategoryFormat"
            ),
            "Read Apple HIG",
            DurationFormatter.compact(2400)
        )

        #expect(AnalyticsCategory.tasks.answerPreview(from: snapshot) == expected)
    }

    @Test @MainActor
    func completedFocusRoundAtThePeriodBoundaryRemainsVisibleWithoutTrackedDuration() {
        let snapshot = makeSnapshot(grossSeconds: 0, pomodoroCount: 1)
        let expected = String(
            format: AppStrings.localized("analytics.question.answer.focusSingularFormat"),
            1
        )

        #expect(AnalyticsCategory.pomodoro.answerPreview(from: snapshot) == expected)
        #expect(
            AnalyticsCategory.overview.answerPreview(from: snapshot) ==
                AppStrings.localized("analytics.question.answer.noRecordedTime")
        )
    }

    @MainActor
    private func makeSnapshot(
        grossSeconds: Int = 0,
        pomodoroCount: Int = 0,
        taskBreakdown: [TaskAnalyticsPoint] = []
    ) -> AnalyticsSnapshot {
        let window = AnalyticsComparisonWindow(
            current: DateInterval(start: .distantPast, duration: 1),
            previous: DateInterval(start: .distantPast, duration: 1),
            basis: .matchedProgress
        )
        return AnalyticsSnapshot(
            range: .today,
            overview: AnalyticsOverview(
                grossSeconds: grossSeconds,
                wallSeconds: 0,
                overlapSeconds: 0,
                pomodoroCount: pomodoroCount,
                averageFocusSeconds: 0
            ),
            comparison: AnalyticsComparison(
                window: window,
                currentGrossSeconds: 0,
                previousGrossSeconds: 0,
                currentWallSeconds: 0,
                previousWallSeconds: 0
            ),
            rhythm: AnalyticsRhythm(
                activeDayCount: 0,
                dailyAverageGrossSeconds: 0,
                peakHour: nil,
                peakHourSeconds: 0,
                longestContinuousSeconds: 0,
                averageSegmentSeconds: 0,
                medianSegmentSeconds: 0,
                segmentCount: 0
            ),
            quality: AnalyticsQuality(
                overlapRatio: 0,
                switchCount: 0,
                shortSegmentCount: 0,
                shortSegmentRatio: 0,
                averageSegmentSeconds: 0,
                longestContinuousSeconds: 0
            ),
            insights: [],
            daily: [],
            todayActivity: [],
            timeline: .empty,
            completedFocusRoundSegmentIDs: [],
            taskBreakdown: taskBreakdown,
            rootBreakdown: [],
            categoryBreakdown: [],
            overlaps: []
        )
    }
}
