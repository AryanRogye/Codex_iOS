import Foundation

enum RelayRole: String, Codable {
    case user
    case assistant
}

struct RelayMessage: Codable {
    let role: RelayRole
    let content: String
    let timestamp: Date
}

struct RelayThreadSummary: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
    let lastMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messageCount = "message_count"
        case lastMessage = "last_message"
    }
}

struct RelayThreadResponse: Codable {
    let id: String
    let createdAt: Date
    let updatedAt: Date
    let messages: [RelayMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case messages
    }
}

struct RelayHealthResponse: Codable {
    let status: String
}

struct RelayChatRequest: Encodable {
    let threadId: String?
    let message: String
    let model: String?
    let workingDirectory: String?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case message
        case model
        case workingDirectory = "working_directory"
    }
}

struct RelayChatResponse: Codable {
    let threadId: String
    let model: String
    let reply: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case model
        case reply
    }
}

struct RelayErrorResponse: Decodable {
    let error: String
}

struct RelayDirectoryListing: Decodable {
    let path: String
    let parentPath: String?
    let entries: [RelayDirectoryEntry]

    enum CodingKeys: String, CodingKey {
        case path
        case parentPath = "parent_path"
        case entries
    }
}

struct RelayDirectoryEntry: Decodable, Equatable, Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDirectory = "is_directory"
    }
}

enum RelayCoders {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let container = try value.singleValueContainer()
            let rawDate = try container.decode(String.self)
            if let date = RelayDateParser.withFractional.date(from: rawDate)
                ?? RelayDateParser.standard.date(from: rawDate) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(rawDate)"
            )
        }
        return decoder
    }
}

enum RelayDateParser {
    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
