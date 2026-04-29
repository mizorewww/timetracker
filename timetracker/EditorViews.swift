import SwiftUI

struct TaskEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskEditorDraft

    var body: some View {
        TaskEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.taskEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                if store.saveTaskDraft(draft) {
                    dismiss()
                }
            }
        )
        .platformSheetFrame(width: 520, height: 620)
        .presentationDetents([.large])
    }
}

struct TaskEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: TaskEditorDraft
    @State private var isSymbolPickerPresented = false
    @FocusState private var focusedChecklistDraftID: UUID?
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> Void

    private let colors = ["1677FF", "16A34A", "7C3AED", "F97316", "EF4444", "0EA5E9", "64748B"]

    init(store: TimeTrackerStore, initialDraft: TaskEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (TaskEditorDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section(AppStrings.localized("editor.task.info")) {
                        TextField(AppStrings.localized("editor.task.name"), text: $draft.title)

                        TaskStatusPicker(selection: $draft.status)

                        Picker(AppStrings.localized("editor.task.parent"), selection: parentBinding) {
                            Text(.app("editor.task.rootLevel")).tag(Optional<UUID>.none)
                            ForEach(store.validParentTasks(for: draft.taskID), id: \.id) { task in
                                Text(indentedTitle(task)).tag(Optional(task.id))
                            }
                        }

                        HStack {
                            Text(.app("editor.task.symbolColor"))
                            Spacer()
                            Button {
                                isSymbolPickerPresented = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: draft.iconName)
                                        .foregroundStyle(Color(hex: draft.colorHex) ?? .blue)
                                    Text(.app("common.choose"))
                                }
                            }
                            #if os(macOS)
                            .popover(isPresented: $isSymbolPickerPresented) {
                                SymbolAndColorPicker(
                                    symbols: SymbolCatalog.symbolNames,
                                    searchKeywords: SymbolCatalog.searchKeywords,
                                    colors: colors,
                                    symbolName: $draft.iconName,
                                    colorHex: $draft.colorHex
                                )
                                .frame(width: 460, height: 520)
                            }
                            #endif
                        }
                    }

                    Section(AppStrings.localized("editor.task.plan")) {
                        Stepper(value: estimatedMinutesBinding, in: 0...600, step: 15) {
                            LabeledContent(AppStrings.localized("editor.task.estimate"), value: draft.estimatedMinutes.map { String(format: AppStrings.localized("common.minutes"), $0) } ?? AppStrings.localized("editor.task.notSet"))
                        }

                        Toggle(AppStrings.localized("editor.task.setDue"), isOn: $draft.hasDueDate)
                        if draft.hasDueDate {
                            DatePicker(AppStrings.localized("editor.task.due"), selection: $draft.dueAt, displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    Section {
                        if draft.checklistItems.isEmpty {
                            Text(.app("editor.checklist.empty"))
                                .foregroundStyle(.secondary)
                        }

                        ForEach(Array(orderedChecklistIndices.enumerated()), id: \.element) { visualIndex, index in
                            ChecklistEditorRow(
                                item: $draft.checklistItems[index],
                                canMoveUp: visualIndex > 0,
                                canMoveDown: visualIndex < orderedChecklistIndices.count - 1,
                                moveUp: { moveChecklistItem(atVisualIndex: visualIndex, direction: -1) },
                                moveDown: { moveChecklistItem(atVisualIndex: visualIndex, direction: 1) },
                                delete: { draft.checklistItems.remove(at: index) },
                                focus: $focusedChecklistDraftID,
                                submit: { addChecklistItem(afterVisualIndex: visualIndex) }
                            )
                        }

                        Button {
                            addChecklistItem()
                        } label: {
                            Label(AppStrings.localized("editor.checklist.add"), systemImage: "plus")
                        }
                    } header: {
                        Text(.app("editor.checklist.title"))
                    } footer: {
                        Text(.app("editor.checklist.footer"))
                    }

                    Section(AppStrings.localized("editor.task.notes")) {
                        TextEditor(text: $draft.notes)
                            .frame(minHeight: 88)
                    }
                }
                .formStyle(.grouped)
            }
            .navigationTitle(draft.taskID == nil ? AppStrings.localized("editor.task.newTitle") : AppStrings.localized("editor.task.editTitle"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
            }
            #if os(iOS)
            .sheet(isPresented: $isSymbolPickerPresented) {
                NavigationStack {
                    SymbolAndColorPicker(
                        symbols: SymbolCatalog.symbolNames,
                        searchKeywords: SymbolCatalog.searchKeywords,
                        colors: colors,
                        symbolName: $draft.iconName,
                        colorHex: $draft.colorHex
                    )
                    .navigationTitle(AppStrings.localized("editor.symbol.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppStrings.done) {
                                isSymbolPickerPresented = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
            #endif
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var orderedChecklistIndices: [Int] {
        draft.checklistItems.indices.sorted { lhs, rhs in
            let left = draft.checklistItems[lhs]
            let right = draft.checklistItems[rhs]
            if left.isCompleted != right.isCompleted {
                return !left.isCompleted
            }
            return lhs < rhs
        }
    }

    private var parentTitle: String {
        guard let parentID = draft.parentID, let task = store.task(for: parentID) else {
            return AppStrings.localized("editor.task.rootTitle")
        }
        return store.path(for: task)
    }

    private var parentBinding: Binding<UUID?> {
        Binding {
            draft.parentID
        } set: { value in
            draft.parentID = value
        }
    }

    private var estimatedMinutesBinding: Binding<Int> {
        Binding {
            draft.estimatedMinutes ?? 0
        } set: { value in
            draft.estimatedMinutes = value == 0 ? nil : value
        }
    }

    private func indentedTitle(_ task: TaskNode) -> String {
        String(repeating: "  ", count: task.depth) + task.title
    }

    private func moveChecklistItem(from source: Int, to destination: Int) {
        guard draft.checklistItems.indices.contains(source),
              draft.checklistItems.indices.contains(destination) else {
            return
        }
        draft.checklistItems.swapAt(source, destination)
    }

    private func moveChecklistItem(atVisualIndex visualIndex: Int, direction: Int) {
        let ordered = orderedChecklistIndices
        let targetVisualIndex = visualIndex + direction
        guard ordered.indices.contains(visualIndex),
              ordered.indices.contains(targetVisualIndex) else {
            return
        }
        moveChecklistItem(from: ordered[visualIndex], to: ordered[targetVisualIndex])
    }

    private func addChecklistItem(afterVisualIndex visualIndex: Int? = nil) {
        let newItem = ChecklistEditorDraft()
        if let visualIndex {
            let insertionIndex = min(visualIndex + 1, draft.checklistItems.count)
            draft.checklistItems.insert(newItem, at: insertionIndex)
        } else {
            draft.checklistItems.append(newItem)
        }
        focusedChecklistDraftID = newItem.id
    }
}

private struct TaskStatusPicker: View {
    @Binding var selection: TaskStatus

    var body: some View {
        Picker(AppStrings.localized("editor.task.status"), selection: $selection) {
            ForEach(TaskStatus.editableCases, id: \.self) { status in
                TaskStatusPickerOption(status: status)
                    .tag(status)
            }
        }
        .pickerStyle(.inline)
    }
}

private struct TaskStatusPickerOption: View {
    let status: TaskStatus

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.displayName)
                Text(status.exampleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: status.symbolName)
                .foregroundStyle(Color(hex: status.colorHex) ?? .secondary)
        }
    }
}

private struct ChecklistEditorRow: View {
    @Binding var item: ChecklistEditorDraft
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    let focus: FocusState<UUID?>.Binding
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ChecklistCompletionButton(isCompleted: item.isCompleted) {
                withAnimation(.snappy(duration: 0.22)) {
                    item.isCompleted.toggle()
                }
            }

            TextField(AppStrings.localized("editor.checklist.itemPlaceholder"), text: $item.title)
                .textFieldStyle(.plain)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .focused(focus, equals: item.id)
                .submitLabel(.next)
                .onSubmit(submit)

            Menu {
                Button {
                    moveUp()
                } label: {
                    Label(AppStrings.localized("common.moveUp"), systemImage: "chevron.up")
                }
                .disabled(!canMoveUp)

                Button {
                    moveDown()
                } label: {
                    Label(AppStrings.localized("common.moveDown"), systemImage: "chevron.down")
                }
                .disabled(!canMoveDown)

                Divider()

                Button(role: .destructive) {
                    delete()
                } label: {
                    Label(AppStrings.delete, systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }
}

struct ManualTimeSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: ManualTimeDraft

    var body: some View {
        ManualTimePanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.manualTimeDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveManualTimeDraft(draft)
                dismiss()
            }
        )
        .platformSheetFrame(width: 620, height: 560)
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: SegmentEditorDraft

    var body: some View {
        SegmentEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.segmentEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveSegmentDraft(draft)
                dismiss()
            },
            onDelete: { segmentID in
                store.deleteSegment(segmentID)
                dismiss()
            }
        )
        .platformSheetFrame(width: 620, height: 620)
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: SegmentEditorDraft
    let onCancel: () -> Void
    let onSave: (SegmentEditorDraft) -> Void
    let onDelete: (UUID) -> Void

    init(
        store: TimeTrackerStore,
        initialDraft: SegmentEditorDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SegmentEditorDraft) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("segment.assignment")) {
                    Picker(AppStrings.localized("segment.task"), selection: taskBinding) {
                        Text(.app("segment.choose")).tag(Optional<UUID>.none)
                        ForEach(store.tasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }

                    LabeledContent(AppStrings.localized("segment.source"), value: draft.source.displayName)
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(AppStrings.localized("segment.start"), selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle(AppStrings.localized("segment.active"), isOn: $draft.isActive)
                    if !draft.isActive {
                        DatePicker(AppStrings.localized("segment.end"), selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                        LabeledContent(AppStrings.localized("segment.duration")) {
                            Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                        }
                    }
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(AppStrings.localized("segment.note.placeholder"), text: $draft.note)
                }

                Section {
                    Button(role: .destructive) {
                        onDelete(draft.segmentID)
                    } label: {
                        Label(AppStrings.localized("segment.softDelete"), systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppStrings.localized("segment.edit.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.taskID == nil || (!draft.isActive && draft.endedAt <= draft.startedAt))
                }
            }
        }
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }
}

struct SymbolAndColorPicker: View {
    let symbols: [String]
    let searchKeywords: [String: [String]]
    let colors: [String]
    @Binding var symbolName: String
    @Binding var colorHex: String
    @State private var searchText = ""

    private var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return symbols }
        return symbols.filter { symbol in
            symbol.localizedCaseInsensitiveContains(searchText) ||
            (searchKeywords[symbol]?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(.app("editor.symbol.sfSymbols"))
                    .font(.headline)
                Spacer()
                Text("\(filteredSymbols.count) / \(symbols.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField(AppStrings.localized("editor.symbol.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .foregroundStyle(symbolName == symbol ? .white : (Color(hex: colorHex) ?? .blue))
                                .frame(width: 38, height: 38)
                                .background(symbolName == symbol ? (Color(hex: colorHex) ?? .blue) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            Text(.app("editor.symbol.color"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 26, height: 26)
                            .overlay {
                                if colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum SymbolCatalog {
    static let symbolNames: [String] = {
        let loaded = loadSymbolOrder()
        if !loaded.isEmpty {
            return loaded
        }
        return fallbackSymbols
    }()

    static let searchKeywords: [String: [String]] = loadSearchKeywords()

    private static func loadSymbolOrder() -> [String] {
        for url in resourceURLs(fileName: "symbol_order", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let names = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
                  !names.isEmpty else {
                continue
            }
            return Array(NSOrderedSet(array: names).compactMap { $0 as? String })
        }
        return []
    }

    private static func loadSearchKeywords() -> [String: [String]] {
        for url in resourceURLs(fileName: "symbol_search", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let keywords = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
                continue
            }
            return keywords
        }
        return [:]
    }

    private static func resourceURLs(fileName: String, extension ext: String) -> [URL] {
        let bundled: [URL] = [
            fileName == "symbol_order" ? Bundle.main.url(forResource: "SFSymbolOrder", withExtension: ext) : nil,
            fileName == "symbol_search" ? Bundle.main.url(forResource: "SFSymbolSearch", withExtension: ext) : nil
        ].compactMap(\.self)

        let system = [
            "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/CoreServices/CoreGlyphs.bundle/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphsPrivate.bundle/Contents/Resources"
        ].map {
            URL(fileURLWithPath: $0).appendingPathComponent(fileName).appendingPathExtension(ext)
        }

        return bundled + system
    }

    private static let fallbackSymbols = [
        "checkmark.circle", "folder", "briefcase", "book", "macwindow",
        "square.grid.2x2", "chevron.left.forwardslash.chevron.right",
        "person.2", "pencil.and.list.clipboard", "target", "calendar",
        "clock", "timer", "paintbrush", "chart.bar", "doc.text",
        "hammer", "lightbulb", "paperplane", "terminal", "keyboard",
        "graduationcap", "heart", "house", "cart", "creditcard",
        "briefcase.fill", "star", "tag", "tray", "archivebox", "trash",
        "play.fill", "pause.fill", "stop.fill", "plus", "magnifyingglass"
    ]
}

struct ManualTimePanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: ManualTimeDraft
    let onCancel: () -> Void
    let onSave: (ManualTimeDraft) -> Void

    init(store: TimeTrackerStore, initialDraft: ManualTimeDraft, onCancel: @escaping () -> Void, onSave: @escaping (ManualTimeDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppStrings.localized("segment.assignment")) {
                    Picker(AppStrings.localized("segment.task"), selection: taskBinding) {
                        Text(.app("segment.choose")).tag(Optional<UUID>.none)
                        ForEach(store.tasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }
                }

                Section(AppStrings.localized("segment.time")) {
                    DatePicker(AppStrings.localized("segment.start"), selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker(AppStrings.localized("segment.end"), selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                    LabeledContent(AppStrings.localized("segment.duration")) {
                        Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                    }
                }

                Section(AppStrings.localized("segment.notes")) {
                    TextField(AppStrings.localized("manual.note.placeholder"), text: $draft.note)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppStrings.localized("manual.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.taskID == nil || draft.endedAt <= draft.startedAt)
                }
            }
        }
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }
}
