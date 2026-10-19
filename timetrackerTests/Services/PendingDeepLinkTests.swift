import Foundation
import Testing
@testable import timetracker

@MainActor
struct PendingDeepLinkTests {
    private let tasks = URL(string: "timetracker://open/tasks")!
    private let inbox = URL(string: "timetracker://open/inbox")!

    @Test
    func keepsOnlyTheNewestValidLink() {
        let pending = PendingDeepLink()

        #expect(pending.set(tasks))
        #expect(pending.set(inbox))
        #expect(pending.set(URL(string: "https://example.com")!) == false)

        #expect(pending.take() == inbox)
        #expect(pending.take() == nil)
    }

    @Test
    func restoreNeverReplacesANewerLink() {
        let pending = PendingDeepLink()
        pending.set(inbox)

        pending.restore(tasks)

        #expect(pending.take() == inbox)
        pending.restore(tasks)
        #expect(pending.take() == tasks)
    }
}
