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
                isPresented: Binding {
                    router.feedback(forHost: hostID) != nil
                } set: { _ in
                    // Only OK clears the feedback; an alert torn down with
                    // its closing sheet reappears on the host below.
                },
                presenting: feedback
            ) { presentedFeedback in
                Button(AppStrings.localized("common.ok"), role: .cancel) {
                    router.dismiss(feedbackID: presentedFeedback.id)
                }
            } message: { presentedFeedback in
                Text(presentedFeedback.message)
            }
            .onAppear { router.registerHost(hostID) }
            .onDisappear { router.unregisterHost(hostID) }
    }
}

extension View {
    func appSceneFeedbackHost(router: AppSceneFeedbackRouter) -> some View {
        modifier(AppSceneFeedbackHostModifier(router: router))
    }
}
