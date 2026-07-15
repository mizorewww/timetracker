import Foundation
import Testing
@testable import timetracker

struct AnalyticsGroupBreakdownPresentationTests {
    @Test @MainActor
    func zeroDataKeepsTheBreakdownEmpty() {
        let presentation = AnalyticsGroupBreakdownPresentation.make(
            items: [],
            reportedTotalSeconds: 0,
            otherTitle: "Other",
            otherSubtitle: "Combined smaller groups"
        )

        #expect(presentation.items.isEmpty)
        #expect(presentation.totalSeconds == 0)
    }

    @Test @MainActor
    func presentationAggregatesHiddenGroupsIntoNamedOtherItem() {
        let points = (1...8).map { index in
            AnalyticsGroupBreakdownPoint(
                id: "group-\(index)",
                kind: .rootTask,
                title: "Group \(index)",
                subtitle: "Context \(index)",
                iconName: "folder",
                colorHex: "0A84FF",
                grossSeconds: (9 - index) * 100,
                wallSeconds: (9 - index) * 100
            )
        }

        let presentation = AnalyticsGroupBreakdownPresentation.make(
            items: points,
            reportedTotalSeconds: 3_600,
            otherTitle: "Other",
            otherSubtitle: "Combined smaller groups"
        )

        #expect(presentation.totalSeconds == 3_600)
        #expect(presentation.items.count == 6)
        #expect(presentation.items.prefix(5).map(\.title) == [
            "Group 1", "Group 2", "Group 3", "Group 4", "Group 5"
        ])
        #expect(presentation.items.last?.title == "Other")
        #expect(presentation.items.last?.grossSeconds == 600)
        #expect(presentation.items.reduce(0) { $0 + $1.grossSeconds } == 3_600)
    }

    @Test @MainActor
    func barLayoutBorrowsWidthWithoutOverflowingItsContainer() throws {
        let items = [990, 1, 1, 1, 1, 1].enumerated().map { index, seconds in
            AnalyticsGroupBreakdownDisplayItem(
                id: "group-\(index)",
                title: "Group \(index)",
                subtitle: "",
                iconName: "folder",
                colorHex: "0A84FF",
                grossSeconds: seconds
            )
        }

        let layout = AnalyticsGroupBarLayoutEngine.layout(
            items: items,
            totalSeconds: 995,
            availableWidth: 100
        )

        #expect(layout.count == 6)
        #expect(layout.allSatisfy { $0.width >= 4 })
        let occupiedWidth = layout.reduce(CGFloat.zero) { $0 + $1.width } + 15
        #expect(abs(occupiedWidth - 100) < 0.001)
        #expect(abs(try #require(layout.first).width - 65) < 0.001)
    }
}
