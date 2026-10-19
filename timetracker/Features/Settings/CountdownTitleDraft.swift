import Foundation

struct CountdownTitleDraft: Equatable {
    var text: String {
        didSet {
            if text != oldValue {
                error = nil
            }
        }
    }

    /// Why the edit was not saved. A failed save keeps the edit and is reported
    /// by the caller, so only validation problems are shown in place.
    private(set) var error: CountdownTitleValidationError?
    private var persistedTitle: String

    init(persistedTitle: String) {
        text = persistedTitle
        self.persistedTitle = persistedTitle
    }

    var isDirty: Bool {
        text != persistedTitle
    }

    mutating func reconcile(persistedTitle newTitle: String) {
        guard newTitle != persistedTitle else { return }
        let hadUnsavedChanges = isDirty
        persistedTitle = newTitle
        if !hadUnsavedChanges {
            text = newTitle
        }
    }

    @discardableResult
    mutating func commit(using save: (String) -> Bool) -> Bool {
        let normalizedTitle: String
        do {
            normalizedTitle = try CountdownTitlePolicy.normalized(text)
        } catch {
            self.error = error as? CountdownTitleValidationError ?? .empty
            return false
        }

        guard normalizedTitle != persistedTitle else {
            text = normalizedTitle
            error = nil
            return true
        }
        guard save(normalizedTitle) else { return false }

        persistedTitle = normalizedTitle
        text = normalizedTitle
        error = nil
        return true
    }
}
