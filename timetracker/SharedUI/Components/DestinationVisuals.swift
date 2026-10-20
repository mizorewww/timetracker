import SwiftUI

/// Symbol and solid-tile color of a top-level destination.
struct DestinationVisual {
    let symbolName: String
    let tint: Color

    static let settings = DestinationVisual(symbolName: "gearshape.fill", tint: .gray)
}

extension TimeTrackerStore.DesktopDestination {
    var visual: DestinationVisual {
        switch self {
        case .today: DestinationVisual(symbolName: "sun.max.fill", tint: .orange)
        case .inbox: DestinationVisual(symbolName: "tray.fill", tint: .blue)
        case .tasks: DestinationVisual(symbolName: "checklist", tint: .green)
        case .pomodoro: DestinationVisual(symbolName: "timer", tint: .pink)
        case .analytics: DestinationVisual(symbolName: "chart.bar.fill", tint: .purple)
        }
    }
}
