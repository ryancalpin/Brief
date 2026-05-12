// RuleBasedParserTests.swift
// Tests for the deterministic offline parser — all date patterns, classification, priorities.

import XCTest
@testable import Brief

final class RuleBasedParserTests: XCTestCase {

    // MARK: - Classification

    func testReminderTriggers() {
        XCTAssertEqual(classify("remind me to buy milk"), .reminder)
        XCTAssertEqual(classify("don't forget the meeting"), .reminder)
        XCTAssertEqual(classify("remember to call mom"), .reminder)
        XCTAssertEqual(classify("i need to finish the report"), .reminder)
        XCTAssertEqual(classify("i have to exercise"), .reminder)
        XCTAssertEqual(classify("todo write tests"), .reminder)
    }

    func testNoteTriggers() {
        XCTAssertEqual(classify("note that the API key is sk-or-abc"), .note)
        XCTAssertEqual(classify("remember that we discussed the timeline"), .note)
        XCTAssertEqual(classify("write down the recipe"), .note)
        XCTAssertEqual(classify("jot down that idea"), .note)
        XCTAssertEqual(classify("keep in mind the deadline is Friday"), .note)
    }

    func testCalendarTriggers() {
        XCTAssertEqual(classify("schedule a dentist appointment"), .calendarEvent)
        XCTAssertEqual(classify("meeting with Sarah tomorrow at 2"), .calendarEvent)
        XCTAssertEqual(classify("add to calendar my flight info"), .calendarEvent)
    }

    func testListTriggers() {
        XCTAssertEqual(classify("shopping list for groceries"), .list)
        XCTAssertEqual(classify("grocery list milk eggs bread"), .list)
        XCTAssertEqual(classify("to-do list for this week"), .list)
        XCTAssertEqual(classify("list of things to pack"), .list)
    }

    func testGenericFallback() {
        XCTAssertEqual(classify("the weather is nice today"), .generic)
        XCTAssertEqual(classify("hello"), .generic)
    }

    // MARK: - Title extraction

    func testTitleStripsPrefixes() {
        let result = parse("remind me to buy milk tomorrow")
        XCTAssertEqual(result.title, "Buy milk tomorrow")
    }

    func testTitleTruncatesOver80Chars() {
        let long = "remind me to " + String(repeating: "a very long reminder text that goes on and on ", count: 5)
        let result = parse(long)
        XCTAssertLessThanOrEqual(result.title.count, 83) // 80 chars + "…"
        XCTAssertTrue(result.title.hasSuffix("…"))
    }

    func testTitlePreservesOriginalWhenNoPrefix() {
        let result = parse("buy milk")
        XCTAssertEqual(result.title, "Buy milk")
    }

    // MARK: - Date parsing — absolute named

    func testTomorrow() {
        let result = parse("remind me to call mom tomorrow")
        let expected = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        XCTAssertNotNil(result.dueDate)
        XCTAssertTrue(Calendar.current.isDate(result.dueDate!, inSameDayAs: expected!))
    }

