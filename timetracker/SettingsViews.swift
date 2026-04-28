import SwiftUI
import UniformTypeIdentifiers

struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let text = String(data: data, encoding: .utf8) {
            self.text = text
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct SettingsView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var isResetConfirmationPresented = false
    @State private var isClearConfirmationPresented = false
    @State private var isOptimizeConfirmationPresented = false
    @State private var isExportPresented = false
    @State private var isCheckingSync = false
    @State private var syncCheckMessage: String?
    @State private var databaseOptimizationMessage: String?

    private var minuteFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 480
        return formatter
    }

    var body: some View {
        Form {
            Section {
                Picker(AppStrings.localized("settings.appearance"), selection: preferredColorSchemeBinding) {
                    Text(.app("settings.appearance.system")).tag("system")
                    Text(.app("settings.appearance.light")).tag("light")
                    Text(.app("settings.appearance.dark")).tag("dark")
                }
                .pickerStyle(.segmented)

                Toggle(AppStrings.localized("settings.allowParallelTimers"), isOn: allowParallelTimersBinding)
                Toggle(AppStrings.localized("settings.showWallGross"), isOn: showGrossAndWallTogetherBinding)
            } header: {
                SettingsHeader(symbol: "paintbrush.pointed.fill", title: AppStrings.localized("settings.displayTiming"))
            } footer: {
                Text(.app("settings.displayTiming.footer"))
            }

            Section {
                Picker(AppStrings.localized("settings.defaultMode"), selection: pomodoroDefaultModeBinding) {
                    ForEach(PomodoroPreset.allCases) { preset in
                        Text(preset.title).tag(preset.rawValue)
                    }
                }
                .onChange(of: store.preferences.pomodoroDefaultMode) { _, newValue in
                    guard let preset = PomodoroPreset(rawValue: newValue), preset != .custom else { return }
                    store.setDefaultFocusMinutes(preset.focusMinutes)
                    store.setDefaultBreakMinutes(preset.breakMinutes)
                }

                TextField(AppStrings.localized("settings.focusMinutes"), value: defaultFocusMinutesBinding, formatter: minuteFormatter)
                TextField(AppStrings.localized("settings.breakMinutes"), value: defaultBreakMinutesBinding, formatter: minuteFormatter)
                TextField(AppStrings.localized("settings.defaultRounds"), value: defaultPomodoroRoundsBinding, formatter: minuteFormatter)
            } header: {
                SettingsHeader(symbol: "timer", title: AppStrings.pomodoro)
            } footer: {
                Text(.app("settings.pomodoro.footer"))
            }

            Section {
                if store.countdownEvents.isEmpty {
                    Text(.app("settings.countdown.empty"))
                        .foregroundStyle(.secondary)
                }

                ForEach(store.countdownEvents) { event in
                    CountdownEventSettingsRow(
                        event: event,
                        onChangeTitle: { title in
                            store.updateCountdownEvent(event, title: title)
                        },
                        onChangeDate: { date in
                            store.updateCountdownEvent(event, date: date)
                        },
                        onDelete: {
                            store.deleteCountdownEvent(event)
                        }
                    )
                }

                Button {
                    store.addCountdownEvent()
                } label: {
                    Label(AppStrings.localized("settings.countdown.add"), systemImage: "plus")
                }
            } header: {
                SettingsHeader(symbol: "calendar.badge.clock", title: AppStrings.localized("settings.countdown"))
            } footer: {
                Text(.app("settings.countdown.footer"))
            }

            Section {
                Button {
                    isExportPresented = true
                } label: {
                    Label(AppStrings.localized("settings.exportCSV"), systemImage: "square.and.arrow.down")
                }

                Button {
                    store.presentManualTime()
                } label: {
                    Label(AppStrings.addTime, systemImage: "calendar.badge.plus")
                }

                Button(role: .destructive) {
                    isOptimizeConfirmationPresented = true
                } label: {
                    Label(AppStrings.localized("settings.optimizeDatabase"), systemImage: "externaldrive.badge.checkmark")
                }
            } header: {
                SettingsHeader(symbol: "doc.text.fill", title: AppStrings.localized("settings.data"))
            } footer: {
                Text(.app("settings.data.footer"))
            }

            Section {
                Toggle(isOn: cloudSyncEnabledBinding) {
                    Label(AppStrings.localized("settings.icloud"), systemImage: "icloud")
                }

                LabeledContent(
                    AppStrings.localized("settings.currentStorage"),
                    value: store.preferences.cloudSyncEnabled ? (store.syncStatus.isCloudBacked ? "iCloud" : AppStrings.localized("settings.localWillRetryCloud")) : AppStrings.localized("settings.local")
                )

                Button {
                    isCheckingSync = true
                    Task {
                        await store.refreshCloudAccountStatus()
                        syncCheckMessage = store.syncStatus.accountStatus
                        isCheckingSync = false
                    }
                } label: {
                    Label(isCheckingSync ? AppStrings.localized("settings.checking") : AppStrings.localized("settings.checkSync"), systemImage: "arrow.clockwise")
                }
                .disabled(isCheckingSync)

                Button {
                    isCheckingSync = true
                    Task {
                        syncCheckMessage = await store.forceCloudSyncRefresh()
                        isCheckingSync = false
                    }
                } label: {
                    Label(AppStrings.localized("settings.forceSync"), systemImage: "arrow.clockwise.icloud")
                }
                .disabled(isCheckingSync)
            } header: {
                SettingsHeader(symbol: "icloud.fill", title: AppStrings.localized("settings.sync"))
            } footer: {
                Text(.app("settings.sync.footer"))
            }

            Section {
                LabeledContent(AppStrings.tasks, value: "\(store.tasks.count)")
                LabeledContent(AppStrings.localized("settings.timeRecords"), value: "\(store.allSegments.count)")
                LabeledContent(AppStrings.pomodoro, value: "\(store.pomodoroRuns.count)")
                LabeledContent(AppStrings.localized("settings.cloudAccount"), value: store.syncStatus.accountStatus)
                LabeledContent(AppStrings.localized("settings.icloudContainer"), value: store.syncStatus.containerIdentifier)
                Button(AppStrings.localized("settings.rebuildDemoData"), role: .destructive) {
                    isResetConfirmationPresented = true
                }
                Button(AppStrings.localized("settings.clearDemoData"), role: .destructive) {
                    isClearConfirmationPresented = true
                }
            } header: {
                SettingsHeader(symbol: "wrench.and.screwdriver.fill", title: AppStrings.localized("settings.maintenance"))
            }

            Section {
                AboutAppSummary()
                LabeledContent(AppStrings.localized("settings.about.version"), value: AppBuildInfo.versionSummary)
                LabeledContent(AppStrings.localized("settings.about.branch"), value: AppBuildInfo.gitBranch)
                LabeledContent(AppStrings.localized("settings.about.commit"), value: AppBuildInfo.gitCommit + (AppBuildInfo.isDirtyBuild ? " *" : ""))
                LabeledContent(AppStrings.localized("settings.about.built"), value: AppBuildInfo.buildDate)
            } header: {
                SettingsHeader(symbol: "info.circle.fill", title: AppStrings.localized("settings.about"))
            } footer: {
                Text(.app("settings.about.footer"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AppStrings.settings)
        .accessibilityIdentifier("settings.view")
        .fileExporter(
            isPresented: $isExportPresented,
            document: CSVExportDocument(text: store.csvExport()),
            contentType: .commaSeparatedText,
            defaultFilename: "time-tracker-export.csv"
        ) { result in
            if case let .failure(error) = result {
                store.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(AppStrings.localized("dialog.rebuildDemo.title"), isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.rebuildDemo.confirm"), role: .destructive) {
                store.replaceWithDemoData()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.rebuildDemo.message"))
        }
        .confirmationDialog(AppStrings.localized("dialog.clearDemo.title"), isPresented: $isClearConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.clearDemo.confirm"), role: .destructive) {
                store.clearDemoData()
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.clearDemo.message"))
        }
        .confirmationDialog(AppStrings.localized("dialog.optimize.title"), isPresented: $isOptimizeConfirmationPresented, titleVisibility: .visible) {
            Button(AppStrings.localized("dialog.optimize.confirm"), role: .destructive) {
                let removedCount = store.optimizeDatabase()
                databaseOptimizationMessage = removedCount == 0 ? AppStrings.localized("dialog.optimize.none") : String(format: AppStrings.localized("dialog.optimize.removed"), removedCount)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("dialog.optimize.message"))
        }
        .alert(AppStrings.localized("alert.sync.title"), isPresented: syncCheckPresented) {
            Button(AppStrings.localized("common.ok")) {
                syncCheckMessage = nil
            }
        } message: {
            Text(syncCheckMessage ?? "")
        }
        .alert(AppStrings.localized("alert.optimize.title"), isPresented: optimizationMessagePresented) {
            Button(AppStrings.localized("common.ok")) {
                databaseOptimizationMessage = nil
            }
        } message: {
            Text(databaseOptimizationMessage ?? "")
        }
    }

    private var syncCheckPresented: Binding<Bool> {
        Binding {
            syncCheckMessage != nil
        } set: { isPresented in
            if !isPresented {
                syncCheckMessage = nil
            }
        }
    }

    private var optimizationMessagePresented: Binding<Bool> {
        Binding {
            databaseOptimizationMessage != nil
        } set: { isPresented in
            if !isPresented {
                databaseOptimizationMessage = nil
            }
        }
    }

    private var preferredColorSchemeBinding: Binding<String> {
        Binding(
            get: { store.preferences.preferredColorScheme },
            set: { store.setPreferredColorScheme($0) }
        )
    }

    private var pomodoroDefaultModeBinding: Binding<String> {
        Binding(
            get: { store.preferences.pomodoroDefaultMode },
            set: { store.setPomodoroDefaultMode($0) }
        )
    }

    private var defaultFocusMinutesBinding: Binding<Int> {
        Binding(
            get: { store.preferences.defaultFocusMinutes },
            set: { store.setDefaultFocusMinutes($0) }
        )
    }

    private var defaultBreakMinutesBinding: Binding<Int> {
        Binding(
            get: { store.preferences.defaultBreakMinutes },
            set: { store.setDefaultBreakMinutes($0) }
        )
    }

    private var defaultPomodoroRoundsBinding: Binding<Int> {
        Binding(
            get: { store.preferences.defaultPomodoroRounds },
            set: { store.setDefaultPomodoroRounds($0) }
        )
    }

    private var allowParallelTimersBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.allowParallelTimers },
            set: { store.setAllowParallelTimers($0) }
        )
    }

    private var showGrossAndWallTogetherBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.showGrossAndWallTogether },
            set: { store.setShowGrossAndWallTogether($0) }
        )
    }

    private var cloudSyncEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.cloudSyncEnabled },
            set: { store.setCloudSyncEnabled($0) }
        )
    }
}

struct AboutAppSummary: View {
    var body: some View {
        HStack(spacing: 14) {
            AppIconImage()
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppBuildInfo.displayName)
                    .font(.headline)
                Text(String(format: AppStrings.localized("settings.about.versionFormat"), AppBuildInfo.versionSummary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(AppBuildInfo.gitBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbol)
    }
}

struct CountdownEventSettingsRow: View {
    let event: CountdownEvent
    let onChangeTitle: (String) -> Void
    let onChangeDate: (Date) -> Void
    let onDelete: () -> Void

    private var titleBinding: Binding<String> {
        Binding {
            event.title
        } set: { value in
            onChangeTitle(value)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding {
            event.date
        } set: { value in
            onChangeDate(value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(AppStrings.localized("settings.countdown.eventName"), text: titleBinding)
            HStack {
                DatePicker(AppStrings.localized("settings.countdown.date"), selection: dateBinding, displayedComponents: .date)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
