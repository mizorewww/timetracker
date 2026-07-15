import SwiftUI

extension View {
    @ViewBuilder
    func settingsPopoverAdaptation() -> some View {
        #if os(iOS)
        presentationCompactAdaptation(.sheet)
        #else
        self
        #endif
    }

    @ViewBuilder
    func settingsPopoverContentFrame(idealWidth: CGFloat) -> some View {
        #if os(macOS)
        frame(width: idealWidth)
        #else
        frame(maxWidth: .infinity)
        #endif
    }
}
