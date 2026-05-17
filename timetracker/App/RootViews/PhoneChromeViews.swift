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

struct PhonePagedBottomSelector: View {
    @ObservedObject var chrome: PhoneChromeCoordinator
    let destinations: [TimeTrackerStore.DesktopDestination]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0
    @Namespace private var barGlassNamespace

    private var pages: [[TimeTrackerStore.DesktopDestination?]] {
        stride(from: 0, to: destinations.count, by: 4).map { start in
            var page = destinations[start..<min(start + 4, destinations.count)].map(Optional.some)
            while page.count < 4 {
                page.append(nil)
            }
            return page
        }
    }

    private var maxPageIndex: Int {
        max(0, pages.count - 1)
    }

    private var modeAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.28)
    }

    private var pageAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24, extraBounce: 0)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GlassEffectContainer(spacing: 22) {
                if chrome.isBottomBarCollapsed {
                    collapsedGlass
                        .padding(.leading, PhoneRootChromeMetrics.bottomBarCollapsedSidePadding - PhoneRootChromeMetrics.bottomBarSidePadding)
                        .transition(.identity)
                } else {
                    expandedGlass
                        .transition(.identity)
                }
            }

            expandedSelector
                .opacity(chrome.isBottomBarCollapsed ? 0 : 1)
                .scaleEffect(chrome.isBottomBarCollapsed ? 0.98 : 1, anchor: .bottomLeading)
                .offset(y: chrome.isBottomBarCollapsed ? 8 : 0)
                .allowsHitTesting(!chrome.isBottomBarCollapsed)

            collapsedIndicator
                .padding(.leading, PhoneRootChromeMetrics.bottomBarCollapsedSidePadding - PhoneRootChromeMetrics.bottomBarSidePadding)
                .opacity(chrome.isBottomBarCollapsed ? 1 : 0)
                .scaleEffect(chrome.isBottomBarCollapsed ? 1 : 0.92, anchor: .bottomLeading)
                .offset(y: chrome.isBottomBarCollapsed ? 0 : 6)
                .allowsHitTesting(chrome.isBottomBarCollapsed)
        }
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .frame(height: chrome.isBottomBarCollapsed ? PhoneRootChromeMetrics.collapsedIndicatorSize : PhoneRootChromeMetrics.bottomBarExpandedHeight, alignment: .bottomLeading)
        .padding(.horizontal, PhoneRootChromeMetrics.bottomBarSidePadding)
        .padding(.bottom, PhoneRootChromeMetrics.bottomBarBottomPadding)
        .animation(modeAnimation, value: chrome.isBottomBarCollapsed)
    }

    private var expandedSelector: some View {
        VStack(spacing: 0) {
            pageIndicator
                .frame(height: PhoneRootChromeMetrics.bottomBarIndicatorBandHeight)

            GeometryReader { proxy in
                let pageWidth = proxy.size.width
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                        HStack(spacing: 0) {
                            ForEach(0..<page.count, id: \.self) { itemIndex in
                                if let destination = page[itemIndex] {
                                    PhoneBottomDestinationButton(
                                        destination: destination,
                                        isSelected: chrome.selectedDestination == destination,
                                        select: {
                                            chrome.select(destination)
                                        }
                                    )
                                    .frame(width: pageWidth / 4)
                                } else {
                                    Color.clear
                                        .frame(width: pageWidth / 4)
                                        .frame(height: PhoneRootChromeMetrics.bottomBarItemHeight)
                                }
                            }
                        }
                        .frame(width: pageWidth)
                    }
                }
                .offset(x: -CGFloat(chrome.selectedPageIndex) * pageWidth + dragOffset)
                .animation(pageAnimation, value: chrome.selectedPageIndex)
                .gesture(pageDragGesture)
            }
            .frame(height: PhoneRootChromeMetrics.bottomBarItemHeight)
            .clipped()

            Color.clear
                .frame(height: PhoneRootChromeMetrics.bottomBarIndicatorBandHeight)
        }
        .padding(.horizontal, 4)
        .frame(height: PhoneRootChromeMetrics.bottomBarExpandedHeight)
        .frame(maxWidth: .infinity)
    }

    private var expandedGlass: some View {
        Color.clear
            .frame(height: PhoneRootChromeMetrics.bottomBarExpandedHeight)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(true), in: RoundedRectangle(cornerRadius: PhoneRootChromeMetrics.bottomBarCornerRadius, style: .continuous))
            .glassEffectID("phone-bottom-bar-glass", in: barGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
    }

    private var collapsedGlass: some View {
        Color.clear
            .frame(width: PhoneRootChromeMetrics.collapsedIndicatorSize, height: PhoneRootChromeMetrics.collapsedIndicatorSize)
            .glassEffect(.regular.interactive(true).tint(chrome.selectedDestination.phoneTint.opacity(0.12)), in: RoundedRectangle(cornerRadius: PhoneRootChromeMetrics.collapsedIndicatorCornerRadius, style: .continuous))
            .glassEffectID("phone-bottom-bar-glass", in: barGlassNamespace)
            .glassEffectTransition(.matchedGeometry)
    }

    private var pageDragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                let threshold: CGFloat = 44
                let predicted = value.predictedEndTranslation.width
                let translation = abs(predicted) > abs(value.translation.width) ? predicted : value.translation.width
                let nextPage: Int
                if translation < -threshold {
                    nextPage = min(maxPageIndex, chrome.selectedPageIndex + 1)
                } else if translation > threshold {
                    nextPage = max(0, chrome.selectedPageIndex - 1)
                } else {
                    nextPage = chrome.selectedPageIndex
                }

                withAnimation(pageAnimation) {
                    chrome.selectedPageIndex = nextPage
                }
            }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pages.count, id: \.self) { pageIndex in
                Capsule()
                    .fill(pageIndex == chrome.selectedPageIndex ? chrome.selectedDestination.phoneTint.opacity(0.72) : Color.secondary.opacity(0.24))
                    .frame(width: pageIndex == chrome.selectedPageIndex ? 16 : 5, height: 5)
                    .animation(.snappy(duration: 0.2, extraBounce: 0), value: chrome.selectedPageIndex)
            }
        }
        .frame(height: PhoneRootChromeMetrics.bottomBarIndicatorBandHeight)
        .accessibilityHidden(true)
    }

    private var collapsedIndicator: some View {
        let destination = chrome.selectedDestination
        return Button {
            chrome.expandFromUser()
        } label: {
            Image(systemName: destination.phoneFilledSymbolName)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(destination.phoneTint, destination.phoneTint.opacity(0.42))
                .frame(width: PhoneRootChromeMetrics.collapsedIndicatorSize, height: PhoneRootChromeMetrics.collapsedIndicatorSize)
                .contentShape(RoundedRectangle(cornerRadius: PhoneRootChromeMetrics.collapsedIndicatorCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    if value.translation.height < -8 {
                        chrome.expandFromUser()
                    }
                }
        )
        .frame(width: PhoneRootChromeMetrics.collapsedIndicatorSize, height: PhoneRootChromeMetrics.collapsedIndicatorSize)
    }
}

