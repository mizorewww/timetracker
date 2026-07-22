import Foundation
import SwiftUI
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
        #expect(source.contains("arrow.up.forward.app"))
        #expect(source.contains("widget.action.openToStop"))
    }

    @Test
    func stopActionsSerializeTheVisibleSegmentAcrossShortcutAndWidget() throws {
        let appIntent = try sourceText("timetracker/AppIntents/TimeTrackerAppIntents.swift")
        let widget = try sourceText("timetrackerWidgetExtension/ActiveTimerWidgetView.swift")
        let widgetSupport = try sourceText("timetrackerWidgetExtension/WidgetSupport.swift")

        #expect(appIntent.contains("var timer: ActiveTimerAppEntity"))
        #expect(appIntent.contains("segmentID: targetID"))
        #expect(widget.contains("Button(intent: WidgetStopTimerIntent(segmentID: timer.id))"))
        #expect(widgetSupport.contains("timetracker://timer/stop?segmentID="))
        #expect(widgetSupport.contains("var segmentID: String"))
        #expect(widgetSupport.contains("Open Time Tracker to Stop"))
        #expect(widgetSupport.contains("Open Time Tracker to stop this specific running timer."))
    }

    @Test
    func liveActivityUsesAnUnboundedStopwatchWithoutAStaleDeadline() throws {
        let shared = try sourceText("SharedLiveActivity/TimeTrackingActivityAttributes.swift")
        let coordinator = try sourceText("timetracker/App/TimeTrackerLiveActivities.swift")
        let timer = try liveActivityTimerSources()
        let bundle = try sourceText("timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift")

        #expect(!shared.contains("LiveActivityElapsedPresentation"))
        #expect(!shared.contains("staleAfter"))
        #expect(coordinator.contains("staleDate: nil"))
        #expect(!coordinator.contains("LiveActivityTimingPolicy.staleDate"))
        #expect(timer.contains("format: .stopwatch("))
        #expect(timer.contains("startingAt: startedAt"))
        #expect(timer.contains("maxPrecision: .seconds(1)"))
        #expect(!timer.contains("timerInterval:"))
        #expect(!timer.contains("LiveActivityElapsedFormatter.clock(seconds)"))
        #expect(bundle.contains("CompactTimerText("))
        #expect(bundle.contains("context.isStale ? \"live.timer.stale\" : \"live.timer.elapsed\""))
        #expect(bundle.contains("context.isStale ? String(localized: \"live.timer.staleHint\") : \"\""))
        #expect(timer.contains(".accessibilityValue(stopwatchText)"))
    }

    @Test
    func liveActivityStopwatchKeepsAThreeFieldSixteenHourClock() {
        let startedAt = Date(timeIntervalSince1970: 0)
        let currentDate = startedAt.addingTimeInterval(16 * 3_600 + 2 * 60 + 3)
        let style = SystemFormatStyle.Stopwatch(
            startingAt: startedAt,
            showsHours: true,
            maxFieldCount: 3,
            maxPrecision: .seconds(1)
        )
        .locale(Locale(identifier: "en_US_POSIX"))

        #expect(String(style.format(currentDate).characters) == "16:02:03")
    }

    @Test
    func liveActivityProjectionUsesCanonicalBoundedTaskIdentity() throws {
        let shared = try sourceText("SharedLiveActivity/TimeTrackingActivityAttributes.swift")
        let coordinator = try sourceText("timetracker/App/TimeTrackerLiveActivities.swift")
        let projection = try sourceText("timetracker/App/LiveActivityProjection.swift")
        let timer = try sourceText(
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift"
        )

        #expect(shared.contains("var segmentID: String"))
        #expect(shared.contains("var taskPathAbbreviated: String?"))
        #expect(shared.contains("boundedUTF8Prefix("))
        #expect(coordinator.contains("segmentID: primary.id.uuidString"))
        #expect(coordinator.contains("projectionService.taskProjection("))
        #expect(coordinator.contains("additionalTimerCount: 0"))
        #expect(projection.contains("TaskTreeService().indexes(tasks: tasks)"))
        #expect(projection.contains(".taskIdentityPresentation(for:"))
        #expect(projection.contains("presentation.breadcrumb.readable"))
        #expect(projection.contains("presentation.breadcrumb.abbreviated"))
        #expect(projection.contains("$0.id.uuidString < $1.id.uuidString"))
        #expect(timer.contains("ViewThatFits(in: .horizontal)"))
        #expect(timer.contains("Text(abbreviatedPath(for: state))"))
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
    func liveActivityReusesOneGlanceableTimerRowWithoutMutationControls() throws {
        let lockScreen = try sourceText(
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift"
        )
        let expanded = try sourceText(
            "timetrackerLiveActivityExtension/ExpandedActivityDetails.swift"
        )
        let bundle = try sourceText(
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift"
        )
        let timer = try sourceText(
            "timetrackerLiveActivityExtension/LiveActivityTimerPresentationViews.swift"
        )
        let support = try sourceText(
            "timetrackerLiveActivityExtension/LiveActivitySupport.swift"
        )
        let systemTest = try sourceText(
            "timetrackerUITests/LiveActivitySystemSurfaceUITests.swift"
        )

        #expect(lockScreen.contains("struct LiveActivityTimerRow: View"))
        #expect(lockScreen.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(lockScreen.contains("ViewThatFits(in: .horizontal)"))
        #expect(lockScreen.contains("case .dynamicIsland:\n                    horizontalContent"))
        #expect(lockScreen.contains("horizontalContent"))
        #expect(lockScreen.contains("stackedContent"))
        #expect(lockScreen.contains("case dynamicIsland"))
        #expect(lockScreen.contains("self == .lockScreen"))
        #expect(lockScreen.contains(".lineLimit(allowsWrapping ? 2 : 1)"))
        #expect(lockScreen.contains("Spacer(minLength: 6)") == false)
        #expect(lockScreen.contains(".layoutPriority(style.summaryLayoutPriority)"))
        #expect(lockScreen.contains(".layoutPriority(style.timerLayoutPriority)"))
        #expect(lockScreen.contains("var summaryLayoutPriority: Double"))
        #expect(lockScreen.contains("var timerLayoutPriority: Double"))
        let summaryPrioritySource = lockScreen
            .components(separatedBy: "var summaryLayoutPriority: Double")
            .last?
            .components(separatedBy: "var timerLayoutPriority: Double")
            .first ?? ""
        #expect(summaryPrioritySource.contains(
            "case .lockScreen:\n            1\n        case .dynamicIsland:\n            2\n"
        ))
        let timerPrioritySource = lockScreen
            .components(separatedBy: "var timerLayoutPriority: Double")
            .last?
            .components(separatedBy: "struct LiveActivityTimerRow: View")
            .first ?? ""
        #expect(timerPrioritySource.contains(
            "case .lockScreen:\n            2\n        case .dynamicIsland:\n            1\n"
        ))
        let summarySource = lockScreen
            .components(separatedBy: "struct ActivityTaskSummary: View")
            .last?
            .components(separatedBy: "struct ActivityIconView: View")
            .first ?? ""
        #expect(summarySource.contains(".frame(maxWidth: .infinity") == false)
        #expect(summarySource.contains(".layoutPriority(") == false)
        #expect(lockScreen.contains("liveActivity.lockScreen.title"))
        #expect(lockScreen.contains("liveActivity.expanded.title"))
        #expect(expanded.contains("LiveActivityTimerRow("))
        #expect(expanded.contains("style: .dynamicIsland"))
        #expect(expanded.contains("ActivityTaskSummary(") == false)
        #expect(bundle.contains(".widgetURL(LiveActivityDeepLinks.today)"))
        #expect(bundle.contains("DynamicIslandExpandedRegion(.bottom)"))
        #expect(bundle.contains("DynamicIslandExpandedRegion(.leading)") == false)
        #expect(bundle.contains("DynamicIslandExpandedRegion(.trailing)") == false)
        #expect(bundle.contains("Text(context.state.taskTitle)"))
        #expect(bundle.components(separatedBy: "CompactTimerText(").count - 1 == 2)
        #expect(bundle.contains(".minimumScaleFactor(") == false)
        #expect(bundle.contains(".frame(maxWidth: 62") == false)
        #expect(bundle.contains(".frame(maxWidth: 50") == false)
        #expect(bundle.contains(".frame(maxWidth: 45") == false)
        #expect(bundle.contains(".fontWidth(.condensed)"))
        #expect(bundle.contains(".fontWidth(.compressed)"))
        #expect(bundle.contains(".accessibilityValue(timer.fullStopwatchText)"))
        #expect(bundle.contains(".accessibilityHidden(true)"))
        #expect(timer.components(separatedBy: "maxFieldCount: 3").count - 1 == 2)
        #expect(timer.contains("visibleFieldCount") == false)
        #expect(timer.contains("idealWidth:") == false)
        #expect(timer.contains("maxWidth: style == .lockScreen") == false)
        #expect(timer.contains(".minimumScaleFactor(") == false)
        #expect(timer.contains(".fixedSize(horizontal: true") == false)
        #expect(systemTest.contains("#if os(iOS) && targetEnvironment(simulator)"))
        #expect(systemTest.contains("physicalDeviceModelIdentifier") == false)
        #expect(systemTest.contains("liveActivity.compact.leading"))
        #expect(systemTest.contains("liveActivity.compact.timer"))
        #expect(systemTest.contains("liveActivity.lockScreen.timer"))
        #expect(systemTest.contains("liveActivity.expanded.timer"))
        #expect(systemTest.contains("import Vision"))
        #expect(systemTest.contains("assertScreenshotContainsLongElapsedClock"))
        #expect(systemTest.contains("request.regionOfInterest = normalizedRegionOfInterest"))
        #expect(systemTest.contains("allow.isHittable") == false)
        #expect(lockScreen.contains("Button(intent:") == false)
        #expect(expanded.contains("Button(intent:") == false)
        #expect(support.contains("timetracker://timer/stop") == false)
        #expect(support.contains("LiveActivityStopTimerIntent") == false)
    }

    @Test
    func systemSurfaceCopyExistsInEveryExtensionLocale() throws {
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let widget = try sourceText(
                "timetrackerWidgetExtension/\(locale).lproj/Localizable.strings"
            )
            let liveActivity = try sourceText(
                "timetrackerLiveActivityExtension/\(locale).lproj/Localizable.strings"
            )

            #expect(widget.contains("\"widget.action.startTaskFormat\""))
            #expect(widget.contains("\"widget.action.openToStop\""))
            #expect(liveActivity.contains("\"live.timer.staleHint\""))
            #expect(liveActivity.contains("\"live.timer.openToStop\"") == false)
            #expect(liveActivity.contains("\"live.timer.additionalFormat\"") == false)
        }
    }

    @Test
    func liveActivitySettingsExposeARealRegistrationGateAndRecoveryActions() throws {
        let section = try sourceText(
            "timetracker/Features/Settings/LiveActivitySettingsSection.swift"
        )
        let settings = try sourceText(
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        )
        let systemTest = try sourceText(
            "timetrackerUITests/LiveActivitySystemSurfaceUITests.swift"
        )

        #expect(settings.contains("LiveActivitySettingsSection(store: store)"))
        #expect(section.contains("SettingsStatusRow(presentation: statusPresentation)"))
        #expect(section.contains("case .active:"))
        #expect(section.contains("case .unavailable(let failure):"))
        #expect(section.contains("UIApplication.openSettingsURLString"))
        #expect(section.contains("coordinator.retryLatestDesiredState()"))
        #expect(section.contains("store.syncLiveActivitiesIfAvailable()"))
        #expect(section.contains("settings.liveActivity.status."))
        #expect(systemTest.contains("settings.liveActivity.status.active"))

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let strings = try sourceText(
                "timetracker/\(locale).lproj/Localizable.strings"
            )
            #expect(strings.contains("\"liveActivity.settings.title\""))
            #expect(strings.contains("\"liveActivity.settings.status.active.title\""))
            #expect(strings.contains("\"liveActivity.settings.status.denied.title\""))
            #expect(strings.contains("\"liveActivity.settings.status.backgroundStart.title\""))
            #expect(strings.contains("\"liveActivity.settings.status.removed.title\""))
            #expect(strings.contains("\"liveActivity.settings.openSystemSettings\""))
        }
    }
}

private func liveActivityTimerSources() throws -> String {
    try [
        "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
        "timetrackerLiveActivityExtension/LiveActivityTimerPresentationViews.swift"
    ]
    .map(sourceText)
    .joined(separator: "\n")
}
