import Foundation
import Testing
@testable import timetracker

@MainActor
struct StoreMutationBroadcasterTests {
    @MainActor
    private final class Recorder {
        var posts: [Set<StoreDomainEvent>] = []
    }

    @Test
    func mutationsInOneTurnArriveAsOneMergedPost() async {
        let recorder = Recorder()
        let token = NotificationCenter.default.addObserver(
            forName: StoreMutationBroadcaster.notification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                if let events = StoreMutationBroadcaster.events(from: notification) {
                    recorder.posts.append(events)
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let first = StoreDomainEvent.preferenceChanged(key: UUID().uuidString)
        let second = StoreDomainEvent.inboxChanged(itemIDs: [UUID()])
        StoreMutationBroadcaster.publish(events: [first])
        StoreMutationBroadcaster.publish(events: [second])
        #expect(recorder.posts.contains { $0.contains(first) } == false)

        #expect(await eventually { recorder.posts.contains { $0.contains(first) } })
        // Other suites may publish concurrently; ours must share one post.
        let posts = recorder.posts.filter {
            $0.contains(first) || $0.contains(second)
        }
        #expect(posts.count == 1)
        #expect(posts.first?.isSuperset(of: [first, second]) == true)
    }
}
