import Foundation
import Testing
@testable import timetracker

struct AnalyticsLayoutTests {
    private let base = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test
    func laneAllocatorUsesTheLowestAvailableLane() {
        let first = TimelineEntryID.trackedSegment(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = TimelineEntryID.trackedSegment(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let third = TimelineEntryID.trackedSegment(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)

        let assignments = TimelineLaneAllocator.assignments(
            for: [
                TimelineLaneInterval(id: third, start: 11, end: 12),
                TimelineLaneInterval(id: second, start: 5, end: 7),
                TimelineLaneInterval(id: first, start: 0, end: 10),
            ],
            minimumGap: 0
        )

        #expect(assignments == [
            TimelineLaneAssignment(id: first, lane: 0),
            TimelineLaneAssignment(id: second, lane: 1),
            TimelineLaneAssignment(id: third, lane: 0),
        ])
    }

    @Test
    func laneAllocatorHonorsExactMinimumGapPolicy() {
        let first = TimelineEntryID.trackedSegment(UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
        let second = TimelineEntryID.trackedSegment(UUID(uuidString: "00000000-0000-0000-0000-000000000012")!)
        let intervals = [
            TimelineLaneInterval(id: first, start: 0, end: 10),
            TimelineLaneInterval(id: second, start: 11, end: 12),
        ]

        let strict = TimelineLaneAllocator.assignments(
            for: intervals,
            minimumGap: 1
        )
        let inclusive = TimelineLaneAllocator.assignments(
            for: intervals,
            minimumGap: 1,
            allowsReuseAtMinimumGap: true
        )

        #expect(strict.map(\.lane) == [0, 1])
        #expect(inclusive.map(\.lane) == [0, 0])
    }

    @Test
    func layoutClipsToTheDayAndAllocatesOverlaps() throws {
        let day = DateInterval(start: base, duration: 3600)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let outsideID = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!

        let result = TimelineLayoutEngine.layout(
            items: [
                TimelineLayoutItem(id: firstID, startedAt: base.addingTimeInterval(-600), endedAt: base.addingTimeInterval(600)),
                TimelineLayoutItem(id: secondID, startedAt: base.addingTimeInterval(300), endedAt: base.addingTimeInterval(900)),
                TimelineLayoutItem(id: outsideID, startedAt: base.addingTimeInterval(4000), endedAt: base.addingTimeInterval(4200)),
            ],
            dayInterval: day,
            minimumLaneGap: 0
        )

        #expect(result.displayInterval == DateInterval(start: base, end: base.addingTimeInterval(900)))
        #expect(result.entries.map(\.id) == [.trackedSegment(firstID), .trackedSegment(secondID)])
        #expect(result.laneCount == 2)
        let first = try #require(result.entries.first)
        #expect(first.item.startedAt == day.start)
        #expect(first.item.endedAt == base.addingTimeInterval(600))
    }

    @Test
    func axisCompressionReplacesOnlyLongInteriorGaps() throws {
        let display = DateInterval(start: base, duration: 7200)
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: [
                DateInterval(start: base, duration: 600),
                DateInterval(start: base.addingTimeInterval(6600), duration: 600),
            ],
            gapThreshold: 3600,
            gapPlaceholderDuration: 900
        )

        let gap = try #require(compression.omittedGaps.first)
        #expect(compression.omittedGaps.count == 1)
        #expect(gap.duration == 6000)
        #expect(gap.omittedDuration == 5100)
        #expect(compression.compressedDuration == 2100)
        #expect(abs(compression.ratio(for: base.addingTimeInterval(3600)) - 0.5) < 0.000_001)
        #expect(compression.isInsideOmittedGap(base.addingTimeInterval(3600)))
        #expect(!compression.isInsideOmittedGap(gap.start))
    }
}
