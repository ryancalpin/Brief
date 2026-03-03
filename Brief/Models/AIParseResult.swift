// AIParseResult.swift
// Decoded output from AI parsing (Apple Intelligence or BYOK)

import Foundation

/// The structured result returned by the AI after parsing a voice transcript.
/// Compatible with both Foundation Models (`@Generable` on iOS 26+) and JSON decoding for BYOK APIs.
struct AIParseResult: Codable, Sendable {
    var itemType: String        // "reminder" | "note" | "calendarEvent" | "list" | "generic"
    var destination: String     // "reminders" | "notes" | "calendar" | "briefOnly"
    var title: String
    var content: String?
    var dueDateISO: String?     // ISO 8601 string or nil
    var priority: String?       // "low" | "medium" | "high" | "urgent"
    var tags: [String]
    var startDateISO: String?
    var endDateISO: String?
    var location: String?

    // MARK: - Computed typed accessors

    var briefItemType: BriefItemType {
        BriefItemType(rawValue: itemType) ?? .generic
    }

    var briefDestination: BriefDestination {
        BriefDestination(rawValue: destination) ?? .briefOnly
    }

    var briefPriority: BriefPriority? {
        priority.flatMap { BriefPriority(rawValue: $0) }
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoParserNoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoParser.date(from: string) ?? isoParserNoFractional.date(from: string)
    }

    var dueDate: Date? { Self.parseDate(dueDateISO) }
    var startDate: Date? { Self.parseDate(startDateISO) }
    var endDate: Date? { Self.parseDate(endDateISO) }

    // MARK: - Conversion to BriefItem

    func toBriefItem(rawTranscript: String, aiProvider: String? = nil) -> BriefItem {
        let item = BriefItem(
            rawTranscript: rawTranscript,
            title: title,
            content: content,
            itemType: briefItemType,
            destination: briefDestination,
            dueDate: dueDate,
            priority: briefPriority,
            startDate: startDate,
            endDate: endDate,
            location: location,
            tags: tags
        )
        item.aiProviderUsed = aiProvider
        item.isProcessed = true
        return item
    }
}

// MARK: - System prompt for AI parsing

extension AIParseResult {
    static func systemPrompt(currentDate: Date = .now, timezone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.timeZone = timezone
        let dateString = formatter.string(from: currentDate)
        let tzName = timezone.identifier

        return """
        You are Brief, a voice-first assistant that converts spoken input into structured data.

        Current date/time: \(dateString) (\(tzName))

        Parse the user's voice input and return ONLY valid JSON matching this exact schema:
        {
          "itemType": "reminder" | "note" | "calendarEvent" | "list" | "generic",
          "destination": "reminders" | "notes" | "calendar" | "briefOnly",
          "title": "concise title (max 80 chars)",
          "content": "full text or null",
          "dueDateISO": "ISO 8601 or null",
          "priority": "low" | "medium" | "high" | "urgent" | null,
          "tags": ["tag1", "tag2"],
          "startDateISO": "ISO 8601 or null",
          "endDateISO": "ISO 8601 or null",
          "location": "location string or null"
        }

        Rules:
        - "remind me to", "don't forget to", "I need to" → reminder → reminders
        - "note that", "remember that", "write down", "jot down" → note → notes
        - "schedule", "add to calendar", "meeting", "appointment" + date/time → calendarEvent → calendar
        - "shopping list", "grocery list", "todo list", any explicit list → list → reminders
        - Urgent signals ("ASAP", "urgent", "immediately") → priority: "urgent"
        - Parse relative dates: "tomorrow", "next Monday", "in 3 hours", "this weekend"
        - All dates must be ISO 8601 in the user's timezone
        - Extract location for calendar events
        - Keep title concise; put details in content
        - Return ONLY the JSON object, no markdown, no explanation
        """
    }
}
