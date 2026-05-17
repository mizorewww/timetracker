#if os(iOS)
import SwiftUI

enum PhoneRootChromeMetrics {
    static let pageHorizontalPadding: CGFloat = 18
    static let scrollBottomClearance: CGFloat = 112
    static let bottomBarSidePadding: CGFloat = 10
    static let bottomBarCollapsedSidePadding: CGFloat = 18
    static let bottomBarBottomPadding: CGFloat = 8
    static let bottomBarIndicatorBandHeight: CGFloat = 14
    static let bottomBarItemHeight: CGFloat = 50
    static let bottomBarExpandedHeight: CGFloat = bottomBarIndicatorBandHeight + bottomBarItemHeight + bottomBarIndicatorBandHeight
    static let bottomBarCornerRadius: CGFloat = 28
    static let collapsedIndicatorSize: CGFloat = 56
    static let collapsedIndicatorCornerRadius: CGFloat = 18
    static let groupedListOuterInset: CGFloat = 16

    static var groupedHeaderRowInsets: EdgeInsets {
        let inset = max(0, pageHorizontalPadding - groupedListOuterInset)
        return EdgeInsets(top: 0, leading: inset, bottom: 8, trailing: inset)
    }

    static var groupedSearchRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)
    }

    static var groupedSearchHorizontalAdjustment: CGFloat {
        pageHorizontalPadding - groupedListOuterInset - 8
    }
}
#endif
