import SwiftUI

struct WidthLayoutPolicy {
    let width: CGFloat

    var isNarrow: Bool {
        width < 720
    }
}

struct HomeLayoutPolicy {
    private let widthPolicy: WidthLayoutPolicy

    init(width: CGFloat) {
        widthPolicy = WidthLayoutPolicy(width: width)
    }

    var isCompact: Bool {
        widthPolicy.isNarrow
    }

    var contentSpacing: CGFloat {
        isCompact ? 16 : 22
    }

    var pagePadding: CGFloat {
        isCompact ? 18 : 28
    }

    var usesHorizontalMetrics: Bool {
        !isCompact
    }

    var showsQuickStartInDesktopFlow: Bool {
        !isCompact
    }
}

struct SizeClassLayoutPolicy {
    let horizontalSizeClass: UserInterfaceSizeClass?

    var isCompactPhone: Bool {
        horizontalSizeClass == .compact
    }
}

struct AnalyticsLayoutPolicy {
    private let sizeClassPolicy: SizeClassLayoutPolicy

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        sizeClassPolicy = SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var showsPageTitleInContent: Bool {
        !sizeClassPolicy.isCompactPhone
    }
}

struct InboxLayoutPolicy {
    private let sizeClassPolicy: SizeClassLayoutPolicy

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        sizeClassPolicy = SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var isCompact: Bool {
        sizeClassPolicy.isCompactPhone
    }

    var contentMaxWidth: CGFloat? {
        isCompact ? nil : 1100
    }

    var contentSpacing: CGFloat {
        isCompact ? 14 : 24
    }

    var pageHorizontalPadding: CGFloat {
        isCompact ? 28 : 34
    }

    var pageTopPadding: CGFloat {
        isCompact ? 6 : 28
    }

    var cardCornerRadius: CGFloat {
        isCompact ? 28 : 24
    }

    var cardHorizontalPadding: CGFloat {
        isCompact ? 14 : 18
    }

    var captureTopPadding: CGFloat {
        isCompact ? 14 : 18
    }

    var captureBottomPadding: CGFloat {
        isCompact ? 16 : 18
    }

    var rowVerticalPadding: CGFloat {
        isCompact ? 8 : 10
    }

    var rowBaseHeight: CGFloat {
        isCompact ? 78 : 82
    }

    var suggestedRowHeight: CGFloat {
        isCompact ? 142 : 132
    }
}

struct TaskListLayoutPolicy {
    private let sizeClassPolicy: SizeClassLayoutPolicy

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        sizeClassPolicy = SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var usesCompactRows: Bool {
        sizeClassPolicy.isCompactPhone
    }

    func showsNavigationChevron(hasChildren: Bool) -> Bool {
        usesCompactRows && !hasChildren
    }
}

struct PomodoroLayoutPolicy {
    private let sizeClassPolicy: SizeClassLayoutPolicy

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        sizeClassPolicy = SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var showsInlineHeader: Bool {
        !sizeClassPolicy.isCompactPhone
    }
}

struct SplitColumnLayoutPolicy {
    var sidebar: ColumnWidth = ColumnWidth(min: 220, ideal: 240, max: 300)
    var detail: ColumnWidth = ColumnWidth(min: 520, ideal: 760, max: nil)
    var inspector: ColumnWidth = ColumnWidth(min: 240, ideal: 260, max: 320)

    static let iPad = SplitColumnLayoutPolicy(
        sidebar: ColumnWidth(min: 240, ideal: 260, max: 300),
        detail: ColumnWidth(min: 560, ideal: 780, max: nil),
        inspector: ColumnWidth(min: 240, ideal: 260, max: 320)
    )

    static let mac = SplitColumnLayoutPolicy(
        sidebar: ColumnWidth(min: 220, ideal: 240, max: 270),
        detail: ColumnWidth(min: 520, ideal: 760, max: nil),
        inspector: ColumnWidth(min: 240, ideal: 260, max: 320)
    )
}

struct ColumnWidth: Equatable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat?
}
