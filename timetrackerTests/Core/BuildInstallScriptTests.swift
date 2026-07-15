import Foundation
import Testing

@Suite(.serialized)
struct BuildInstallScriptTests {
    @Test
    func buildInstallScriptBuildsAndInstallsWatchApp() throws {
        let script = try sourceText("scripts/build_install_all.sh")

        #expect(script.contains("WATCH_SCHEME=\"${WATCH_SCHEME:-timetrackerWatchApp}\""))
        #expect(script.contains("WATCH_PRODUCTS=\"$DERIVED_DATA/Build/Products/${CONFIGURATION}-watchos\""))
        #expect(script.contains("WATCH_APP=\"$WATCH_PRODUCTS/${WATCH_PRODUCT_NAME}.app\""))
        #expect(script.contains("IOS_EMBEDDED_WATCH_APP=\"$IOS_APP/Watch/${WATCH_PRODUCT_NAME}.app\""))
        #expect(script.contains("report_embedded_watch_content"))
        #expect(script.contains("-allowProvisioningDeviceRegistration"))
        #expect(script.contains("validate_watch_profile \"$IOS_EMBEDDED_WATCH_APP\" \"embedded Watch companion\""))
        #expect(script.contains("validate_watch_profile \"$WATCH_APP\" \"watchOS app\""))
        #expect(script.contains("ALLOW_INVALID_WATCH_PROFILE=\"${ALLOW_INVALID_WATCH_PROFILE:-0}\""))
        #expect(script.contains("profile_contains_connected_watch"))
        #expect(script.contains("connected_watch_udids()"))
        #expect(script.contains("profile_provisioned_devices()"))
        #expect(script.contains("available_watch_devices_json()"))
        #expect(script.contains("install_on_available_watch_devices()"))
        #expect(script.contains("watch_xcodebuild_destinations()"))
        #expect(script.contains("build_watch_app()"))
        #expect(script.contains("hardwareProperties.platform == 'watchOS'"))
        #expect(script.contains("xcrun devicectl list devices"))
        #expect(script.contains("run_xcodebuild \"$SCHEME\" -sdk iphoneos -destination \"generic/platform=iOS\" build"))
        #expect(script.contains("run_xcodebuild \"$WATCH_SCHEME\" -destination \"$destination\" build"))
        #expect(script.contains("run_xcodebuild \"$WATCH_SCHEME\" -destination \"generic/platform=watchOS\" build"))
        #expect(!script.contains("run_xcodebuild -scheme \"$WATCH_SCHEME\""))
        #expect(script.contains("install_app_on_device \"$device_id\" \"$device_name\" \"$WATCH_APP\" \"watchOS\" \"\""))
        #expect(script.contains("Skipping direct watch install"))
        #expect(script.contains("embedded Watch companion"))
        #expect(script.contains("includes the connected Apple Watch"))
        #expect(script.contains("cannot be verified for the connected Apple Watch"))
        #expect(script.contains("integrity could not be verified"))
        #expect(script.contains("watchOS app:   $WATCH_APP"))
        #expect(script.contains("embedded watch: $IOS_EMBEDDED_WATCH_APP"))
    }

    @Test
    func iOSAppEmbedsWatchAppForPairedWatchInstall() throws {
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")

        #expect(project.contains("Embed Watch Content"))
        #expect(project.contains("dstPath = \"$(CONTENTS_FOLDER_PATH)/Watch\";"))
        #expect(project.contains("timetrackerWatchApp.app in Embed Watch Content"))
        #expect(project.contains("target = E7000000000000000000000D /* timetrackerWatchApp */;"))
    }

    @Test
    func watchAppHasSharedSchemeWithWatchLaunchTarget() throws {
        let scheme = try sourceText("timetracker.xcodeproj/xcshareddata/xcschemes/timetrackerWatchApp.xcscheme")

        #expect(scheme.contains("BuildableName = \"timetrackerWatchApp.app\""))
        #expect(scheme.contains("BlueprintIdentifier = \"E7000000000000000000000D\""))
        #expect(scheme.contains("BlueprintName = \"timetrackerWatchApp\""))
        #expect(scheme.contains("<LaunchAction"))
        #expect(!scheme.contains("BuildableName = \"timetracker.app\""))
    }

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

    @Test
    func watchAppHasDedicatedAppIconAsset() throws {
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")
        let appIcon = try sourceText("timetrackerWatchApp/Assets.xcassets/AppIcon.appiconset/Contents.json")

        #expect(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"))
        #expect(appIcon.contains("\"platform\" : \"watchos\""))
        #expect(appIcon.contains("\"filename\" : \"AppIcon-1024.png\""))
    }
}
