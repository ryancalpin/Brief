// AIParseResultTests.swift
// Tests for JSON encoding/decoding, validation, and the BriefItem factory.

import XCTest
@testable import Brief

final class AIParseResultTests: XCTestCase {

    // MARK: - Valid JSON decode

    func testDecodeValidReminder() throws {
        let json = """
        {
            "itemType": "reminder",
            "title": "Buy milk",
            "body": "Need 2% milk from the store",
            "dueDate": "2026-05-13T10:00:00Z",
            "priority": 2,
            "tags": ["groceries", "errands"]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(AIParseResult.self, from: data)

        XCTAssertEqual(result.itemType, .reminder)
        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertEqual(result.body, "Need 2% milk from the store")
        XCTAssertNotNil(result.dueDate)
        XCTAssertEqual(result.priority, 2)
        XCTAssertEqual(result.tags, ["groceries", "errands"])
        XCTAssertEqual(result.isConversational, false)
    }

    func testDecodeCalendarEvent() throws {
        let json = """
        {
            "itemType": "calendarEvent",
            "title": "Team standup",
            "dueDate": "2026-05-13T09:00:00Z",
            "priority": 1
        }
        """
        let result = try JSONDecoder().decode(AIParseResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.itemType, .calendarEvent)
        XCTAssertEqual(result.title, "Team standup")
        XCTAssertNil(result.body)
        XCTAssertNotNil(result.dueDate)
    }

    func testDecodeConvoWithAIResponse() throws {
        let json = """
        {
            "itemType": "convo",
            "title": "Weather question",
            "aiResponse": "It's sunny and 72°F today!",
            "isConversational": true
        }
        """
        let result = try JSONDecoder().decode(AIParseResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.itemType, .convo)
        XCTAssertEqual(result.aiResponse, "It's sunny and 72°F today!")
        XCTAssertTrue(result.isConversational)
    }

    // MARK: - Partial / missing fields

    func testDecodeMinimalJSON() throws {
        let json = """
        {
            "itemType": "generic",
            "title": "hello"
        }
        """
        let result = try JSONDecoder().decode(AIParseResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.title, "hello")
        XCTAssertEqual(result.itemType, .generic)
        XCTAssertNil(result.dueDate)
        XCTAssertEqual(result.priority, 0)
        XCTAssertEqual(result.tags, [])
        XCTAssertFalse(result.isConversational)
    }

    func testDecodeWithMissingFields() throws {
        let json = """
        {
            "title": "Just a title",
            "itemType": "note"
        }
        """
        let result = try JSONDecoder().decode(AIParseResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.title, "Just a title")
        XCTAssertEqual(result.itemType, .note)
        XCTAssertEqual(result.priority, 0)
    }

    // MARK: - Empty title validation

    func testDecodeEmptyTitleThrows() {
        let json = """
        {
            "itemType": "reminder",
            "title": ""
        }
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AIParseResult.self, from: data)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDecodeWhitespaceOnlyTitleThrows() {
        let json = """
        {
            "itemType": "reminder",
            "title": "   "
        }
        """
        let data = json.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(AIParseResult.self, from: data))
    }

    // MARK: - Encode round-trip

    func testEncodeDecodeRoundTrip() throws {
        let original = AIParseResult(
            itemType: .reminder,
            title: "Call dentist",
            body: "Ask about teeth whitening",
            dueDate: ISO8601DateFormatter().date(from: "2026-06-01T14:00:00Z"),
            priority: 2,
            tags: ["health", "appointments"],
            sessionID: UUID(),
            isConversational: false
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIParseResult.self, from: encoded)

        XCTAssertEqual(decoded.itemType, original.itemType)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.body, original.body)
        XCTAssertEqual(decoded.priority, original.priority)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.isConversational, original.isConversational)
        XCTAssertNotNil(decoded.dueDate)
        XCTAssertEqual(decoded.sessionID, original.sessionID)
    }

    // MARK: - DueDate ISO 8601 variants

    func testDecodeDueDateWithoutFractionalSeconds() throws {
        let json = """
        {
            "itemType": "reminder",
            "title": "Test",
            "dueDate": "2026-05-13T10:00:00Z"
        }
        """
        let result = try JSONDecoder().decode(AIParseResult.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(result.dueDate)
    }

    func testDecodeDueDateWithFractionalSeconds() throws {
        let json = """
        {
            "itemType": "reminder",
            "title": "Test",
            "dueDate": "2026-05-13T10:00:00.123Z"
        }
        """
        let result = try JSONDecoder().decode(AIParseResult.self, from: json.data(using: .utf8)!)
        XCTAssertNotNil(result.dueDate)
    }

    // MARK: - toBriefItem factory

    func testToBriefItemReminder() {
        let result = AIParseResult(
            itemType: .reminder,
            title: "Buy milk",
            body: "2% organic",
            dueDate: Date(),
            priority: 2,
            tags: ["groceries"]
        )
        let item = result.toBriefItem(rawTranscript: "remind me to buy milk", aiProvider: "openrouter")

        XCTAssertEqual(item.title, "Buy milk")
        XCTAssertEqual(item.content, "2% organic")
        XCTAssertEqual(item.itemType, .reminder)
        XCTAssertEqual(item.destination, .reminders)
        XCTAssertNotNil(item.dueDate)
        XCTAssertEqual(item.tags, ["groceries"])
    }

    func testToBriefItemCalendarEvent() {
        let due = Date()
        let result = AIParseResult(
            itemType: .calendarEvent,
            title: "Meeting",
            dueDate: due,
            priority: 1
        )
        let item = result.toBriefItem(rawTranscript: "schedule meeting")

        XCTAssertEqual(item.destination, .calendar)
        XCTAssertEqual(item.startDate, due)
        XCTAssertNotNil(item.endDate) // Should be 1 hour after start
    }

    func testToBriefItemNote() {
        let result = AIParseResult(itemType: .note, title: "Recipe")
        let item = result.toBriefItem(rawTranscript: "note that the recipe uses 2 eggs")

        XCTAssertEqual(item.destination, .notes)
    }

    func testToBriefItemConvoStaysInApp() {
        let result = AIParseResult(itemType: .convo, title: "Hello")
        let item = result.toBriefItem(rawTranscript: "hello")

        XCTAssertEqual(item.destination, .briefOnly)
    }
}
