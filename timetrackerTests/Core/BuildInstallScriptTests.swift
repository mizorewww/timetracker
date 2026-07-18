import Foundation
import Testing

@Suite(.serialized)
struct BuildInstallScriptTests {
    @Test
    func buildInstallScriptInstallsIOSContainerWithDependentWatchCompanion() throws {
        let script = try sourceText("scripts/build_install_all.sh")

        #expect(script.contains("IOS_EMBEDDED_WATCH_APP=\"$IOS_APP/Watch/${WATCH_PRODUCT_NAME}.app\""))
        #expect(script.contains("-allowProvisioningDeviceRegistration"))
        #expect(script.contains("validate_embedded_watch_companion"))
        #expect(script.contains("validate_embedded_watch_profile"))
        #expect(script.contains("connected_watch_udids"))
        #expect(script.contains("ProvisionedDevices"))
        #expect(script.contains("hardwareProperties.platform == 'watchOS'"))
        #expect(script.contains("WKCompanionAppBundleIdentifier"))
        #expect(script.contains("WKRunsIndependentlyOfCompanionApp"))
        #expect(script.contains("WKApplication"))
        #expect(script.contains("$ios_bundle_id.watchkitapp"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("xcrun devicectl list devices"))
        #expect(script.contains("run_xcodebuild \"$SCHEME\" -sdk iphoneos -destination \"generic/platform=iOS\" build"))
        #expect(script.contains("install_app_on_device \"$device_id\" \"$device_name\" \"$IOS_APP\" \"iOS/iPadOS\" \"$BUNDLE_ID\""))
        #expect(!script.contains("install_on_available_watch_devices"))
        #expect(!script.contains("WATCH_SCHEME"))
        #expect(script.contains("Automatic App Install"))
        #expect(script.contains("embedded watch: $IOS_EMBEDDED_WATCH_APP"))
    }

    @Test
    func iOSAppEmbedsWatchAppForPairedWatchInstall() throws {
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")

        #expect(project.contains("Embed Watch Content"))
        #expect(project.contains("dstPath = \"$(CONTENTS_FOLDER_PATH)/Watch\";"))
        #expect(project.contains("timetrackerWatchApp.app in Embed Watch Content"))
        #expect(project.contains("target = E7000000000000000000000D /* timetrackerWatchApp */;"))
        #expect(project.contains("PRODUCT_BUNDLE_IDENTIFIER = me.mezorewww.timetracker.watchkitapp;"))
        #expect(project.contains("INFOPLIST_KEY_WKCompanionAppBundleIdentifier = me.mezorewww.timetracker;"))
        #expect(project.contains("INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = NO;"))
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
