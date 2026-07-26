import Foundation

indirect nonisolated enum OpenAIJSONValue:
    Codable,
    Equatable,
    Sendable
{
    case object([String: OpenAIJSONValue])
    case array([OpenAIJSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(
            [String: OpenAIJSONValue].self
        ) {
            self = .object(value)
        } else if let value = try? container.decode(
            [OpenAIJSONValue].self
        ) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

nonisolated struct OpenAIChatToolDefinition:
    Encodable,
    Equatable,
    Sendable
{
    nonisolated struct Function: Encodable, Equatable, Sendable {
        let name: String
        let description: String
        let parameters: OpenAIJSONValue
    }

    let type: String
    let function: Function

    init(type: String = "function", function: Function) {
        self.type = type
        self.function = function
    }
}

nonisolated struct OpenAIChatToolCall:
    Codable,
    Equatable,
    Sendable
{
    nonisolated struct Function: Codable, Equatable, Sendable {
        let name: String
        let arguments: String
    }

    let id: String
    let type: String
    let function: Function
}
