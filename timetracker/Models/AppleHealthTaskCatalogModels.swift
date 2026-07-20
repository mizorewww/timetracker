import Foundation

nonisolated enum AppleHealthTaskCategoryRole: Hashable, Sendable {
    case exercise
    case daily
}

nonisolated enum AppleHealthTaskRole: Hashable, Sendable {
    case workout(AppleHealthWorkoutKind)
    case sleep

    var categoryRole: AppleHealthTaskCategoryRole {
        switch self {
        case .workout:
            .exercise
        case .sleep:
            .daily
        }
    }
}

nonisolated struct AppleHealthTaskCategoryDefinition: Equatable, Sendable {
    let role: AppleHealthTaskCategoryRole
    let id: UUID
    let titleLocalizationKey: String
    let iconName: String
    let colorHex: String
    let sortOrder: Double
}

nonisolated struct AppleHealthTaskDefinition: Equatable, Sendable {
    let role: AppleHealthTaskRole
    let id: UUID
    let categoryID: UUID
    let categoryAssignmentID: UUID
    let titleLocalizationKey: String
    let iconName: String
    let colorHex: String
    let sortOrder: Double
}

nonisolated struct AppleHealthTaskCatalogPlan: Equatable, Sendable {
    let categories: [AppleHealthTaskCategoryDefinition]
    let tasks: [AppleHealthTaskDefinition]
}

nonisolated enum AppleHealthTaskCatalog {
    static let seedTimestamp = Date(timeIntervalSinceReferenceDate: 0)
    static let allRoles: Set<AppleHealthTaskRole> = Set(
        AppleHealthWorkoutKind.allCases.map(AppleHealthTaskRole.workout)
    ).union([.sleep])
    static let syncOnlyTaskIDs = Set(allRoles.map { taskDefinition(for: $0).id })

    static func plan(
        for roles: Set<AppleHealthTaskRole>
    ) -> AppleHealthTaskCatalogPlan {
        let tasks = roles.map(taskDefinition).sorted {
            let lhsCategory = categoryDefinition(
                for: $0.role.categoryRole
            )
            let rhsCategory = categoryDefinition(
                for: $1.role.categoryRole
            )
            if lhsCategory.sortOrder != rhsCategory.sortOrder {
                return lhsCategory.sortOrder < rhsCategory.sortOrder
            }
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        let categoryRoles = Set(tasks.map(\.role.categoryRole))
        let categories = categoryRoles.map(categoryDefinition).sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        return AppleHealthTaskCatalogPlan(categories: categories, tasks: tasks)
    }

    static func categoryDefinition(
        for role: AppleHealthTaskCategoryRole
    ) -> AppleHealthTaskCategoryDefinition {
        switch role {
        case .exercise:
            AppleHealthTaskCategoryDefinition(
                role: role,
                id: id("A1100000-0000-4000-8000-000000000001"),
                titleLocalizationKey: "health.timeline.exerciseCategory",
                iconName: "figure.run",
                colorHex: "FF3B30",
                sortOrder: 9_000
            )
        case .daily:
            AppleHealthTaskCategoryDefinition(
                role: role,
                id: id("A1100000-0000-4000-8000-000000000002"),
                titleLocalizationKey: "health.timeline.dailyCategory",
                iconName: "calendar",
                colorHex: "5856D6",
                sortOrder: 9_010
            )
        }
    }

    static func taskDefinition(
        for role: AppleHealthTaskRole
    ) -> AppleHealthTaskDefinition {
        let category = categoryDefinition(for: role.categoryRole)
        let presentation = taskPresentation(for: role)
        return AppleHealthTaskDefinition(
            role: role,
            id: id("A1200000-0000-4000-8000-\(presentation.idSuffix)"),
            categoryID: category.id,
            categoryAssignmentID: id(
                "A1300000-0000-4000-8000-\(presentation.idSuffix)"
            ),
            titleLocalizationKey: presentation.titleLocalizationKey,
            iconName: presentation.iconName,
            colorHex: category.colorHex,
            sortOrder: 9_000 + Double(presentation.sortIndex * 10)
        )
    }

    private static func taskPresentation(
        for role: AppleHealthTaskRole
    ) -> (idSuffix: String, sortIndex: Int, titleLocalizationKey: String, iconName: String) {
        switch role {
        case .workout(.walking):
            ("000000000001", 1, "health.timeline.workout.walking", "figure.walk")
        case .workout(.running):
            ("000000000002", 2, "health.timeline.workout.running", "figure.run")
        case .workout(.cycling):
            ("000000000003", 3, "health.timeline.workout.cycling", "bicycle")
        case .workout(.swimming):
            ("000000000004", 4, "health.timeline.workout.swimming", "figure.pool.swim")
        case .workout(.strengthTraining):
            ("000000000005", 5, "health.timeline.workout.strengthTraining", "dumbbell.fill")
        case .workout(.highIntensityIntervalTraining):
            ("000000000006", 6, "health.timeline.workout.highIntensityIntervalTraining", "bolt.heart.fill")
        case .workout(.yoga):
            ("000000000007", 7, "health.timeline.workout.yoga", "figure.yoga")
        case .workout(.hiking):
            ("000000000008", 8, "health.timeline.workout.hiking", "figure.hiking")
        case .workout(.rowing):
            ("000000000009", 9, "health.timeline.workout.rowing", "figure.rower")
        case .workout(.dance):
            ("000000000010", 10, "health.timeline.workout.dance", "figure.dance")
        case .workout(.other):
            ("000000000011", 11, "health.timeline.workout.other", "figure.mixed.cardio")
        case .sleep:
            ("000000000012", 1, "health.task.sleep", "bed.double.fill")
        }
    }

    private static func id(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

extension AppleHealthTimelineItem {
    nonisolated var taskRole: AppleHealthTaskRole? {
        subject.appleHealthTaskRole
    }
}

extension TimelineEntrySubject {
    nonisolated var appleHealthTaskRole: AppleHealthTaskRole? {
        switch self {
        case .task:
            nil
        case let .appleHealthWorkout(kind):
            .workout(kind)
        case .appleHealthSleep:
            .sleep
        }
    }
}
