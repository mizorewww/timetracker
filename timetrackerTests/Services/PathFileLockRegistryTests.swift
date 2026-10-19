import Foundation
import Testing
@testable import timetracker

struct PathFileLockRegistryTests {
    @Test
    func nestedAccessThroughAnAliasReusesTheHeldLockAndCanBeTakenAgainAfterwards() throws {
        let registry = PathFileLockRegistry()
        let directory = try makeStoreDirectory()
        let lockURL = directory.appending(path: "store.lock")
        let alias = directory.appending(path: "nested/../store.lock")

        let depth = try registry.withExclusiveAccess(to: lockURL) {
            try registry.withExclusiveAccess(to: alias) { 2 }
        }
        #expect(depth == 2)

        // After the last user returns the entry is released; a later caller
        // must still be able to take the file lock.
        #expect(try registry.withExclusiveAccess(to: lockURL) { true })
    }
}
