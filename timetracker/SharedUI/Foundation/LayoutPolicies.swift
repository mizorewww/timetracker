import SwiftUI

/// Chooses the app shell from the space actually available, never from the
/// device model.
///
/// An idiom check gets this wrong in both directions: an iPad in Split View or
/// Slide Over has phone-sized width, and a Mac window dragged narrow should
/// behave the same way. HIG `layout.md` asks iPadOS apps to "support the full
/// range of window sizes" and to "defer switching to compact view as long as
/// possible", which is a statement about width, not hardware.
struct RootLayoutPolicy: Equatable, Sendable {
    enum Shell: Equatable, Sendable {
        /// Tab bar over a single navigation stack.
        case compact
        /// Sidebar plus detail split.
        case regular
    }

    /// Below this the split view cannot keep both columns usable, so the
    /// compact shell takes over. Shared with `WidthLayoutPolicy` so the app
    /// has exactly one shell breakpoint.
    static let regularShellMinimumWidth: CGFloat = WidthLayoutPolicy.narrowMaximumWidth

    /// `nil` until the first layout pass has measured the window.
    let measuredWidth: CGFloat?
    let horizontalSizeClass: UserInterfaceSizeClass?

    var shell: Shell {
        // The system's own compactness signal wins whenever it says compact:
        // that covers iPhone landscape and iPad Slide Over, where raw width
        // would over-promote to a split view. macOS always reports `.regular`,
        // so there width is the only signal — which is exactly what lets a
        // narrow Mac window fall back to the compact shell.
        if horizontalSizeClass == .compact {
            return .compact
        }
        // Before the first measurement, trust the size class rather than
        // flashing the wrong shell for one frame.
        guard let measuredWidth else { return .regular }
        return measuredWidth >= Self.regularShellMinimumWidth ? .regular : .compact
    }
}

extension EnvironmentValues {
    /// The shell the root chose for the current width.
    ///
    /// Published once by `AppRootView` so nested views can adapt without
    /// re-measuring or, worse, asking what device they are on. Defaults to
    /// `.regular` so a view rendered outside the app shell (a preview, a
    /// standalone sheet) gets the roomier treatment rather than the phone one.
    @Entry var layoutShell: RootLayoutPolicy.Shell = .regular
}

struct WidthLayoutPolicy {
    /// The one narrow/wide breakpoint in the app.
    static let narrowMaximumWidth: CGFloat = 720

    let width: CGFloat

    var isNarrow: Bool {
        width < Self.narrowMaximumWidth
    }
}

struct HomeLayoutPolicy {
    private static let currentStateTwoColumnMinimumWidth: CGFloat = 744
    private static let currentStatePrimaryMinimumWidth: CGFloat = 420
    private static let currentStatePrimaryMaximumWidth: CGFloat = 620
    private static let currentStateOverviewMinimumWidth: CGFloat = 280

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
        contentWidth >= 1000
    }

    func usesSideBySideCurrentState(prefersSingleColumn: Bool) -> Bool {
        !prefersSingleColumn &&
            contentWidth >= Self.currentStateTwoColumnMinimumWidth
    }

    var contentMaxWidth: CGFloat {
        1180
    }

    var contentWidth: CGFloat {
        min(max(0, width - (pagePadding * 2)), contentMaxWidth)
    }

    var supportingColumnWidth: CGFloat {
        360
    }

    var currentStatePrimaryColumnWidth: CGFloat {
        min(
            Self.currentStatePrimaryMaximumWidth,
            max(
                Self.currentStatePrimaryMinimumWidth,
                contentWidth - contentSpacing - Self.currentStateOverviewMinimumWidth
            )
        )
    }

    var currentStateOverviewColumnWidth: CGFloat {
        max(
            0,
            contentWidth - contentSpacing - currentStatePrimaryColumnWidth
        )
    }
}

struct SizeClassLayoutPolicy {
    let horizontalSizeClass: UserInterfaceSizeClass?

    /// Named for the width it describes, not for a device: a narrow Mac window
    /// and an iPad in Slide Over are both compact.
    var isCompact: Bool {
        horizontalSizeClass == .compact
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

    var setupCardPadding: CGFloat {
        sizeClassPolicy.isCompact ? 18 : 24
    }

    var setupSectionSpacing: CGFloat {
        sizeClassPolicy.isCompact ? 20 : 24
    }
}

struct SplitColumnLayoutPolicy {
    var sidebar: ColumnWidth = .init(min: 220, ideal: 240, max: 300)
    var detail: ColumnWidth = .init(min: 520, ideal: 760, max: nil)

    /// One preset for every platform that shows the split shell.
    ///
    /// The previous `.iPad` and `.mac` presets differed by 20pt of sidebar and
    /// 60pt of detail minimum, for no reason either one recorded. The more
    /// permissive bound of each pair is kept, so the split view stays usable
    /// all the way down to `RootLayoutPolicy.regularShellMinimumWidth` — below
    /// which the compact shell takes over regardless.
    static let standard = SplitColumnLayoutPolicy(
        sidebar: ColumnWidth(min: 220, ideal: 250, max: 300),
        detail: ColumnWidth(min: 420, ideal: 760, max: nil)
    )
}

struct ColumnWidth: Equatable {
    let min: CGFloat
    let ideal: CGFloat
    let max: CGFloat?
}
