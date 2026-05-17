#if os(iOS)
import SwiftUI

extension TimeTrackerStore.DesktopDestination {
    static var phoneDestinations: [TimeTrackerStore.DesktopDestination] {
        [.today, .inbox, .tasks, .pomodoro, .analytics, .settings]
    }

    var phonePageIndex: Int {
        guard let index = Self.phoneDestinations.firstIndex(of: self) else { return 0 }
        return index / 4
    }

    var phoneSymbolName: String {
        switch self {
        case .today: return "house"
        case .inbox: return "tray"
        case .tasks: return "checklist"
        case .pomodoro: return "timer"
        case .analytics: return "chart.bar.xaxis"
        case .settings: return "gearshape"
        }
    }

    var phoneFilledSymbolName: String {
        switch self {
        case .today: return "house.fill"
        case .inbox: return "tray.fill"
        case .tasks: return "checklist.checked"
        case .pomodoro: return "timer"
        case .analytics: return "chart.bar.xaxis"
        case .settings: return "gearshape.fill"
        }
    }

    var phoneTint: Color {
        switch self {
        case .today: return .orange
        case .inbox: return .blue
        case .tasks: return .green
        case .pomodoro: return .red
        case .analytics: return .purple
        case .settings: return .gray
        }
    }
}
#endif
