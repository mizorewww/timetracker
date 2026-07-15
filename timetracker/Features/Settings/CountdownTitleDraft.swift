import Foundation

enum CountdownTitleDraftError: Equatable {
    case validation(CountdownTitleValidationError)
    case saveFailed

    var localizedMessage: String {
        switch self {
        case let .validation(error):
            error.localizedDescription
        case .saveFailed:
            AppStrings.localized("settings.countdown.title.error.saveFailed")
        }
    }
}

struct CountdownTitleDraft: Equatable {
    var text: String {
        didSet {
            if text != oldValue {
                error = nil
            }
        }
    }

    private(set) var error: CountdownTitleDraftError?
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
        } catch let validationError as CountdownTitleValidationError {
            error = .validation(validationError)
            return false
        } catch {
            self.error = .saveFailed
            return false
        }

        guard normalizedTitle != persistedTitle else {
            text = normalizedTitle
            error = nil
            return true
        }
        guard save(normalizedTitle) else {
            error = .saveFailed
            return false
        }

        persistedTitle = normalizedTitle
        text = normalizedTitle
        error = nil
        return true
    }
}
