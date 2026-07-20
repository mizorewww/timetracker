import SwiftUI

private struct PhoneTabNavigationSafetyModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var requestID: UUID?
    let navigationGuard: TaskDetailNavigationGuard

    func body(content: Content) -> some View {
        content
            .editorDiscardConfirmation(
                isPresented: $isPresented,
                hasUnsavedChanges: navigationGuard.pendingNavigationID
                    == requestID,
                discard: discardChangesAndNavigate
            )
            .onChange(of: isPresented) { _, isPresented in
                cancelPendingNavigationIfNeeded(isPresented: isPresented)
            }
    }

    private func cancelPendingNavigationIfNeeded(
        isPresented presentationIsActive: Bool
    ) {
        guard presentationIsActive == false,
              let requestID else { return }
        Task { @MainActor in
            await Task.yield()
            defer {
                if self.requestID == requestID {
                    self.requestID = nil
                }
            }
            guard isPresented == false,
                  navigationGuard.pendingNavigationID == requestID else {
                return
            }
            navigationGuard.cancelPendingNavigation(requestID: requestID)
        }
    }

    private func discardChangesAndNavigate() {
        guard let requestID else { return }
        navigationGuard.discardChangesAndCompletePendingNavigation(
            requestID: requestID
        )
    }
}

extension View {
    func phoneTabNavigationSafety(
        isPresented: Binding<Bool>,
        requestID: Binding<UUID?>,
        navigationGuard: TaskDetailNavigationGuard
    ) -> some View {
        modifier(
            PhoneTabNavigationSafetyModifier(
                isPresented: isPresented,
                requestID: requestID,
                navigationGuard: navigationGuard
            )
        )
    }
}
