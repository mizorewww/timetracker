import Foundation
import Testing

@Suite(.serialized)
struct SystemSurfaceInteractionContractTests {
    @Test
    func widgetBackgroundOnlyOpensTodayAndQuickStartRemainsExplicit() throws {
        let source = try sourceText("timetrackerWidgetExtension/ActiveTimerWidgetView.swift")

        #expect(source.contains(".widgetURL(WidgetDeepLinks.today)"))
        #expect(source.contains("private var widgetURL") == false)
        #expect(source.contains("Link(destination: WidgetDeepLinks.startTimer(taskID: task.taskID))"))
        #expect(source.contains("widget.action.startTaskFormat"))
        #expect(source.contains("minHeight: 44"))
    }

    @Test
    func staleLiveActivityUsesFrozenElapsedPresentation() throws {
        let shared = try sourceText("SharedLiveActivity/TimeTrackingActivityAttributes.swift")
        let coordinator = try sourceText("timetracker/App/TimeTrackerLiveActivities.swift")
        let timer = try sourceText("timetrackerLiveActivityExtension/LiveActivityTimerViews.swift")

        #expect(shared.contains("case frozen(seconds: Int)"))
        #expect(shared.contains("static let staleAfter: TimeInterval = 8 * 60 * 60"))
        #expect(coordinator.contains("LiveActivityTimingPolicy.staleDate(for: request.state.startedAt)"))
        #expect(timer.contains("LiveActivityTimingPolicy.elapsedPresentation("))
        #expect(timer.contains("Text(LiveActivityElapsedFormatter.clock(seconds))"))
        #expect(timer.contains(".accessibilityValue(elapsedAccessibilityValue)"))
    }

    @Test
    func liveActivityLayoutsAdaptInsteadOfForcingOneHorizontalLine() throws {
        let lockScreen = try sourceText(
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift"
        )
        let expanded = try sourceText(
            "timetrackerLiveActivityExtension/ExpandedActivityDetails.swift"
        )

        #expect(lockScreen.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(lockScreen.contains("ViewThatFits(in: .horizontal)"))
        #expect(lockScreen.contains("accessibilityContent"))
        #expect(lockScreen.contains("stackedContent"))
        #expect(lockScreen.components(separatedBy: ".lineLimit(2)").count - 1 >= 2)
        #expect(expanded.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(expanded.contains("ViewThatFits(in: .horizontal)"))
        #expect(expanded.contains(".lineLimit(2)"))
    }

    @Test
    func systemSurfaceActionAndStaleCopyExistInEveryExtensionLocale() throws {
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let widget = try sourceText(
                "timetrackerWidgetExtension/\(locale).lproj/Localizable.strings"
            )
            let liveActivity = try sourceText(
                "timetrackerLiveActivityExtension/\(locale).lproj/Localizable.strings"
            )

            #expect(widget.contains("\"widget.action.startTaskFormat\""))
            #expect(liveActivity.contains("\"live.timer.staleHint\""))
        }
    }
}
