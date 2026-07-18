import Foundation
import Testing

@testable import timetracker

struct AnalyticsCategoryPresentationTests {
    @Test @MainActor
    func homeAsksSixQuestionsAndCoversEveryDestinationOnce() {
        #expect(AnalyticsCategory.questionCategories == [
            .overview,
            .time,
            .tasks,
            .pomodoro,
            .decisions,
            .quality
        ])
        #expect(AnalyticsCategory.questionCategories.count == AnalyticsCategory.allCases.count)
        #expect(Set(AnalyticsCategory.questionCategories) == Set(AnalyticsCategory.allCases))
    }

    @Test @MainActor
    func everyQuestionUsesTheSameNoRecordedTimeAnswerForAnEmptyRange() {
        let window = AnalyticsComparisonWindow(
            current: DateInterval(start: .distantPast, duration: 1),
            previous: DateInterval(start: .distantPast, duration: 1),
            basis: .matchedProgress
        )
        let snapshot = AnalyticsSnapshot(
            range: .today,
            overview: AnalyticsOverview(
                grossSeconds: 0,
                wallSeconds: 0,
                overlapSeconds: 0,
                pomodoroCount: 0,
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
            taskBreakdown: [],
            rootBreakdown: [],
            categoryBreakdown: [],
            overlaps: []
        )
        let expected = AppStrings.localized("analytics.question.answer.noRecordedTime")

        for category in AnalyticsCategory.questionCategories {
            #expect(category.answerPreview(from: snapshot) == expected)
        }
    }
}
