import SwiftUI

struct TaskSelectionPulseModifier<ID: Equatable, Token: Equatable>: ViewModifier {
    let selectedID: ID?
    let itemID: ID
    let pulseToken: Token
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.045 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isPulsing)
            .onChange(of: pulseToken) { _, _ in
                guard selectedID == itemID else { return }
                isPulsing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    isPulsing = false
                }
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
