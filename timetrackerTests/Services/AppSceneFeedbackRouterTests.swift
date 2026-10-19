import Foundation
import Testing
@testable import timetracker

@MainActor
struct AppSceneFeedbackRouterTests {
    @Test
    func feedbackRaisedUnderASheetGoesToTheSheetAndBackToTheRootWhenItCloses() {
        let router = AppSceneFeedbackRouter()
        let root = UUID()
        let sheet = UUID()
        router.registerHost(root)
        router.registerHost(sheet)

        router.present(title: "Failed", message: "Try again")

        #expect(router.feedback(forHost: sheet)?.message == "Try again")
        #expect(router.feedback(forHost: root) == nil)

        router.unregisterHost(sheet)

        #expect(router.feedback(forHost: root)?.message == "Try again")
    }
}
