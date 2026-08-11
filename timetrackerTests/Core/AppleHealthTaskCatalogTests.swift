import Foundation
import Testing
@testable import timetracker

struct AppleHealthTaskCatalogTests {
    @Test
    func stableCatalogUUIDsMatchTheDurableIdentityContract() {
        #expect(
            AppleHealthTaskCatalog.categoryDefinition(for: .exercise).id ==
                UUID(uuidString: "A1100000-0000-4000-8000-000000000001")
        )
        #expect(
            AppleHealthTaskCatalog.taskDefinition(for: .workout(.walking)).id ==
                UUID(uuidString: "A1200000-0000-4000-8000-000000000001")
        )
        #expect(
            AppleHealthTaskCatalog.taskDefinition(for: .sleep).categoryAssignmentID ==
                UUID(uuidString: "A1300000-0000-4000-8000-000000000012")
        )
    }
}
