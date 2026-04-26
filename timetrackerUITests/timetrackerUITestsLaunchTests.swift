//
//  timetrackerUITestsLaunchTests.swift
//  timetrackerUITests
//
//  Created by gaozexuan on 2026/4/25.
//

import XCTest

final class timetrackerUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.terminate()
        app.launch()
        app.activate()

        XCTAssertTrue(app.buttons["home.startTimer"].waitForExistence(timeout: 8))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
