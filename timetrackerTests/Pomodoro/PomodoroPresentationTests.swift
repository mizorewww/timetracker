import Foundation
import Testing
@testable import timetracker

struct PomodoroPresentationTests {
    @Test
    func builtInPlansKeepStableUniqueSelectionIdentity() {
        let firstRead = PomodoroPlan.defaultPlans
        let secondRead = PomodoroPlan.defaultPlans

        #expect(firstRead.map(\.id) == secondRead.map(\.id))
        #expect(Set(firstRead.map(\.id)).count == firstRead.count)
    }
}
