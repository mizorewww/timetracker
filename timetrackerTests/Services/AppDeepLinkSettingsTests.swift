import Foundation
import Testing
@testable import timetracker

@MainActor
struct AppDeepLinkSettingsTests {
    private let settingsURL = URL(string: "timetracker://open/settings")!

    @Test
    func settingsLinkPresentsSettingsWithoutChangingThePage() {
        let store = makeTestStore()
        store.desktopDestination = .tasks
        let router = AppPresentationRouter(feedbackRouter: AppSceneFeedbackRouter())

        let disposition = store.handleDeepLink(settingsURL, presentationRouter: router)

        #expect(disposition == .handled)
        guard case .settings? = router.sheet?.content else {
            Issue.record("The settings link did not present Settings.")
            return
        }
        #expect(store.desktopDestination == .tasks)
    }

    @Test
    func settingsLinkWaitsWhileAnotherSheetIsPresented() {
        let store = makeTestStore()
        let router = AppPresentationRouter(feedbackRouter: AppSceneFeedbackRouter())
        router.present(.startTaskPicker)

        let disposition = store.handleDeepLink(settingsURL, presentationRouter: router)

        #expect(disposition == .deferred)
        guard case .startTaskPicker? = router.sheet?.content else {
            Issue.record("The settings link replaced the presented sheet.")
            return
        }
    }
}
