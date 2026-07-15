import Testing

@testable import timetracker

struct AnalyticsCategoryPresentationTests {
    @Test @MainActor
    func homePrioritizesReviewThenCoversEveryExploreDestinationOnce() {
        #expect(AnalyticsCategory.reviewCategories == [.decisions, .quality])
        #expect(AnalyticsCategory.exploreCategories == [.time, .tasks, .pomodoro, .overview])

        let presentedCategories = AnalyticsCategory.reviewCategories + AnalyticsCategory.exploreCategories
        #expect(presentedCategories.count == AnalyticsCategory.allCases.count)
        #expect(Set(presentedCategories) == Set(AnalyticsCategory.allCases))
    }
}
