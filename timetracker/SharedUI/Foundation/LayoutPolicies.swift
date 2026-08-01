import SwiftUI

/// Chooses the app shell from the space actually available, never from the
/// device model.
///
/// An idiom check gets this wrong in both directions: an iPad in Split View or
/// Slide Over has phone-sized width, and a Mac window dragged narrow should
/// behave the same way. HIG `layout.md` asks iPadOS apps to "support the full
/// range of window sizes" and to "defer switching to compact view as long as
/// possible", which is a statement about width, not hardware.
nonisolated struct RootLayoutPolicy: Equatable, Sendable {
    enum Shell: Equatable, Sendable {
        /// Tab bar over a single navigation stack.
        case compact
        /// Sidebar plus detail split.
        case regular
    }

    /// The only width information the root view needs to retain.
    ///
    /// Keeping the raw width in root state invalidates the complete app shell
    /// throughout a live window resize even though the shell can only change
    /// at one breakpoint.
    nonisolated enum WidthBand: Equatable, Sendable {
        case compact
        case regular

        init(width: CGFloat) {
            self = width < RootLayoutPolicy.regularShellMinimumWidth ? .compact : .regular
        }
    }

    /// Below this the split view cannot keep both columns usable, so the
    /// compact shell takes over. Shared with `WidthLayoutPolicy` so the app
    /// has exactly one shell breakpoint.
    static let regularShellMinimumWidth: CGFloat = WidthLayoutPolicy.narrowMaximumWidth

    /// `nil` until the first layout pass has measured the window.
    let measuredWidthBand: WidthBand?
    let horizontalSizeClass: UserInterfaceSizeClass?

    init(
        measuredWidth: CGFloat?,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) {
        measuredWidthBand = measuredWidth.map(WidthBand.init(width:))
        self.horizontalSizeClass = horizontalSizeClass
    }

    init(
        measuredWidthBand: WidthBand?,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) {
        self.measuredWidthBand = measuredWidthBand
        self.horizontalSizeClass = horizontalSizeClass
    }

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
        guard let measuredWidthBand else { return .regular }
        return switch measuredWidthBand {
        case .compact: .compact
        case .regular: .regular
        }
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

nonisolated struct WidthLayoutPolicy {
    /// The one narrow/wide breakpoint in the app.
    static let narrowMaximumWidth: CGFloat = 720

    let width: CGFloat

    var isNarrow: Bool {
        width < Self.narrowMaximumWidth
    }
}

/// A visually lossless, bounded measurement for Today-page layout.
///
/// Live macOS resizing can deliver several geometry values per rendered frame.
/// Today only needs exact values at its responsive breakpoints; between them,
/// an 8 pt bucket is below the page's spacing granularity and avoids rebuilding
/// all synchronous presentation projections for sub-visual changes.
nonisolated struct HomeViewportMeasurement: Equatable, Sendable {
    static let step: CGFloat = 8

    let layoutWidth: CGFloat

    init(width: CGFloat) {
        let finiteWidth = width.isFinite ? width : 0
        let boundedWidth = min(
            max(0, finiteWidth),
            HomeLayoutPolicy.maximumResponsiveViewportWidth
        )
        if boundedWidth == HomeLayoutPolicy.maximumResponsiveViewportWidth {
            layoutWidth = boundedWidth
            return
        }

        let segmentStart = HomeLayoutPolicy.responsiveViewportBreakpoints
            .last(where: { $0 <= boundedWidth }) ?? 0
        layoutWidth = segmentStart +
            ((boundedWidth - segmentStart) / Self.step).rounded(.down) * Self.step
    }
}

nonisolated struct HomeLayoutPolicy {
    private static let currentStateTwoColumnMinimumWidth: CGFloat = 744
    private static let currentStatePrimaryMinimumWidth: CGFloat = 420
    private static let currentStatePrimaryMaximumWidth: CGFloat = 620
    private static let currentStateOverviewMinimumWidth: CGFloat = 280
    private static let quickStartMinimumWidth: CGFloat = 300
    private static let regularPagePadding: CGFloat = 28
    private static let contentMaximumWidth: CGFloat = 1180
    private static let twoColumnContentMinimumWidth: CGFloat = 1000
    static let visualizationContentMaximumWidth: CGFloat = 720
    static let visualizationCardPadding: CGFloat = 14
    static let maximumResponsiveViewportWidth: CGFloat =
        contentMaximumWidth + (regularPagePadding * 2)
    static let responsiveViewportBreakpoints: [CGFloat] = [
        WidthLayoutPolicy.narrowMaximumWidth,
        currentStateTwoColumnMinimumWidth + (regularPagePadding * 2),
        twoColumnContentMinimumWidth + (regularPagePadding * 2),
        maximumResponsiveViewportWidth,
    ]

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
        isCompact ? 18 : Self.regularPagePadding
    }

    var usesTwoColumnContent: Bool {
        contentWidth >= Self.twoColumnContentMinimumWidth
    }

    func usesSideBySideCurrentState(prefersSingleColumn: Bool) -> Bool {
        !prefersSingleColumn &&
            contentWidth >= Self.currentStateTwoColumnMinimumWidth
    }

    var contentMaxWidth: CGFloat {
        Self.contentMaximumWidth
    }

    var contentWidth: CGFloat {
        min(max(0, width - (pagePadding * 2)), contentMaxWidth)
    }

    var supportingColumnWidth: CGFloat {
        360
    }

    var visualizationSectionWidth: CGFloat {
        min(
            contentWidth,
            Self.visualizationContentMaximumWidth +
                (Self.visualizationCardPadding * 2)
        )
    }

    var wideVisualizationColumnWidth: CGFloat {
        min(
            visualizationSectionWidth,
            max(
                0,
                contentWidth - contentSpacing -
                    Self.quickStartMinimumWidth
            )
        )
    }

    var wideQuickStartColumnWidth: CGFloat {
        max(
            0,
            contentWidth - contentSpacing -
                wideVisualizationColumnWidth
        )
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
    let shell: RootLayoutPolicy.Shell

    var setupCardPadding: CGFloat {
        shell == .compact ? 18 : 24
    }

    var setupSectionSpacing: CGFloat {
        shell == .compact ? 20 : 24
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
