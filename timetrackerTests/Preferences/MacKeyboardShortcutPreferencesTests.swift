#if os(macOS)
import AppKit
import MacKeyboardShortcuts
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct MacKeyboardShortcutPreferencesTests {
    @Test
    func actionRegistryCoversMajorMacCommandsWithSafeDefaults() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }

        let expected: [
            (
                MacKeyboardShortcutAction,
                MacKeyboardShortcutGroup,
                KeyboardShortcuts.Shortcut?
            )
        ] = [
            (.addTime, .creation, .init(.m, modifiers: [.command, .shift])),
            (.chooseTaskToStart, .creation, nil),
            (.startSelectedTask, .timing, .init(.s, modifiers: [.command, .shift])),
            (.stopSelectedTask, .timing, nil),
            (.addSubtask, .creation, nil),
            (.startPomodoro, .timing, .init(.p, modifiers: [.command, .shift])),
            (.archiveSelectedTask, .organization, nil),
            (.newTaskCategory, .creation, nil),
            (.sortTaskCategories, .organization, nil),
            (.generateTaskPlan, .organization, nil),
            (.navigateToday, .navigation, .init(.one, modifiers: [.command])),
            (.navigateInbox, .navigation, .init(.two, modifiers: [.command])),
            (.navigateTasks, .navigation, .init(.three, modifiers: [.command])),
            (.navigatePomodoro, .navigation, .init(.four, modifiers: [.command])),
            (.navigateAnalytics, .navigation, .init(.five, modifiers: [.command])),
            (.refreshData, .data, .init(.r, modifiers: [.command])),
        ]

        #expect(MacKeyboardShortcutAction.allCases == expected.map(\.0))
        for (action, group, shortcut) in expected {
            #expect(action.group == group)
            #expect(action.defaultShortcut == shortcut)
            #expect(fixture.store.shortcut(for: action) == shortcut)
        }
        let groupedActions = MacKeyboardShortcutGroup.allCases.flatMap(\.actions)
        #expect(groupedActions.count == MacKeyboardShortcutAction.allCases.count)
        #expect(Set(groupedActions) == Set(MacKeyboardShortcutAction.allCases))

        let assignedDefaults = expected.compactMap(\.2)
        #expect(Set(assignedDefaults).count == assignedDefaults.count)
        #expect(
            assignedDefaults.allSatisfy(
                MacKeyboardShortcutAction.isValidAssignment
            )
        )
    }

    @Test
    func commandPersistsAnOverrideAcrossStoreInstances() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let replacement = KeyboardShortcuts.Shortcut(
            .t,
            modifiers: [.command, .option]
        )

        try fixture.command.setShortcut(replacement, for: .addTime)

        let reloaded = UserDefaultsMacKeyboardShortcutPreferenceStore(
            defaults: fixture.defaults
        )
        #expect(
            reloaded.shortcut(for: .addTime) ==
                replacement
        )
        #expect(
            reloaded.shortcut(for: .refreshData) ==
                MacKeyboardShortcutAction.refreshData.defaultShortcut
        )
    }

    @Test
    func explicitClearPersistsInsteadOfFallingBackToTheDefault() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }

        try fixture.command.setShortcut(nil, for: .startPomodoro)

        let reloaded = UserDefaultsMacKeyboardShortcutPreferenceStore(
            defaults: fixture.defaults
        )
        #expect(reloaded.shortcut(for: .startPomodoro) == nil)
        #expect(
            fixture.defaults.data(
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            ) != nil
        )
    }

    @Test
    func defaultNilActionCanBeAssignedThenClearedBackToDefault() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let replacement = KeyboardShortcuts.Shortcut(
            .b,
            modifiers: [.command, .option]
        )

        try fixture.command.setShortcut(replacement, for: .stopSelectedTask)
        #expect(fixture.store.shortcut(for: .stopSelectedTask) == replacement)

        try fixture.command.setShortcut(nil, for: .stopSelectedTask)
        #expect(fixture.store.shortcut(for: .stopSelectedTask) == nil)
        #expect(
            fixture.defaults.object(
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            ) == nil
        )
    }

    @Test
    func resetAllRemovesOverridesAndRestoresDefaults() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        try fixture.command.setShortcut(nil, for: .addTime)
        try fixture.command.setShortcut(
            .init(.b, modifiers: [.command, .option]),
            for: .refreshData
        )

        fixture.command.resetAll()

        for action in MacKeyboardShortcutAction.allCases {
            #expect(fixture.store.shortcut(for: action) == action.defaultShortcut)
        }
        #expect(
            fixture.defaults.object(
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            ) == nil
        )
    }

    @Test
    func corruptAndOversizedPayloadsFallBackWithoutMutatingDefaults() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let corrupt = Data("not-a-shortcut".utf8)
        let oversized = Data(
            repeating: 0x41,
            count: UserDefaultsMacKeyboardShortcutPreferenceStore.maximumPayloadByteCount + 1
        )
        fixture.defaults.set(
            corrupt,
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        )
        #expect(
            fixture.store.shortcut(for: .addTime) ==
                MacKeyboardShortcutAction.addTime.defaultShortcut
        )
        #expect(
            fixture.defaults.data(
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            ) == corrupt
        )

        fixture.defaults.set(
            oversized,
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        )
        #expect(
            fixture.store.shortcut(for: .refreshData) ==
                MacKeyboardShortcutAction.refreshData.defaultShortcut
        )
        #expect(
            fixture.defaults.data(
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            ) == oversized
        )
    }

    @Test
    func invalidSemanticPayloadFallsBackWithoutRewritingStoredBytes() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let invalidPayloads = [
            MacKeyboardShortcutPayload(overrides: [
                MacKeyboardShortcutAction.addTime.rawValue: .custom(
                    .init(.n, modifiers: [.command])
                ),
            ]),
            MacKeyboardShortcutPayload(overrides: [
                MacKeyboardShortcutAction.addTime.rawValue: .custom(.init(.y)),
            ]),
            MacKeyboardShortcutPayload(overrides: [
                MacKeyboardShortcutAction.addTime.rawValue: .custom(
                    .init(.b, modifiers: [.command, .option])
                ),
                MacKeyboardShortcutAction.stopSelectedTask.rawValue: .custom(
                    .init(.b, modifiers: [.command, .option])
                ),
            ]),
        ]

        for payload in invalidPayloads {
            let data = try JSONEncoder().encode(payload)
            fixture.defaults.set(
                data,
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            )

            for action in MacKeyboardShortcutAction.allCases {
                #expect(
                    fixture.store.shortcut(for: action) ==
                        action.defaultShortcut
                )
            }
            #expect(
                fixture.defaults.data(
                    forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
                ) == data
            )
        }
    }

    @Test
    func duplicateShortcutIsRejectedWithoutChangingEitherAction() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let existing = try #require(fixture.store.shortcut(for: .addTime))

        #expect(
            throws: MacKeyboardShortcutValidationError.duplicate(.addTime)
        ) {
            try fixture.command.setShortcut(existing, for: .startPomodoro)
        }
        #expect(fixture.store.shortcut(for: .addTime) == existing)
        #expect(
            fixture.store.shortcut(for: .startPomodoro) ==
                MacKeyboardShortcutAction.startPomodoro.defaultShortcut
        )
    }

    @Test
    func duplicateLookupExcludesTheActionBeingEdited() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let settings = MacKeyboardShortcutSettings(command: fixture.command)
        let addTimeShortcut = try #require(settings.shortcut(for: .addTime))

        #expect(
            settings.conflictingAction(
                for: addTimeShortcut,
                excluding: .addTime
            ) == nil
        )
        #expect(
            settings.conflictingAction(
                for: addTimeShortcut,
                excluding: .refreshData
            ) == .addTime
        )
    }

    @Test
    func rejectedSettingsChangeKeepsValueAndRevisionStable() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let settings = MacKeyboardShortcutSettings(command: fixture.command)
        let before = settings.shortcut(for: .startPomodoro)
        let beforeRevision = settings.revision
        let duplicate = try #require(settings.shortcut(for: .addTime))

        #expect(
            settings.setShortcut(duplicate, for: .startPomodoro) == false
        )
        #expect(settings.shortcut(for: .startPomodoro) == before)
        #expect(settings.revision == beforeRevision)
    }

    @Test
    func reservedStandardShortcutIsRejectedWithoutWriting() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }
        let before = fixture.store.shortcut(for: .addTime)

        #expect(throws: MacKeyboardShortcutValidationError.reserved) {
            try fixture.command.setShortcut(
                .init(.n, modifiers: [.command]),
                for: .addTime
            )
        }
        #expect(fixture.store.shortcut(for: .addTime) == before)
        #expect(
            fixture.defaults.object(
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            ) == nil
        )
    }

    @Test
    func unmodifiedLetterIsRejectedAtTheDurableCommandBoundary() throws {
        let fixture = try makeFixture()
        defer { fixture.clear() }

        #expect(throws: MacKeyboardShortcutValidationError.unsupported) {
            try fixture.command.setShortcut(
                .init(.y),
                for: .addTime
            )
        }
        #expect(
            fixture.store.shortcut(for: .addTime) ==
                MacKeyboardShortcutAction.addTime.defaultShortcut
        )
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "MacKeyboardShortcutPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = UserDefaultsMacKeyboardShortcutPreferenceStore(defaults: defaults)
        let command = MacKeyboardShortcutPreferenceCommand(store: store)
        return Fixture(
            suiteName: suiteName,
            defaults: defaults,
            store: store,
            command: command
        )
    }

    private struct Fixture {
        let suiteName: String
        let defaults: UserDefaults
        let store: UserDefaultsMacKeyboardShortcutPreferenceStore
        let command: MacKeyboardShortcutPreferenceCommand

        func clear() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
#endif
