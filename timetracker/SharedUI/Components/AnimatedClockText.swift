import SwiftUI

/// Shared changing-number treatment for running timers and countdowns.
///
/// The surrounding view owns the clock schedule. This view only explains a
/// numeric value change, so it cannot create another timer or invalidate a
/// larger page.
struct AnimatedClockText: View {
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
                reduceMotion ? nil : .snappy(duration: 0.22),
                value: value
            )
    }
}
