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
        #expect(source.contains("Button(intent: WidgetStopTimerIntent(segmentID: timer.id))"))
        #expect(source.contains("widget.action.stop"))
    }

    @Test
    func stopActionsSerializeTheVisibleSegmentAcrossSystemSurfaces() throws {
        let appIntent = try sourceText("timetracker/AppIntents/TimeTrackerAppIntents.swift")
        let shared = try sourceText("SharedLiveActivity/TimeTrackingActivityAttributes.swift")
        let coordinator = try sourceText("timetracker/App/TimeTrackerLiveActivities.swift")
        let liveTimer = try sourceText("timetrackerLiveActivityExtension/LiveActivityTimerViews.swift")
        let liveExpanded = try sourceText("timetrackerLiveActivityExtension/ExpandedActivityDetails.swift")
        let liveSupport = try sourceText("timetrackerLiveActivityExtension/LiveActivitySupport.swift")

        #expect(appIntent.contains("var timer: ActiveTimerAppEntity"))
        #expect(appIntent.contains("segmentID: targetID"))
        #expect(shared.contains("var segmentID: String"))
        #expect(coordinator.contains("segmentID: primary.id.uuidString"))
        #expect(liveTimer.contains("Button(intent: LiveActivityStopTimerIntent(segmentID: segmentID))"))
        #expect(liveExpanded.contains("Button(intent: LiveActivityStopTimerIntent("))
        #expect(liveSupport.contains("timetracker://timer/stop?segmentID="))
        #expect(liveSupport.contains("var segmentID: String"))
    }

    @Test
    func staleLiveActivityUsesFrozenElapsedPresentation() throws {
        let shared = try sourceText("SharedLiveActivity/TimeTrackingActivityAttributes.swift")
        let coordinator = try sourceText("timetracker/App/TimeTrackerLiveActivities.swift")
        let timer = try sourceText("timetrackerLiveActivityExtension/LiveActivityTimerViews.swift")
        let bundle = try sourceText("timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift")

        #expect(shared.contains("case frozen(seconds: Int)"))
        #expect(shared.contains("static let staleAfter: TimeInterval = 8 * 60 * 60"))
        #expect(coordinator.contains("LiveActivityTimingPolicy.staleDate(for: request.state.startedAt)"))
        #expect(timer.contains("LiveActivityTimingPolicy.elapsedPresentation("))
        #expect(timer.contains("Text(LiveActivityElapsedFormatter.clock(seconds))"))
        #expect(bundle.contains("CompactTimerText("))
        #expect(bundle.contains("isStale: context.isStale"))
        #expect(timer.contains(".accessibilityValue(elapsedAccessibilityValue)"))
    }

    @Test
    func staleWidgetAndWatchSnapshotsFreezeTheirElapsedText() throws {
        let widget = try sourceText("timetracker/Shared/WidgetSnapshotModels.swift")
        let watchSnapshot = try sourceText("timetracker/Shared/WatchStateSnapshotModels.swift")
        let watchRows = try sourceText("timetrackerWatchApp/WatchTimerRows.swift")

        #expect(widget.contains("guard freshness != .current else"))
        #expect(watchSnapshot.contains("enum WatchTimerElapsedPresentation"))
        #expect(watchSnapshot.contains("guard freshness != .current else"))
        #expect(watchRows.contains("timer.elapsedPresentation("))
        #expect(watchRows.contains("Text(WatchElapsedFormatter.clock(seconds))"))
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
            #expect(widget.contains("\"widget.action.stop\""))
            #expect(liveActivity.contains("\"live.timer.staleHint\""))
        }
    }
}
