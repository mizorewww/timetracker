import ActivityKit
import Foundation
import SwiftUI

func path(for state: TimeTrackingActivityAttributes.ContentState) -> String {
    state.taskPath.isEmpty ? String(localized: "live.timer.defaultPath") : state.taskPath
}

func abbreviatedPath(for state: TimeTrackingActivityAttributes.ContentState) -> String {
    guard let abbreviated = state.taskPathAbbreviated,
          abbreviated.isEmpty == false else {
        return path(for: state)
    }
    return abbreviated
}

func activityColor(_ hex: String) -> Color {
    guard let components = activityRGB(hex) else { return .blue }
    return Color(red: components.red, green: components.green, blue: components.blue)
}

func activityForegroundColor(_ hex: String) -> Color {
    guard let components = activityRGB(hex) else { return .white }
    let luminance = 0.2126 * linearSRGB(components.red)
        + 0.7152 * linearSRGB(components.green)
        + 0.0722 * linearSRGB(components.blue)
    return luminance > 0.179 ? .black : .white
}

private func activityRGB(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
    var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    if value.count == 3 {
        value = value.map { "\($0)\($0)" }.joined()
    }
    guard value.count == 6 else { return nil }

    var int: UInt64 = 0
    guard Scanner(string: value).scanHexInt64(&int) else { return nil }
    let red = Double((int >> 16) & 0xFF) / 255
    let green = Double((int >> 8) & 0xFF) / 255
    let blue = Double(int & 0xFF) / 255
    return (red, green, blue)
}

private func linearSRGB(_ component: Double) -> Double {
    component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
}

enum LiveActivityDeepLinks {
    static let today = URL(string: "timetracker://open/today")!
}

enum LiveActivityElapsedFormatter {
    nonisolated static func clock(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .time(pattern: .hourMinuteSecond).locale(.autoupdatingCurrent)
        )
    }
}
