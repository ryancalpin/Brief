// AIParseResult.swift
// Decoded output from AI parsing (Apple Intelligence or OpenRouter/BYOK)

import Foundation

struct AIParseResult: Codable, Sendable {
    var itemType: BriefItemType
    var title: String
    var body: String?
    var aiResponse: String?      // conversational reply (spoken back to user)
    var dueDate: Date?
    var priority: Int = 0        // 0=none 1=low 2=medium 3=high
    var tags: [String] = []
    var sessionID: UUID?
    var isConversational: Bool = false

    init(
        itemType: BriefItemType = .generic,
        title: String,
        body: String? = nil,
        aiResponse: String? = nil,
        dueDate: Date? = nil,
        priority: Int = 0,
        tags: [String] = [],
        sessionID: UUID? = nil,
        isConversational: Bool = false
    ) {
        self.itemType = itemType
        self.title = title
        self.body = body
        self.aiResponse = aiResponse
        self.dueDate = dueDate
        self.priority = priority
        self.tags = tags
        self.sessionID = sessionID
        self.isConversational = isConversational
    }

    // MARK: - Custom Codable (AI returns dueDate as an ISO 8601 string)

    enum CodingKeys: String, CodingKey {
        case itemType, title, body, aiResponse, dueDate, priority, tags, sessionID, isConversational
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Decode each field with clear fallbacks, but validate critical fields
        itemType         = (try? c.decode(BriefItemType.self, forKey: .itemType)) ?? .generic
        title            = (try? c.decode(String.self,        forKey: .title)) ?? ""
        body             = try? c.decode(String.self,         forKey: .body)
        aiResponse       = try? c.decode(String.self,         forKey: .aiResponse)
        priority         = (try? c.decode(Int.self,           forKey: .priority)) ?? 0
        tags             = (try? c.decode([String].self,      forKey: .tags)) ?? []
        sessionID        = try? c.decode(UUID.self,           forKey: .sessionID)
        isConversational = (try? c.decode(Bool.self,          forKey: .isConversational)) ?? false

        // AI returns dueDate as an ISO string; parse it
        if let iso = try? c.decode(String.self, forKey: .dueDate) {
            dueDate = Self.parseISO(iso)
        } else {
            dueDate = try? c.decode(Date.self, forKey: .dueDate)
        }

        // Validate: title must be non-empty after decoding
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: c.codingPath + [CodingKeys.title],
                    debugDescription: "AIParseResult.title must not be empty after decoding"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(itemType,         forKey: .itemType)
        try c.encode(title,            forKey: .title)
        try c.encodeIfPresent(body,    forKey: .body)
        try c.encodeIfPresent(aiResponse, forKey: .aiResponse)
        try c.encode(priority,         forKey: .priority)
        try c.encode(tags,             forKey: .tags)
        try c.encodeIfPresent(sessionID, forKey: .sessionID)
        try c.encode(isConversational, forKey: .isConversational)
        if let date = dueDate {
            try c.encode(isoFormatter.string(from: date), forKey: .dueDate)
        }
    }

    // MARK: - Date parsing

    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO(_ string: String) -> Date? {
        isoFull.date(from: string) ?? isoBasic.date(from: string)
    }

    private let isoFormatter = ISO8601DateFormatter()
}

// MARK: - BriefItem factory

extension AIParseResult {
    func toBriefItem(rawTranscript: String, aiProvider: String? = nil) -> BriefItem {
        let destination: BriefDestination = {
            switch itemType {
            case .reminder, .list: return .reminders
            case .calendarEvent:   return .calendar
            case .note:            return .notes
            case .convo, .generic: return .briefOnly
            }
        }()

        let pri: BriefPriority? = {
            switch priority {
            case 3: return .high
            case 2: return .medium
            case 1: return .low
            default: return nil
            }
        }()

        return BriefItem(
            rawTranscript: rawTranscript,
            title: title,
            content: body,
            itemType: itemType,
            destination: destination,
            dueDate: dueDate,
            priority: pri,
            startDate: itemType == .calendarEvent ? dueDate : nil,
            endDate: itemType == .calendarEvent && dueDate != nil
                ? Calendar.current.date(byAdding: .hour, value: 1, to: dueDate!) : nil,
            location: nil,
            tags: tags
        )
    }

    // MARK: - System prompt (shared across all AI providers)

    static func systemPrompt() -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        return """
        You are a voice-input parser assistant. Convert the user's spoken input into a structured JSON object with these fields:
        - itemType: "reminder" | "note" | "calendarEvent" | "list" | "generic" | "convo"
        - title: Short actionable summary (max 80 chars)
        - body: Additional context or details (optional)
        - aiResponse: Conversational reply if this is a conversation (optional)
        - dueDate: ISO 8601 date string if a date/time was mentioned (optional)
        - priority: 0 (none), 1 (low), 2 (medium), 3 (high)
        - tags: Array of relevant keyword strings (optional)
        - isConversational: true if this is casual conversation, not an action item
        - sessionID: UUID if continuing an existing session (optional)

        Current time is \(now). Use it to calculate relative dates (tomorrow, next week, etc).

        Respond with ONLY the JSON object. No markdown, no explanation, no code fences.
        """
    }
}
