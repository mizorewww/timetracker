import SwiftUI

/// Shared changing-number treatment for running timers, countdowns and
/// totals.
///
/// The surrounding view owns the clock schedule. This view only explains a
/// numeric value change, so it cannot create another timer or invalidate a
/// larger page.
struct AnimatedNumberText: View {
    let text: String
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .monospacedDigit()
            .contentTransition(
                reduceMotion
                    ? .identity
                    : .numericText(value: Double(value))
            )
            .animation(
                reduceMotion ? nil : AppMotion.stateChange,
                value: value
            )
    }
}
