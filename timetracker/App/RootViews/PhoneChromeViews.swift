#if os(iOS)
import SwiftUI

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
        .accessibilityIdentifier("phone.bottomBar")
        .animation(modeAnimation, value: chrome.isBottomBarCollapsed)
    }

    private var expandedSelector: some View {
        VStack(spacing: 0) {
            pageIndicator
                .frame(height: PhoneRootChromeMetrics.bottomBarIndicatorBandHeight)

            GeometryReader { proxy in
                let pageWidth = proxy.size.width
                HStack(spacing: 0) {
                    ForEach(pages.enumerated(), id: \.offset) { _, page in
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
#endif
