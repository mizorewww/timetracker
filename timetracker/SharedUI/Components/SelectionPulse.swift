import SwiftUI

struct TaskSelectionPulseModifier<ID: Equatable, Token: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selectedID: ID?
    let itemID: ID
    let pulseToken: Token
    @State private var isPulsing = false
    @State private var resetTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && !reduceMotion ? 1.025 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isPulsing)
            .onChange(of: pulseToken) { _, _ in
                guard selectedID == itemID else { return }
                resetTask?.cancel()
                guard !reduceMotion else {
                    isPulsing = false
                    return
                }
                isPulsing = true
                resetTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    isPulsing = false
                }
            }
            .onDisappear {
                resetTask?.cancel()
            }
    }
}

extension View {
    func taskSelectionPulse<ID: Equatable, Token: Equatable>(
        selectedID: ID?,
        itemID: ID,
        pulseToken: Token
    ) -> some View {
        modifier(TaskSelectionPulseModifier(selectedID: selectedID, itemID: itemID, pulseToken: pulseToken))
    }
}