private struct PhoneBottomDestinationButton: View {
    let destination: TimeTrackerStore.DesktopDestination
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(destination.phoneTint.opacity(0.18))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .padding(.horizontal, 7)
                        .overlay {
                            Capsule()
                                .stroke(destination.phoneTint.opacity(0.18), lineWidth: 0.5)
                                .padding(.horizontal, 7)
                        }
                        .allowsHitTesting(false)
                        .zIndex(0)
                }

                VStack(spacing: 3) {
                    Image(systemName: isSelected ? destination.phoneFilledSymbolName : destination.phoneSymbolName)
                        .font(.system(size: 19, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSelected ? destination.phoneTint : destination.phoneTint.opacity(0.82),
                            destination.phoneTint.opacity(isSelected ? 0.46 : 0.28)
                        )
                        .frame(height: 22)

                    Text(destination.title)
                        .font(.caption2.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(isSelected ? destination.phoneTint : Color.secondary)
                }
                .zIndex(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: PhoneRootChromeMetrics.bottomBarItemHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
    }
}

struct PhoneLargePageHeader: View {
    let destination: TimeTrackerStore.DesktopDestination

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: destination.phoneFilledSymbolName)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(destination.phoneTint, destination.phoneTint.opacity(0.36))
                .frame(width: 38, height: 38)
                .background(destination.phoneTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(destination.title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct PhoneRootChromeModifier: ViewModifier {
    @EnvironmentObject private var chrome: PhoneChromeCoordinator
    @Namespace private var titleGlassNamespace
    let destination: TimeTrackerStore.DesktopDestination

    func body(content: Content) -> some View {
        let opacity = chrome.toolbarTitleOpacity(for: destination)
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                PhoneFloatingToolbarTitle(
                    destination: destination,
                    opacity: opacity,
                    namespace: titleGlassNamespace
                )
            }
    }
}

private struct PhoneFloatingToolbarTitle: View {
    let destination: TimeTrackerStore.DesktopDestination
    let opacity: Double
    let namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Text(destination.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minWidth: 94)
                .frame(height: 36)
                .glassEffect(.regular, in: Capsule())
                .glassEffectID("phone-floating-title", in: namespace)
                .glassEffectTransition(.materialize)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .opacity(opacity)
        .scaleEffect(0.96 + (0.04 * CGFloat(opacity)))
        .animation(.smooth(duration: 0.18), value: opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PhoneChromeScrollObserver: ViewModifier {
    @EnvironmentObject private var chrome: PhoneChromeCoordinator
    let destination: TimeTrackerStore.DesktopDestination

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: PhoneChromeScrollState.self) { geometry in
                PhoneChromeScrollState(
                    offsetY: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height
                )
            } action: { _, state in
                chrome.updateScroll(state, for: destination)
            }
    }
}

private struct PhoneRootScrollBehaviorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

struct PhoneRootListBottomClearanceRow: View {
    var body: some View {
        Color.clear
            .frame(height: PhoneRootChromeMetrics.scrollBottomClearance)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct PhoneSecondaryDestinationModifier: ViewModifier {
    @EnvironmentObject private var chrome: PhoneChromeCoordinator
    let destination: TimeTrackerStore.DesktopDestination
    @State private var isRegistered = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isRegistered else { return }
                isRegistered = true
                chrome.enterSecondary(for: destination)
            }
            .onDisappear {
                guard isRegistered else { return }
                isRegistered = false
                chrome.exitSecondary(for: destination)
            }
    }
}

extension View {
    @ViewBuilder
    func phoneRootChrome(destination: TimeTrackerStore.DesktopDestination, enabled: Bool = true) -> some View {
        if enabled {
            modifier(PhoneRootChromeModifier(destination: destination))
        } else {
            self
        }
    }

    @ViewBuilder
    func phoneChromeScrollObserver(destination: TimeTrackerStore.DesktopDestination, enabled: Bool = true) -> some View {
        if enabled {
            modifier(PhoneChromeScrollObserver(destination: destination))
        } else {
            self
        }
    }

    @ViewBuilder
    func phoneSecondaryDestination(_ destination: TimeTrackerStore.DesktopDestination) -> some View {
        modifier(PhoneSecondaryDestinationModifier(destination: destination))
    }

    @ViewBuilder
    func phoneRootScrollMargins(enabled: Bool = true) -> some View {
        if enabled {
            contentMargins(.top, 0, for: .scrollContent)
                .modifier(PhoneRootScrollBehaviorModifier())
        } else {
            self
        }
    }

    @ViewBuilder
    func phoneRootScrollBehavior(enabled: Bool = true) -> some View {
        if enabled {
            modifier(PhoneRootScrollBehaviorModifier())
        } else {
            self
        }
    }
}

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
