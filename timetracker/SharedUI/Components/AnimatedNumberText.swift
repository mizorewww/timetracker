import SwiftUI

/// Rolls a number to its new value: totals, durations and the Focus
/// countdown face. Timers in rows tick as plain monospaced text, since rolling
/// every second keeps the whole window animating.
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
