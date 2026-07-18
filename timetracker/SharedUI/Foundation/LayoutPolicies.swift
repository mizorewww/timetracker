import SwiftUI

#if os(iOS)
import UIKit
#endif

struct RootLayoutPolicy: Equatable, Sendable {
    enum InterfaceIdiom: Equatable, Sendable {
        case phone
        case pad
        case unsupported
    }

    enum Shell: Equatable, Sendable {
        case phone
        case pad
    }

    let interfaceIdiom: InterfaceIdiom

    var shell: Shell {
        interfaceIdiom == .pad ? .pad : .phone
    }
}

#if os(iOS)
extension RootLayoutPolicy {
    init(userInterfaceIdiom: UIUserInterfaceIdiom) {
        let interfaceIdiom: InterfaceIdiom = switch userInterfaceIdiom {
        case .phone:
            .phone
        case .pad:
            .pad
        default:
            .unsupported
        }
        self.init(interfaceIdiom: interfaceIdiom)
    }
}
#endif

struct WidthLayoutPolicy {
    let width: CGFloat

    var isNarrow: Bool {
        width < 720
    }
}

struct HomeLayoutPolicy {
    private let width: CGFloat
    private let widthPolicy: WidthLayoutPolicy

    init(width: CGFloat) {
        self.width = width
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

    var usesTwoColumnContent: Bool {
        contentWidth >= 1_000
    }

    var contentMaxWidth: CGFloat {
        1_180
    }

    var contentWidth: CGFloat {
        min(max(0, width - (pagePadding * 2)), contentMaxWidth)
    }

    var supportingColumnWidth: CGFloat {
        360
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

enum TaskTreeDisclosureSlot: Equatable {
    case control
    case reserved
    case none

    init(depth: Int, hasChildren: Bool) {
        if hasChildren {
            self = .control
        } else if depth > 0 {
            self = .reserved
        } else {
            self = .none
        }
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

    var setupCardPadding: CGFloat {
        sizeClassPolicy.isCompactPhone ? 18 : 24
    }

    var setupSectionSpacing: CGFloat {
        sizeClassPolicy.isCompactPhone ? 20 : 24
    }
}

struct SplitColumnLayoutPolicy {
    var sidebar: ColumnWidth = ColumnWidth(min: 220, ideal: 240, max: 300)
    var detail: ColumnWidth = ColumnWidth(min: 520, ideal: 760, max: nil)

    static let iPad = SplitColumnLayoutPolicy(
        sidebar: ColumnWidth(min: 240, ideal: 260, max: 300),
        detail: ColumnWidth(min: 480, ideal: 760, max: nil)
    )

    static let mac = SplitColumnLayoutPolicy(
        sidebar: ColumnWidth(min: 220, ideal: 240, max: 270),
        detail: ColumnWidth(min: 420, ideal: 720, max: nil)
    )
}

struct ColumnWidth: Equatable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat?
}
