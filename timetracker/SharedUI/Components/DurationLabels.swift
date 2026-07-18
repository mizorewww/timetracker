import SwiftUI

struct TrackedTimeDisplaySnapshot: Equatable {
    let start: Date
    let end: Date
    let elapsedSeconds: Int
    let usesCurrentEndLabel: Bool

    init(startedAt: Date, endedAt: Date?, now: Date) {
        let interval = TrackedTimePolicy.interval(
            startedAt: startedAt,
            endedAt: endedAt,
            now: now
        )
        let boundedEnd = TrackedTimePolicy.boundedEnd(endedAt: endedAt, now: now)
        let zeroDurationAnchor = min(startedAt, now)

        start = interval?.start ?? zeroDurationAnchor
        end = interval?.end ?? zeroDurationAnchor
        elapsedSeconds = TrackedTimePolicy.elapsedSeconds(
            startedAt: startedAt,
            endedAt: endedAt,
            now: now
        )
        usesCurrentEndLabel = boundedEnd == now && (endedAt.map { $0 > now } ?? true)
    }
}

struct DurationLabel: View {
    let startedAt: Date
    let endedAt: Date?

    @ViewBuilder
    var body: some View {
        let now = Date()
        if endedAt.map({ $0 <= now }) == true {
            durationText(at: now)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                durationText(at: context.date)
            }
        }
    }

    private func durationText(at now: Date) -> some View {
        let display = TrackedTimeDisplaySnapshot(
            startedAt: startedAt,
            endedAt: endedAt,
            now: now
        )
        return AnimatedClockText(
            text: DurationFormatter.clock(display.elapsedSeconds),
            value: display.elapsedSeconds
        )
    }
}
