import ActivityKit
import Foundation
import SwiftUI

func path(for state: TimeTrackingActivityAttributes.ContentState) -> String {
    state.taskPath.isEmpty ? String(localized: "live.timer.defaultPath") : state.taskPath
}

func abbreviatedPath(for state: TimeTrackingActivityAttributes.ContentState) -> String {
    guard let abbreviated = state.taskPathAbbreviated,
          abbreviated.isEmpty == false
    else {
        return path(for: state)
    }
    return abbreviated
}

func activityColor(_ hex: String) -> Color {
    guard let components = HexColorParser.components(for: hex) else { return .blue }
    return Color(red: components.red, green: components.green, blue: components.blue)
}

func activityForegroundColor(_ hex: String) -> Color {
    guard let components = HexColorParser.components(for: hex) else { return .white }
    let luminance = 0.2126 * linearSRGB(components.red)
        + 0.7152 * linearSRGB(components.green)
        + 0.0722 * linearSRGB(components.blue)
    return luminance > 0.179 ? .black : .white
}

private func linearSRGB(_ component: Double) -> Double {
    component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
}

enum LiveActivityDeepLinks {
    static let today = URL(string: "timetracker://open/today")!
}
