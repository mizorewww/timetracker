import Foundation
import Testing
@testable import timetracker

struct CoreTaskIdentityPresentationTests {
    @Test
    func textContextsUseHierarchyWithoutRepeatingTheTaskTitle() {
        let presentation = TaskIdentityPresentation(
            id: UUID(),
            title: "Review",
            parentPath: "Work / Release",
            fullPath: "Work / Release / Review",
            visual: TaskVisualPresentation(iconName: "doc.text", colorHex: "0A84FF")
        )

        #expect(
            presentation.text(for: .hierarchical) ==
                TaskIdentityText(primary: "Review", secondary: nil)
        )
        #expect(
            presentation.text(for: .standard) ==
                TaskIdentityText(primary: "Review", secondary: "Work / Release")
        )
        #expect(
            presentation.text(for: .compact) ==
                TaskIdentityText(primary: "Work / Release / Review", secondary: nil)
        )
    }

    @Test
    func rootIdentityNeverManufacturesAParentSubtitle() {
        let presentation = TaskIdentityPresentation(
            id: UUID(),
            title: "Root",
            parentPath: "",
            fullPath: "Root",
            visual: TaskVisualPresentation(iconName: nil, colorHex: nil)
        )

        #expect(presentation.parentPath == nil)
        #expect(
            presentation.text(for: .standard) ==
                TaskIdentityText(primary: "Root", secondary: nil)
        )
        #expect(
            presentation.text(for: .compact) ==
                TaskIdentityText(primary: "Root", secondary: nil)
        )
    }

    @Test
    func invalidVisualDataUsesTheCanonicalTaskFallback() {
        let visual = TaskVisualPresentation(
            iconName: "not.a.real.symbol",
            colorHex: "not-a-color"
        )

        #expect(visual.symbolName == "checkmark.circle")
        #expect(visual.colorHex == "1677FF")
        #expect(TaskVisualPresentation.defaultSymbolName == "checkmark.circle")
        #expect(TaskVisualPresentation.defaultColorHex == "1677FF")
    }

    @Test @MainActor
    func indexedAdapterPreservesSlashesAndDisambiguatesMatchingTitles() throws {
        let firstRoot = TaskNode(
            title: "Product / iOS",
            parentID: nil,
            deviceID: "test",
            colorHex: "0A84FF",
            iconName: "folder"
        )
        let secondRoot = TaskNode(
            title: "Product / macOS",
            parentID: nil,
            deviceID: "test",
            colorHex: "5E5CE6",
            iconName: "folder"
        )
        let firstReview = TaskNode(
            title: "Review / Ship",
            parentID: firstRoot.id,
            deviceID: "test",
            colorHex: "0A84FF",
            iconName: "doc.text"
        )
        let secondReview = TaskNode(
            title: "Review / Ship",
            parentID: secondRoot.id,
            deviceID: "test",
            colorHex: "5E5CE6",
            iconName: "doc.text"
        )
        let indexes = TaskTreeService().indexes(
            tasks: [firstRoot, secondRoot, firstReview, secondReview]
        )

        let first = try #require(indexes.taskIdentityPresentation(for: firstReview.id))
        let second = try #require(indexes.taskIdentityPresentation(for: secondReview.id))

        #expect(first.title == "Review / Ship")
        #expect(first.parentPath == "Product / iOS")
        #expect(first.fullPath == "Product / iOS / Review / Ship")
        #expect(second.title == first.title)
        #expect(second.parentPath == "Product / macOS")
        #expect(second.fullPath == "Product / macOS / Review / Ship")
        #expect(first.text(for: .standard) != second.text(for: .standard))
    }

    @Test @MainActor
    func storeAdapterReadsTheRebuiltTaskIndex() {
        let store = makeTestStore()
        let root = TaskNode(title: "Work", parentID: nil, deviceID: "test")
        let child = TaskNode(
            title: "Planning",
            parentID: root.id,
            deviceID: "test",
            colorHex: "0A84FF",
            iconName: "calendar"
        )
        store.tasks = [root, child]

        let presentation = store.taskIdentityPresentation(for: child)

        #expect(presentation.id == child.id)
        #expect(presentation.parentPath == "Work")
        #expect(presentation.fullPath == "Work / Planning")
        #expect(presentation.visual == TaskVisualPresentation(iconName: "calendar", colorHex: "0A84FF"))
    }
}
