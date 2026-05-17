#if os(iOS)
import Combine
import SwiftUI

@MainActor
final class PhoneChromeCoordinator: ObservableObject {
    enum BottomBarMode {
        case expanded
        case collapsed
    }

    @Published var selectedDestination: TimeTrackerStore.DesktopDestination = .today
    @Published var selectedPageIndex = 0
    @Published var bottomBarMode: BottomBarMode = .expanded

    private var scrollStates: [TimeTrackerStore.DesktopDestination: PhoneChromeScrollState] = [:]
    private var secondaryDepths: [TimeTrackerStore.DesktopDestination: Int] = [:]
    private var manualExpandedOffset: CGFloat?

    private let collapseOffset: CGFloat = 72
    private let expandResetOffset: CGFloat = 16
    private let recollapseDistance: CGFloat = 56

    var isBottomBarCollapsed: Bool {
        bottomBarMode == .collapsed
    }

    func select(_ destination: TimeTrackerStore.DesktopDestination) {
        selectedDestination = destination
        selectedPageIndex = destination.phonePageIndex

        if secondaryDepth(for: destination) > 0 {
            collapseBottomBar()
        } else {
            expandBottomBar(trackCurrentOffset: true)
        }
    }

    func expandFromUser() {
        selectedPageIndex = selectedDestination.phonePageIndex
        expandBottomBar(trackCurrentOffset: true)
    }

    func updateScroll(_ state: PhoneChromeScrollState, for destination: TimeTrackerStore.DesktopDestination) {
        scrollStates[destination] = state
        guard destination == selectedDestination else { return }
        guard secondaryDepth(for: destination) == 0 else {
            collapseBottomBar()
            return
        }

        if state.offsetY <= expandResetOffset {
            manualExpandedOffset = nil
            expandBottomBar(trackCurrentOffset: false)
            return
        }

        guard state.isLongPage, state.offsetY > collapseOffset else { return }

        if let anchor = manualExpandedOffset {
            guard state.offsetY > max(collapseOffset, anchor + recollapseDistance) else { return }
            manualExpandedOffset = nil
        }

        collapseBottomBar()
    }

    func enterSecondary(for destination: TimeTrackerStore.DesktopDestination) {
        secondaryDepths[destination, default: 0] += 1
        if destination == selectedDestination {
            collapseBottomBar()
        }
    }

    func exitSecondary(for destination: TimeTrackerStore.DesktopDestination) {
        let nextDepth = max(0, secondaryDepth(for: destination) - 1)
        secondaryDepths[destination] = nextDepth
        if destination == selectedDestination, nextDepth == 0 {
            expandBottomBar(trackCurrentOffset: true)
        }
    }

    func toolbarTitleOpacity(for destination: TimeTrackerStore.DesktopDestination) -> Double {
        guard destination == selectedDestination else { return 0 }
        guard let state = scrollStates[destination] else { return 0 }
        let fadeDistance: CGFloat = 24
        return Double(min(max((state.offsetY - 4) / fadeDistance, 0), 1))
    }

    private func collapseBottomBar() {
        guard bottomBarMode != .collapsed else { return }
        bottomBarMode = .collapsed
    }

    private func expandBottomBar(trackCurrentOffset: Bool) {
        if trackCurrentOffset {
            manualExpandedOffset = scrollStates[selectedDestination]?.offsetY
        }
        selectedPageIndex = selectedDestination.phonePageIndex
        guard bottomBarMode != .expanded else { return }
        bottomBarMode = .expanded
    }

    private func secondaryDepth(for destination: TimeTrackerStore.DesktopDestination) -> Int {
        secondaryDepths[destination] ?? 0
    }
}

struct PhoneChromeScrollState: Equatable {
    let offsetY: CGFloat
    let scrollableDistance: CGFloat
    let contentScrollableDistance: CGFloat

    var canScroll: Bool {
        scrollableDistance > 8
    }

    var isLongPage: Bool {
        contentScrollableDistance > 160
    }

    init(offsetY: CGFloat, contentHeight: CGFloat, containerHeight: CGFloat, bottomClearance: CGFloat = PhoneRootChromeMetrics.scrollBottomClearance) {
        self.offsetY = (offsetY / 4).rounded() * 4
        scrollableDistance = max(0, contentHeight - containerHeight)
        contentScrollableDistance = max(0, contentHeight - bottomClearance - containerHeight)
    }
}
#endif
