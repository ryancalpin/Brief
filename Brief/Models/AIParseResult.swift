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
        itemType         = (try? c.decode(BriefItemType.self, forKey: .itemType)) ?? .generic
        title            = (try? c.decode(String.self,        forKey: .title))    ?? ""
        body             = try? c.decode(String.self,         forKey: .body)
        aiResponse       = try? c.decode(String.self,         forKey: .aiResponse)
        priority         = (try? c.decode(Int.self,           forKey: .priority)) ?? 0
        tags             = (try? c.decode([String].self,      forKey: .tags))     ?? []
        sessionID        = try? c.decode(UUID.self,           forKey: .sessionID)
        isConversational = (try? c.decode(Bool.self,          forKey: .isConversational)) ?? false

        // AI returns dueDate as an ISO string; parse it
        if let iso = try? c.decode(String.self, forKey: .dueDate) {
            dueDate = Self.parseISO(iso)
        } else {
            dueDate = try? c.decode(Date.self, forKey: .dueDate)
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

        let briefPriority: BriefPriority? = {
            switch priority {
            case 1: return .low
            case 2: return .medium
            case 3: return .high
            default: return nil
            }
        }()

        let item = BriefItem(
            rawTranscript: rawTranscript,
            title: title,
            content: body,
            itemType: isConversational ? .convo : itemType,
            destination: destination,
            dueDate: dueDate,
            priority: briefPriority,
            startDate: nil,
            endDate: nil,
            location: nil,
            tags: tags
        )
        item.aiProviderUsed   = aiProvider
        item.isProcessed      = true
        item.aiResponse       = aiResponse
        item.sessionID        = sessionID
        item.isConversational = isConversational
        return item
    }
}

// MARK: - System prompt

extension AIParseResult {
    static func systemPrompt(currentDate: Date = .now, timezone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = timezone
        let dateString = formatter.string(from: currentDate)
        let tzName = timezone.identifier

        return """
        You are Brief, a voice-first ambient AI assistant on iPhone and Apple Watch.
        Help the user capture thoughts, manage tasks, and think through ideas.

        Current date/time: \(dateString) (\(tzName))

        Parse the user's voice input and return ONLY valid JSON matching this exact schema:
        {
          "itemType": "reminder" | "note" | "calendarEvent" | "list" | "convo" | "generic",
          "title": "concise title (max 80 chars)",
          "body": "full text or null",
          "aiResponse": "1-3 sentence conversational reply or null",
          "dueDate": "ISO 8601 or null",
          "priority": 0 | 1 | 2 | 3,
          "tags": ["tag1", "tag2"],
          "isConversational": true | false
        }

        Priority scale: 0=none, 1=low, 2=medium, 3=high

        Rules:
        - "remind me to", "don't forget to", "I need to" → reminder
        - "note that", "remember that", "write down", "jot down" → note
        - "schedule", "add to calendar", "meeting", "appointment" + date/time → calendarEvent
        - "shopping list", "grocery list", "todo list" → list
        - Questions, thoughts, ideas, "what do you think", chat → convo + isConversational: true
        - Urgent signals ("ASAP", "urgent", "immediately") → priority: 3
        - Parse relative dates: "tomorrow", "next Monday", "in 3 hours", "this weekend"
        - All dates in ISO 8601 in the user's timezone
        - For convo items: aiResponse should be a helpful 1-3 sentence reply
        - Keep title concise; put details in body
        - Return ONLY the JSON object, no markdown fences, no explanation
        """
    }
}
