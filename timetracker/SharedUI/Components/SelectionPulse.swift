import SwiftUI

struct TaskSelectionPulseModifier<ID: Equatable, Token: Equatable>: ViewModifier {
    let selectedID: ID?
    let itemID: ID
    let pulseToken: Token
    @State private var isPulsing = false
    @State private var pulseResetTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.045 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isPulsing)
            .onChange(of: pulseToken) { _, _ in
                guard selectedID == itemID else { return }
                pulseResetTask?.cancel()
                isPulsing = true
                pulseResetTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard !Task.isCancelled else { return }
                    isPulsing = false
                    pulseResetTask = nil
                }
            }
            .onDisappear {
                pulseResetTask?.cancel()
                pulseResetTask = nil
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