    func testNextWeek() {
        let result = parse("schedule team standup next week")
        let expected = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Date())
        XCTAssertNotNil(result.dueDate)
        XCTAssertTrue(Calendar.current.isDate(result.dueDate!, inSameDayAs: expected!))
    }

    func testNextMonth() {
        let result = parse("remind me to renew subscription next month")
        let expected = Calendar.current.date(byAdding: .month, value: 1, to: Date())
        XCTAssertNotNil(result.dueDate)
        // Same day-of-month, one month ahead
        let expectedDay = Calendar.current.component(.day, from: expected!)
        let actualDay = Calendar.current.component(.day, from: result.dueDate!)
        XCTAssertEqual(actualDay, expectedDay)
    }

    func testTonight() {
        let result = parse("remind me to take out trash tonight")
        XCTAssertNotNil(result.dueDate)
        let hour = Calendar.current.component(.hour, from: result.dueDate!)
        XCTAssertEqual(hour, 19)
    }

    // MARK: - Date parsing — day of week

    func testNextMonday() {
        let result = parse("remind me to submit report next monday")
        XCTAssertNotNil(result.dueDate)
        let weekday = Calendar.current.component(.weekday, from: result.dueDate!)
        XCTAssertEqual(weekday, 2) // Monday = 2 in Gregorian
    }

    func testThisFriday() {
        let result = parse("meeting this friday at 3pm")
        XCTAssertNotNil(result.dueDate)
        let weekday = Calendar.current.component(.weekday, from: result.dueDate!)
        XCTAssertEqual(weekday, 6) // Friday = 6
    }

    func testOnTuesday() {
        let result = parse("remind me on tuesday to call the doctor")
        XCTAssertNotNil(result.dueDate)
        let weekday = Calendar.current.component(.weekday, from: result.dueDate!)
        XCTAssertEqual(weekday, 3) // Tuesday = 3
    }

    // MARK: - Date parsing — relative time

    func testInThreeHours() {
        let result = parse("remind me to check email in 3 hours")
        let expected = Calendar.current.date(byAdding: .hour, value: 3, to: Date())
        XCTAssertNotNil(result.dueDate)
        let diff = abs(result.dueDate!.timeIntervalSince(expected!))
        XCTAssertLessThan(diff, 5) // Within 5 seconds
    }

    func testInThirtyMinutes() {
        let result = parse("remind me in 30 minutes to leave")
        let expected = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
        XCTAssertNotNil(result.dueDate)
        let diff = abs(result.dueDate!.timeIntervalSince(expected!))
        XCTAssertLessThan(diff, 5)
    }

    func testInTwoDays() {
        let result = parse("schedule follow up in 2 days")
        let expected = Calendar.current.date(byAdding: .day, value: 2, to: Date())
        XCTAssertNotNil(result.dueDate)
        XCTAssertTrue(Calendar.current.isDate(result.dueDate!, inSameDayAs: expected!))
    }

    // MARK: - Date parsing — specific dates

    func testMarch15() {
        let result = parse("remind me about taxes on March 15")
        XCTAssertNotNil(result.dueDate)
        let month = Calendar.current.component(.month, from: result.dueDate!)
        let day = Calendar.current.component(.day, from: result.dueDate!)
        XCTAssertEqual(month, 3)
        XCTAssertEqual(day, 15)
    }

    func testDateWithOrdinalSuffix() {
        let result = parse("event on March 15th")
        XCTAssertNotNil(result.dueDate)
        let month = Calendar.current.component(.month, from: result.dueDate!)
        let day = Calendar.current.component(.day, from: result.dueDate!)
        XCTAssertEqual(month, 3)
        XCTAssertEqual(day, 15)
    }

    func testNoDateReturnsNil() {
        let result = parse("remind me to relax")
        XCTAssertNil(result.dueDate)
    }

    // MARK: - Priority extraction

    func testUrgentPriority() {
        XCTAssertEqual(parse("remind me urgent to call back").priority, 3)
        XCTAssertEqual(parse("do this asap").priority, 3)
        XCTAssertEqual(parse("fix this immediately").priority, 3)
    }

    func testImportantPriority() {
        XCTAssertEqual(parse("important meeting tomorrow").priority, 3)
        XCTAssertEqual(parse("high priority task").priority, 3)
    }

    func testLowPriority() {
        XCTAssertEqual(parse("whenever you get a chance").priority, 1)
        XCTAssertEqual(parse("low priority cleanup").priority, 1)
        XCTAssertEqual(parse("do this eventually").priority, 1)
    }

    func testDefaultPriority() {
        XCTAssertEqual(parse("remind me to buy milk").priority, 0)
    }

    // MARK: - Conversation type

    func testConversationalInput() {
        let result = parse("what's the weather like today")
        // This should NOT be classified as a note/reminder — it's generic
        XCTAssertEqual(result.itemType, .generic)
    }

    // MARK: - Helpers

    private func parse(_ transcript: String) -> AIParseResult {
        RuleBasedParser.parse(transcript: transcript)
    }

    private func classify(_ transcript: String) -> BriefItemType {
        parse(transcript).itemType
    }
}
