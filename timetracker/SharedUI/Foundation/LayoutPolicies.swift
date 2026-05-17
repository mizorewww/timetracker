import SwiftUI

nonisolated struct WidthLayoutPolicy {
    let width: CGFloat

    var isNarrow: Bool {
        width < 720
    }
}

nonisolated struct HomeLayoutPolicy {
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

nonisolated struct SizeClassLayoutPolicy {
    let horizontalSizeClass: UserInterfaceSizeClass?

    var isCompactPhone: Bool {
        horizontalSizeClass == .compact
    }
}

nonisolated struct AnalyticsLayoutPolicy {
    private let sizeClassPolicy: SizeClassLayoutPolicy

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        sizeClassPolicy = SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var showsPageTitleInContent: Bool {
        !sizeClassPolicy.isCompactPhone
    }
}

nonisolated struct InboxLayoutPolicy {
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
        isCompact ? 0 : 28
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

    func rowHeight(forTitle title: String, isCompleted: Bool, hasSupplementaryContent: Bool) -> CGFloat {
        let titleExtra = CGFloat(max(0, estimatedTitleLineCount(for: title) - 1)) * (isCompact ? 18 : 20)
        if hasSupplementaryContent && !isCompleted {
            return suggestedRowHeight + titleExtra
        }
        return rowBaseHeight + titleExtra
    }

    private func estimatedTitleLineCount(for title: String) -> Int {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }

        let characterBudget = isCompact ? 26 : 78
        let weightedCount = trimmed.reduce(0) { total, character in
            total + (character.isASCII ? 1 : 2)
        }
        return min(5, max(1, Int(ceil(Double(weightedCount) / Double(characterBudget)))))
    }
}

nonisolated struct TaskListLayoutPolicy {
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

nonisolated struct PomodoroLayoutPolicy {
    private let sizeClassPolicy: SizeClassLayoutPolicy

    init(horizontalSizeClass: UserInterfaceSizeClass?) {
        sizeClassPolicy = SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var showsInlineHeader: Bool {
        !sizeClassPolicy.isCompactPhone
    }
}

nonisolated struct SplitColumnLayoutPolicy {
    var sidebar: ColumnWidth = ColumnWidth(min: 220, ideal: 240, max: 300)
    var detail: ColumnWidth = ColumnWidth(min: 520, ideal: 760, max: nil)

    static let iPad = SplitColumnLayoutPolicy(
        sidebar: ColumnWidth(min: 240, ideal: 260, max: 300),
        detail: ColumnWidth(min: 560, ideal: 780, max: nil)
    )

    static let mac = SplitColumnLayoutPolicy(
        sidebar: ColumnWidth(min: 220, ideal: 240, max: 270),
        detail: ColumnWidth(min: 520, ideal: 760, max: nil)
    )
}

nonisolated struct ColumnWidth: Equatable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat?
}
