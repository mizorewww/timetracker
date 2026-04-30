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
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
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
