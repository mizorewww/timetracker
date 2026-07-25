import Foundation
import SwiftUI
import Testing

@Suite(.serialized)
struct SystemSurfaceInteractionContractTests {
    @Test
    func liveActivityStopwatchKeepsAThreeFieldSixteenHourClock() {
        let startedAt = Date(timeIntervalSince1970: 0)
        let currentDate = startedAt.addingTimeInterval(16 * 3600 + 2 * 60 + 3)
        let style = SystemFormatStyle.Stopwatch(
            startingAt: startedAt,
            showsHours: true,
            maxFieldCount: 3,
            maxPrecision: .seconds(1)
        )
        .locale(Locale(identifier: "en_US_POSIX"))

        #expect(String(style.format(currentDate).characters) == "16:02:03")
    }
}
