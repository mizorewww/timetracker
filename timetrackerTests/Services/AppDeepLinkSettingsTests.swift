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

    @Test
    func nativeSettingsWindowOpensEvenWhileASheetIsPresented() {
        let store = makeTestStore()
        let router = AppPresentationRouter(feedbackRouter: AppSceneFeedbackRouter())
        var openedNativeSettings = 0
        router.openNativeSettings = { openedNativeSettings += 1 }
        router.present(.startTaskPicker)

        let disposition = store.handleDeepLink(settingsURL, presentationRouter: router)

        #expect(disposition == .handled)
        #expect(openedNativeSettings == 1)
        guard case .startTaskPicker? = router.sheet?.content else {
            Issue.record("Opening the Settings window replaced the presented sheet.")
            return
        }
    }

    @Test
    func replacingASheetWithNativeSettingsClosesTheSheet() throws {
        let router = AppPresentationRouter(feedbackRouter: AppSceneFeedbackRouter())
        var openedNativeSettings = 0
        router.openNativeSettings = { openedNativeSettings += 1 }
        router.present(.aiTaskPlanGenerator)
        let presentationID = try #require(router.sheet?.id)

        #expect(router.replace(presentationID: presentationID, with: .settings))

        #expect(openedNativeSettings == 1)
        #expect(router.sheet == nil)
    }
}
