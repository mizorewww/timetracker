import SwiftUI

/// The app's one minute-granular page clock.
///
/// A page keeps `now` in `@State` and derives everything time-dependent from
/// it; this modifier advances `now` at `deadline` while the page's live
/// clocks are active (`pageLiveClocksActive`), and immediately when the page
/// or scene becomes active or the system clock, day, or time zone changes.
/// Second-level text (a running timer's elapsed label) stays a 1 s
/// `TimelineView` scoped to that label.
extension View {
    func liveClock(_ now: Binding<Date>, until deadline: Date?) -> some View {
        modifier(LiveClockModifier(now: now, deadline: deadline))
    }
}

enum LiveClockDeadline {
    /// The next moment a page showing `now` can change: the next minute
    /// boundary while something is live, otherwise the next local day.
    static func next(
        after now: Date,
        isLive: Bool,
        calendar: Calendar = .current
    ) -> Date? {
        if isLive {
            let minute = floor(now.timeIntervalSinceReferenceDate / 60)
            return Date(timeIntervalSinceReferenceDate: (minute + 1) * 60)
        }
        return calendar.dateInterval(of: .day, for: now)?.end
    }
}

private struct LiveClockModifier: ViewModifier {
    @Binding var now: Date
    let deadline: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pageLiveClocksActive) private var pageLiveClocksActive

    private struct Schedule: Hashable {
        let now: Date
        let deadline: Date?
        let isActive: Bool
    }

    func body(content: Content) -> some View {
        let isActive = pageLiveClocksActive && scenePhase == .active
        content
            .task(id: Schedule(now: now, deadline: deadline, isActive: isActive)) {
                guard isActive, let deadline else { return }
                do {
                    try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                } catch {
                    return
                }
                now = Date()
            }
            .onChange(of: isActive) { _, isActive in
                guard isActive else { return }
                now = Date()
            }
            .onSystemClockChange {
                now = Date()
            }
    }
}
