import Foundation
import Testing

@Suite(.serialized)
struct BuildInstallScriptTests {
    @Test
    func mainSchemeSerializesUITestRunnerButKeepsUnitTestsParallelizable() throws {
        let scheme = try sourceText("timetracker.xcodeproj/xcshareddata/xcschemes/timetracker.xcscheme")
        let testables = scheme.components(separatedBy: "<TestableReference").dropFirst()
        let unitTests = try #require(
            testables.first { $0.contains("BlueprintName = \"timetrackerTests\"") }
        )
        let uiTests = try #require(
            testables.first { $0.contains("BlueprintName = \"timetrackerUITests\"") }
        )

        #expect(unitTests.contains("parallelizable = \"YES\""))
        #expect(uiTests.contains("parallelizable = \"NO\""))
    }
}
