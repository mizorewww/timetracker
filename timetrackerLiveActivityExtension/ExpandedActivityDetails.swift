import ActivityKit
import SwiftUI
import WidgetKit

struct ExpandedActivityDetails: View {
    let context: ActivityViewContext<TimeTrackingActivityAttributes>

    var body: some View {
        LiveActivityTimerRow(
            state: context.state,
            isStale: context.isStale,
            style: .dynamicIsland
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
