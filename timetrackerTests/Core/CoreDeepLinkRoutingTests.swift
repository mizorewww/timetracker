import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreDeepLinkRoutingTests {
    @Test @MainActor
    func deepLinkRouterMapsKnownWidgetRoutesToAppActions() throws {
        let router = AppDeepLinkRouter()

        #expect(router.action(for: try #require(URL(string: "timetracker://open/inbox"))) == .open(.inbox))
        #expect(router.action(for: try #require(URL(string: "timetracker://open/tasks"))) == .open(.tasks))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start"))) == .startTimerPicker)
        let taskID = UUID()
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/start?taskID=\(taskID.uuidString)"))) == .startTimer(taskID))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop?taskID=\(taskID.uuidString)"))) == .stopTimer(taskID))
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/stop"))) == .stopTimer(nil))
        #expect(router.action(for: try #require(URL(string: "timetracker://task/new"))) == .newTask)
    }

    @Test @MainActor
    func deepLinkRouterRejectsUnknownOrExternalRoutes() throws {
        let router = AppDeepLinkRouter()

        #expect(router.action(for: try #require(URL(string: "https://example.com/open/inbox"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://open/missing"))) == nil)
        #expect(router.action(for: try #require(URL(string: "timetracker://timer/missing"))) == nil)
    }

    @Test
    func appAndWidgetDeclareDeepLinkIntegrationPoints() throws {
        let info = try sourceText("timetracker/Info.plist")
        let contentView = try sourceText("timetracker/App/ContentView.swift")
        let widget = try sourceText("timetrackerWidgetExtension/TimeTrackerWidget.swift")

        #expect(info.contains("<string>timetracker</string>"))
        #expect(contentView.contains(".onOpenURL"))
        #expect(contentView.contains("store.handleDeepLink"))
        #expect(widget.contains("timetracker://timer/start"))
        #expect(widget.contains("timetracker://open/today"))
    }

    @Test
    func liveActivityDeclaresStopDeepLinkAndLocalizedAction() throws {
        let router = try sourceText("timetracker/App/AppDeepLinkRouter.swift")
        let activity = try sourceText("timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift")
        let strings = try sourceText("timetrackerLiveActivityExtension/en.lproj/Localizable.strings")

        #expect(router.contains("case stopTimer(UUID?)"))
        #expect(activity.contains("timetracker://timer/stop?taskID="))
        #expect(activity.contains("live.timer.stop"))
        #expect(strings.contains("\"live.timer.stop\""))
    }
}
