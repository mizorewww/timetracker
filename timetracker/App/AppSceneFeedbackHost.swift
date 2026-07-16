import SwiftUI

private struct AppSceneFeedbackHostModifier: ViewModifier {
    let router: AppSceneFeedbackRouter

    func body(content: Content) -> some View {
        let feedback = router.current
        content.alert(
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
    }

    private func presentationBinding(feedbackID: UUID?) -> Binding<Bool> {
        Binding {
            router.current != nil
        } set: { isPresented in
            guard !isPresented, let feedbackID else { return }
            router.dismiss(feedbackID: feedbackID)
        }
    }
}

extension View {
    func appSceneFeedbackHost(router: AppSceneFeedbackRouter) -> some View {
        modifier(AppSceneFeedbackHostModifier(router: router))
    }
}
