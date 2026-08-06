import SwiftUI

/// Cross-platform page-entrance transition.
///
/// Content fades and lifts in briefly whenever it appears. Both shells apply
/// it: the compact shell's tab content and the regular shell's detail column.
/// A short entrance transition makes page switches feel deliberate and smooth
/// even when a few tens of milliseconds of layout still land after the
/// switch, instead of exposing a hard cut. Pure SwiftUI — no platform
/// branches.
struct PageEntranceTransition: ViewModifier {
    var duration: Double = 0.2
    var liftDistance: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isPresented ? 1 : 0)
            .offset(
                y: reduceMotion || isPresented ? 0 : liftDistance
            )
            .onAppear {
                // onAppear re-fires on every tab reselection (compact shell)
                // and destination change (regular shell), so the transition
                // replays for each switch.
                guard reduceMotion == false else {
                    isPresented = true
                    return
                }
                isPresented = false
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: duration)) {
                        isPresented = true
                    }
                }
            }
    }
}

extension View {
    /// Fades and lifts the content in on every appearance (page switch).
    func pageEntranceTransition(
        duration: Double = 0.2,
        liftDistance: CGFloat = 6
    ) -> some View {
        modifier(
            PageEntranceTransition(
                duration: duration,
                liftDistance: liftDistance
            )
        )
    }
}
