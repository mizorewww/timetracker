import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreAppSceneFeedbackRouterTests {
    @Test @MainActor
    func feedbackIsPresentedInFIFOOrder() throws {
        let first = AppSceneFeedback(
            id: UUID(),
            context: .dataExport,
            title: "Export",
            message: "First"
        )
        let second = AppSceneFeedback(
            id: UUID(),
            context: .syncRecovery,
            title: "Sync",
            message: "Second"
        )
        let router = AppSceneFeedbackRouter()

        router.present(first)
        router.present(second)

        #expect(router.current == first)
        #expect(router.pendingCount == 1)

        router.dismiss(feedbackID: first.id)

        #expect(router.current == second)
        #expect(router.pendingCount == 0)

        router.dismiss(feedbackID: second.id)
        #expect(router.current == nil)
    }

    @Test @MainActor
    func staleOrUnrelatedDismissalCannotClearCurrentFeedback() throws {
        let first = AppSceneFeedback(
            id: UUID(),
            title: "First",
            message: "First"
        )
        let second = AppSceneFeedback(
            id: UUID(),
            title: "Second",
            message: "Second"
        )
        let router = AppSceneFeedbackRouter()

        router.present(first)
        router.present(second)
        router.dismiss(feedbackID: UUID())
        #expect(router.current == first)

        router.dismiss(feedbackID: first.id)
        router.dismiss(feedbackID: first.id)
        #expect(router.current == second)
    }

    @Test @MainActor
    func separateSceneRoutersDoNotShareFeedback() throws {
        let mainRouter = AppSceneFeedbackRouter()
        let settingsRouter = AppSceneFeedbackRouter()

        let mainID = mainRouter.present(title: "Main", message: "Main failure")
        let settingsID = settingsRouter.present(
            context: .databaseMaintenance,
            title: "Settings",
            message: "Settings failure"
        )

        #expect(mainID != settingsID)
        #expect(mainRouter.current?.message == "Main failure")
        #expect(settingsRouter.current?.message == "Settings failure")

        settingsRouter.dismiss(feedbackID: settingsID)
        #expect(settingsRouter.current == nil)
        #expect(mainRouter.current?.id == mainID)
    }
}
