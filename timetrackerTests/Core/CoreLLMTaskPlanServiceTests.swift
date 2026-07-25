import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLLMTaskPlanServiceTests {
    @Test
    func generateMapsFlatReferencesIntoAnEditableDraft() async throws {
        let contentData = try JSONSerialization.data(withJSONObject: [
            "categories": [
                [
                    "reference": " Work ",
                    "title": " Work ",
                    "iconName": "briefcase",
                    "colorHex": "1677FF",
                ],
            ],
            "tasks": [
                [
                    "reference": " ROOT ",
                    "categoryReference": "work",
                    "parentReference": NSNull(),
                    "title": " Plan release ",
                    "notes": " Useful context ",
                    "estimatedMinutes": 25,
                    "iconName": "target",
                    "colorHex": "34C759",
                ],
                [
                    "reference": "child",
                    "categoryReference": NSNull(),
                    "parentReference": "root",
                    "title": "Ship build",
                    "notes": NSNull(),
                    "estimatedMinutes": NSNull(),
                    "iconName": "paperplane",
                    "colorHex": "0A84FF",
                ],
            ],
            "checklistItems": [
                [
                    "reference": "verify",
                    "taskReference": " ROOT ",
                    "title": "Verify tests",
                    "iconName": "checkmark.circle",
                    "colorHex": "1677FF",
                ],
            ],
        ])
        let content = try #require(String(data: contentData, encoding: .utf8))
        let responseData = try Self.chatResponseData(content: content)
        let service = LLMTaskPlanService { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.test")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (responseData, response)
        }

        let draft = try await service.generate(
            request: "Prepare the release",
            instructions: "",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model-1"
        )

        let category = try #require(draft.categories.first)
        let root = try #require(draft.tasks.first { $0.title == "Plan release" })
        let child = try #require(draft.tasks.first { $0.title == "Ship build" })
        #expect(draft.modelID == "model-1")
        #expect(category.title == "Work")
        #expect(root.categoryID == category.id)
        #expect(root.parentID == nil)
        #expect(root.notes == " Useful context ")
        #expect(root.estimatedMinutes == 25)
        #expect(root.quantityGoal == nil)
        #expect(root.dailyRecurrence == nil)
        #expect(root.checklistItems.map(\.title) == ["Verify tests"])
        #expect(child.categoryID == nil)
        #expect(child.parentID == root.id)
        #expect(Set(draft.tasks.map(\.id)).count == 2)
    }

    @Test
    func quantityAndDailyRecurrenceUseValidatedDomainDraftsAndTrustedLocalTime() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Singapore"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 22,
                    hour: 9
                )
            )
        )

        let draft = try LLMTaskPlanService.makeDraft(
            from: Self.payload(tasks: [
                Self.task(
                    "quantity",
                    quantityGoal: .init(
                        targetAmount: 50,
                        unitLabel: " push-ups "
                    )
                ),
                Self.task("daily", recurrenceCadence: "daily"),
                Self.task(
                    "combined",
                    quantityGoal: .init(
                        targetAmount: 10,
                        unitLabel: "pages"
                    ),
                    recurrenceCadence: "daily"
                ),
            ]),
            modelID: "model",
            now: now,
            timeZone: timeZone
        )

        let quantity = try #require(draft.tasks.first { $0.title == "quantity" })
        let daily = try #require(draft.tasks.first { $0.title == "daily" })
        let combined = try #require(draft.tasks.first { $0.title == "combined" })
        #expect(
            quantity.quantityGoal == TaskQuantityGoalDraft(
                targetAmount: 50,
                unitLabel: "push-ups"
            )
        )
        #expect(quantity.dailyRecurrence == nil)
        #expect(daily.quantityGoal == nil)
        #expect(
            daily.dailyRecurrence == TaskDailyRecurrenceDraft(
                isEnabled: true,
                startDayKey: "2026-07-22",
                timeZoneIdentifier: "Asia/Singapore"
            )
        )
        #expect(combined.quantityGoal?.targetAmount == 10)
        #expect(combined.dailyRecurrence?.startDayKey == "2026-07-22")
    }

    @Test
    func invalidQuantityAndUnknownRecurrenceRejectTheWholePayload() {
        let invalidQuantityGoals = [
            AITaskPlanQuantityGoalPayload(targetAmount: 0, unitLabel: "pages"),
            AITaskPlanQuantityGoalPayload(targetAmount: 1_000_001, unitLabel: "pages"),
            AITaskPlanQuantityGoalPayload(targetAmount: 10, unitLabel: "   "),
            AITaskPlanQuantityGoalPayload(targetAmount: 10, unitLabel: "bad\u{0000}unit"),
            AITaskPlanQuantityGoalPayload(
                targetAmount: 10,
                unitLabel: String(repeating: "a", count: 129)
            ),
        ]

        for quantityGoal in invalidQuantityGoals {
            Self.expectError(.invalidField) {
                _ = try LLMTaskPlanService.makeDraft(
                    from: Self.payload(tasks: [
                        Self.task("quantity", quantityGoal: quantityGoal),
                    ]),
                    modelID: "model"
                )
            }
        }

        Self.expectError(.invalidField) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(tasks: [
                    Self.task("weekly", recurrenceCadence: "weekly"),
                ]),
                modelID: "model"
            )
        }
    }

    @Test
    func incompleteQuantityObjectIsNotSilentlyRepaired() async throws {
        let contentData = try JSONSerialization.data(withJSONObject: [
            "categories": [],
            "tasks": [[
                "reference": "reading",
                "categoryReference": NSNull(),
                "parentReference": NSNull(),
                "title": "Read",
                "notes": NSNull(),
                "estimatedMinutes": NSNull(),
                "iconName": "book",
                "colorHex": "1677FF",
                "quantityGoal": ["targetAmount": 10],
                "recurrenceCadence": NSNull(),
            ]],
            "checklistItems": [],
        ])
        let content = try #require(String(data: contentData, encoding: .utf8))
        let service = LLMTaskPlanService { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.test")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return try (Self.chatResponseData(content: content), response)
        }

        await Self.expectError(.invalidResponse) {
            _ = try await service.generate(
                request: "Plan",
                instructions: "",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model"
            )
        }
    }

    @Test
    func requestBuilderUsesFixedContractAndNormalizedUserJSON() throws {
        let request = try LLMTaskPlanService().generationRequest(
            request: "  Build a release plan  ",
            instructions: "Line one\r\nLine two\rLine three",
            endpoint: " https://example.test/v1/ ",
            apiKey: " secret ",
            modelID: " model-1 "
        )
        let body = try #require(request.httpBody)
        let envelope = try JSONDecoder().decode(ChatRequestEnvelope.self, from: body)
        let userMessage = try #require(envelope.messages.last)
        let prompt = try JSONDecoder().decode(
            UserPromptEnvelope.self,
            from: Data(userMessage.content.utf8)
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.test/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(envelope.model == "model-1")
        #expect(envelope.responseFormat.type == "json_object")
        #expect(envelope.messages.map(\.role) == ["system", "user"])
        #expect(envelope.messages[0].content.contains("three flat arrays"))
        #expect(envelope.messages[0].content.contains("maximum task depth is 6"))
        #expect(envelope.messages[0].content.contains("quantityGoal"))
        #expect(envelope.messages[0].content.contains("recurrenceCadence"))
        #expect(envelope.messages[0].content.contains("Apple Health"))
        #expect(envelope.messages[0].content.contains("not only one representative task"))
        #expect(envelope.messages[0].content.contains("Chapter 1 through Chapter 10"))
        #expect(prompt.request == "Build a release plan")
        #expect(prompt.instructions == "Line one\nLine two\nLine three")
        #expect(prompt.allowedSymbols == SymbolCatalog.aiSuggestionSymbolNames)
        #expect(prompt.allowedColors == TaskColorPalette.hexValues)

        let defaultRequest = try LLMTaskPlanService().generationRequest(
            request: "Plan",
            instructions: " \n ",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model"
        )
        let defaultBody = try #require(defaultRequest.httpBody)
        let defaultEnvelope = try JSONDecoder().decode(
            ChatRequestEnvelope.self,
            from: defaultBody
        )
        let defaultPrompt = try JSONDecoder().decode(
            UserPromptEnvelope.self,
            from: Data(#require(defaultEnvelope.messages.last).content.utf8)
        )
        #expect(defaultPrompt.instructions == LLMTaskPlanPrompt.defaultInstructions)
    }

    @Test
    func duplicateAndOrphanReferencesRejectTheWholePayload() {
        Self.expectError(.duplicateReference) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(tasks: [
                    Self.task("Duplicate"),
                    Self.task(" duplicate "),
                ]),
                modelID: "model"
            )
        }
        Self.expectError(.orphanReference) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(tasks: [
                    Self.task("root", category: "missing"),
                ]),
                modelID: "model"
            )
        }
        Self.expectError(.orphanReference) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(tasks: [
                    Self.task("child", parent: "missing"),
                ]),
                modelID: "model"
            )
        }
        Self.expectError(.orphanReference) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(
                    tasks: [Self.task("root")],
                    checklistItems: [Self.checklist("item", task: "missing")]
                ),
                modelID: "model"
            )
        }
    }

    @Test
    func cycleChildCategoryAndExcessiveDepthAreRejected() {
        Self.expectError(.cycle) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(tasks: [
                    Self.task("a", parent: "b"),
                    Self.task("b", parent: "a"),
                ]),
                modelID: "model"
            )
        }
        Self.expectError(.childCategory) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(
                    categories: [Self.category("work")],
                    tasks: [
                        Self.task("root", category: "work"),
                        Self.task("child", category: "work", parent: "root"),
                    ]
                ),
                modelID: "model"
            )
        }

        let tooDeepTasks = (0 ... 7).map { index in
            Self.task(
                "task-\(index)",
                parent: index == 0 ? nil : "task-\(index - 1)"
            )
        }
        Self.expectError(.depthExceeded) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(tasks: tooDeepTasks),
                modelID: "model"
            )
        }
    }

    @Test
    func oneHundredFiftyChecklistItemsUnderOneTaskAreAccepted() throws {
        let draft = try LLMTaskPlanService.makeDraft(
            from: Self.payload(
                categories: [Self.category("reading")],
                tasks: [Self.task("root")],
                checklistItems: (1 ... 150).map {
                    Self.checklist("chapter-\($0)", task: "root")
                }
            ),
            modelID: "model"
        )

        #expect(draft.tasks.count == 1)
        #expect(draft.tasks[0].checklistItems.count == 150)
    }

    @Test
    func veryLargePlansAreAcceptedWithoutCountLimits() throws {
        let categories = (0 ..< 24).map { Self.category("category-\($0)") }
        let rootTasks = categories.map {
            Self.task("root-\($0.reference)", category: $0.reference)
        }
        let childTasks = (0 ..< 200).map { index in
            Self.task(
                "child-\(index)",
                parent: "root-\(categories[index % categories.count].reference)"
            )
        }
        let checklistItems = (0 ..< 500).map {
            Self.checklist("item-\($0)", task: "root-\(categories[0].reference)")
        } + (0 ..< 900).map {
            Self.checklist("extra-\($0)", task: "child-\($0 % childTasks.count)")
        }

        let draft = try LLMTaskPlanService.makeDraft(
            from: Self.payload(
                categories: categories,
                tasks: rootTasks + childTasks,
                checklistItems: checklistItems
            ),
            modelID: "model"
        )

        #expect(draft.categories.count == 24)
        #expect(draft.tasks.count == 224)
        #expect(draft.tasks.reduce(0) { $0 + $1.checklistItems.count } == 1400)
        let busiest = try #require(
            draft.tasks.first { $0.title == "root-\(categories[0].reference)" }
        )
        #expect(busiest.checklistItems.count == 500)
    }

    @Test
    func emptyPlanIsStillRejected() {
        Self.expectError(.noTasks) {
            _ = try LLMTaskPlanService.makeDraft(
                from: Self.payload(tasks: []),
                modelID: "model"
            )
        }
    }

    @Test
    func UTF8BudgetsAreEnforcedWithoutSplittingMultibyteText() throws {
        let exactLimit = String(
            repeating: "é",
            count: LLMTaskPlanService.maximumRequestByteCount / 2
        )
        let service = LLMTaskPlanService()
        let requestAtLimit = try service.generationRequest(
            request: exactLimit,
            instructions: "",
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model"
        )
        #expect(requestAtLimit.httpBody != nil)

        Self.expectError(.requestTooLarge) {
            _ = try service.generationRequest(
                request: exactLimit + "a",
                instructions: "",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model"
            )
        }

        let instructionsAtLimit = String(
            repeating: "é",
            count: LLMTaskPlanService.maximumInstructionsByteCount / 2
        )
        let instructionsRequest = try service.generationRequest(
            request: "Plan",
            instructions: instructionsAtLimit,
            endpoint: "https://example.test/v1",
            apiKey: "key",
            modelID: "model"
        )
        #expect(instructionsRequest.httpBody != nil)

        Self.expectError(.instructionsTooLarge) {
            _ = try service.generationRequest(
                request: "Plan",
                instructions: instructionsAtLimit + "a",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model"
            )
        }
        Self.expectError(.invalidField) {
            _ = try service.generationRequest(
                request: "Plan",
                instructions: "Unsafe\u{0000}instruction",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model"
            )
        }
    }

    @MainActor
    @Test
    func oversizedResponseContentIsRejectedBeforePayloadDecoding() async {
        let oversizedContent = String(
            repeating: "x",
            count: LLMTaskPlanService.maximumResponseContentByteCount + 1
        )
        let responseData: Data
        do {
            responseData = try Self.chatResponseData(content: oversizedContent)
        } catch {
            Issue.record("Could not construct response fixture: \(error)")
            return
        }
        let service = LLMTaskPlanService { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (responseData, response)
        }

        await Self.expectError(.responseContentTooLarge) {
            _ = try await service.generate(
                request: "Plan",
                instructions: "",
                endpoint: "https://example.test/v1",
                apiKey: "key",
                modelID: "model"
            )
        }
    }

    private static func payload(
        categories: [AITaskPlanCategoryPayload] = [],
        tasks: [AITaskPlanTaskPayload],
        checklistItems: [AITaskPlanChecklistPayload] = []
    ) -> AITaskPlanPayload {
        AITaskPlanPayload(
            categories: categories,
            tasks: tasks,
            checklistItems: checklistItems
        )
    }

    private static func category(_ reference: String) -> AITaskPlanCategoryPayload {
        AITaskPlanCategoryPayload(
            reference: reference,
            title: reference,
            iconName: "folder",
            colorHex: "1677FF"
        )
    }

    private static func task(
        _ reference: String,
        category: String? = nil,
        parent: String? = nil,
        quantityGoal: AITaskPlanQuantityGoalPayload? = nil,
        recurrenceCadence: String? = nil
    ) -> AITaskPlanTaskPayload {
        AITaskPlanTaskPayload(
            reference: reference,
            categoryReference: category,
            parentReference: parent,
            title: reference,
            notes: nil,
            estimatedMinutes: nil,
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            quantityGoal: quantityGoal,
            recurrenceCadence: recurrenceCadence
        )
    }

    private static func checklist(
        _ reference: String,
        task: String
    ) -> AITaskPlanChecklistPayload {
        AITaskPlanChecklistPayload(
            reference: reference,
            taskReference: task,
            title: reference,
            iconName: "checkmark.circle",
            colorHex: "1677FF"
        )
    }

    private static func chatResponseData(content: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "choices": [
                ["message": ["content": content]],
            ],
        ])
    }

    private static func expectError(
        _ expected: LLMTaskPlanServiceError,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected \(expected)")
        } catch let error as LLMTaskPlanServiceError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func expectError(
        _ expected: LLMTaskPlanServiceError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as LLMTaskPlanServiceError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct ChatRequestEnvelope: Decodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
    }

    struct Message: Decodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Decodable {
        let type: String
    }
}

private struct UserPromptEnvelope: Decodable {
    let instructions: String
    let request: String
    let allowedSymbols: [String]
    let allowedColors: [String]
}
