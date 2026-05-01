import Foundation
import SwiftUI

enum AppStrings {
    static let appName = localized("app.name")

    static let today = localized("nav.today")
    static let inbox = localized("nav.inbox")
    static let tasks = localized("nav.tasks")
    static let pomodoro = localized("nav.pomodoro")
    static let analytics = localized("nav.analytics")
    static let settings = localized("nav.settings")

    static let activeTimers = localized("home.activeTimers")
    static let pausedSessions = localized("home.pausedSessions")
    static let todayTimeline = localized("home.todayTimeline")
    static let quickStart = localized("home.quickStart")
    static let startTimer = localized("action.startTimer")
    static let newTask = localized("action.newTask")
    static let addTime = localized("action.addTime")
    static let refresh = localized("action.refresh")
    static let cancel = localized("action.cancel")
    static let done = localized("action.done")
    static let edit = localized("action.edit")
    static let delete = localized("action.delete")
    static let noActiveTimers = localized("empty.noActiveTimers")
    static let noTodaySegments = localized("empty.noTodaySegments")
    static let rootTask = localized("task.root")
    static let running = localized("status.running")
    static let paused = localized("status.paused")
    static let wallTime = localized("metric.wallTime")
    static let grossTime = localized("metric.grossTime")
    static let todayTracked = localized("metric.todayTracked")

    static func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

extension LocalizedStringKey {
    static func app(_ key: String) -> LocalizedStringKey {
        LocalizedStringKey(key)
    }
}
