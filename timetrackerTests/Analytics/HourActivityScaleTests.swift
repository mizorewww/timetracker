import Foundation
import Testing
@testable import timetracker

struct HourActivityScaleTests {
    @Test
    func sharedScaleUsesOneHourAsItsMinimumUpperBound() {
        let scale = HourActivityScale(hourTotals: [0, 30, 1_800, 3_599])

        #expect(scale.upperBoundSeconds == 3_600)
        #expect(scale.height(totalSeconds: 0, availableHeight: 150) == 0)
        #expect(scale.height(totalSeconds: 1_800, availableHeight: 150) == 75)
        #expect(scale.height(totalSeconds: 3_600, availableHeight: 150) == 150)
    }

    @Test
    func sharedScaleExpandsToTheLargestConcurrentGrossHour() {
        let scale = HourActivityScale(hourTotals: [900, 5_400, 7_200, 3_600])

        #expect(scale.upperBoundSeconds == 7_200)
        #expect(scale.height(totalSeconds: 3_600, availableHeight: 150) == 75)
        #expect(scale.height(totalSeconds: 5_400, availableHeight: 150) == 112.5)
        #expect(scale.height(totalSeconds: 7_200, availableHeight: 150) == 150)
    }

    @Test
    func subminuteTotalsRetainFractionalBarHeight() {
        let scale = HourActivityScale(hourTotals: [30])

        #expect(scale.height(totalSeconds: 30, availableHeight: 150) == 1.25)
    }

    @Test
    func scaleRejectsEmptyAndInvalidGeometry() {
        let scale = HourActivityScale(hourTotals: [])

        #expect(scale.height(totalSeconds: -1, availableHeight: 150) == 0)
        #expect(scale.height(totalSeconds: 30, availableHeight: 0) == 0)
        #expect(scale.height(totalSeconds: 30, availableHeight: -.infinity) == 0)
        #expect(scale.height(totalSeconds: 30, availableHeight: .nan) == 0)
    }

    @Test
    func stackLayoutRejectsNonfiniteGeometryWithoutTrapping() {
        let input = HourStackLayoutInput(id: UUID(), seconds: 30)

        #expect(
            HourStackLayoutEngine.layout(
                inputs: [input],
                availableHeight: .infinity,
                minSliceHeight: 0
            ).isEmpty
        )
        #expect(
            HourStackLayoutEngine.layout(
                inputs: [input],
                availableHeight: 150,
                minSliceHeight: .nan
            ).isEmpty
        )
        #expect(
            HourStackLayoutEngine.maxVisibleSliceCount(
                availableHeight: .infinity,
                minSliceHeight: 1
            ) == 0
        )
    }

    @Test
    func taskSliceHeightsConserveTheScaledHourTarget() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let tinyID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let scale = HourActivityScale(hourTotals: [900, 5_400])
        let targetHeight = scale.height(totalSeconds: 900, availableHeight: 150)

        let layout = HourStackLayoutEngine.layout(
            inputs: [
                HourStackLayoutInput(id: firstID, seconds: 600),
                HourStackLayoutInput(id: secondID, seconds: 299),
                HourStackLayoutInput(id: tinyID, seconds: 1)
            ],
            availableHeight: targetHeight,
            minSliceHeight: 0
        )

        #expect(layout.map(\.id) == [firstID, secondID, tinyID])
        #expect(layout[0].height > layout[1].height)
        #expect(layout[2].height > 0)
        #expect(abs(layout.reduce(0) { $0 + $1.height } - targetHeight) < 0.000_000_1)
    }
}
