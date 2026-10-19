import SwiftUI

/// Shows the scene's feedback as an alert. Attached at the scene root and
/// inside every sheet; the topmost attached host presents, so feedback raised
/// from a sheet appears over that sheet.
private struct AppSceneFeedbackHostModifier: ViewModifier {
    let router: AppSceneFeedbackRouter
    @State private var hostID = UUID()

    func body(content: Content) -> some View {
        let feedback = router.feedback(forHost: hostID)
        content
            .alert(
                feedback?.title ?? "",
                isPresented: presentationBinding(feedbackID: feedback?.id),
                presenting: feedback
            ) { presentedFeedback in
                Button(AppStrings.localized("common.ok")) {
                    router.dismiss(feedbackID: presentedFeedback.id)
                }
            } message: { presentedFeedback in
                Text(presentedFeedback.message)
            }
            .onAppear { router.registerHost(hostID) }
            .onDisappear { router.unregisterHost(hostID) }
    }

    private func presentationBinding(feedbackID: UUID?) -> Binding<Bool> {
        Binding {
            router.feedback(forHost: hostID) != nil
        } set: { isPresented in
            // A host covered by a new sheet hides its alert without
            // dismissing the feedback, which the new topmost host shows.
            guard !isPresented, let feedbackID,
                  router.hostIDs.last == hostID else { return }
            router.dismiss(feedbackID: feedbackID)
        }
    }
}

extension View {
    func appSceneFeedbackHost(router: AppSceneFeedbackRouter) -> some View {
        modifier(AppSceneFeedbackHostModifier(router: router))
    }
}
