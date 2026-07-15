import SwiftData

@MainActor
private enum ModelContextMutationState {
    static var depthByContext: [ObjectIdentifier: Int] = [:]
}

@MainActor
extension ModelContext {
    /// Saves immediately for standalone repository calls, but defers nested
    /// command saves while a store-level mutation is being committed atomically.
    func saveAfterMutationStep() throws {
        guard ModelContextMutationState.depthByContext[ObjectIdentifier(self), default: 0] == 0 else {
            return
        }
        try save()
    }

    /// Commits all nested repository and command changes with one final save.
    /// A thrown command or final save failure rolls back the complete unit of work.
    func performAtomicMutation<Result>(_ action: () throws -> Result) throws -> Result {
        let identifier = ObjectIdentifier(self)
        let previousDepth = ModelContextMutationState.depthByContext[identifier, default: 0]
        ModelContextMutationState.depthByContext[identifier] = previousDepth + 1
        defer {
            if previousDepth == 0 {
                ModelContextMutationState.depthByContext.removeValue(forKey: identifier)
            } else {
                ModelContextMutationState.depthByContext[identifier] = previousDepth
            }
        }

        do {
            let result = try action()
            if previousDepth == 0 {
                try save()
            }
            return result
        } catch {
            if previousDepth == 0 {
                rollback()
            }
            throw error
        }
    }
}
