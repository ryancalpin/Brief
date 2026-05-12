// BYOKService.swift
// Rule-based offline parser — always-on fallback when no AI service is configured.
// OpenAI and Anthropic direct integrations have been removed; use OpenRouterService.

import Foundation

final class BYOKService: Sendable {

    func parseRuleBased(transcript: String) -> AIParseResult {
        RuleBasedParser.parse(transcript: transcript)
    }
}

// MARK: - Rule-Based Parser

struct RuleBasedParser {
    static func parse(transcript: String) -> AIParseResult {
        let lower = transcript.lowercased()
        let itemType = classify(lower)
        let title    = extractTitle(from: transcript)
        let dueDate  = extractDate(from: lower)
        let priority = extractPriority(from: lower)

        return AIParseResult(
            itemType: itemType,
            title: title,
            body: transcript != title ? transcript : nil,
            dueDate: dueDate,
            priority: priority
        )
    }

    // MARK: - Classification

    private static func classify(_ text: String) -> BriefItemType {
        let reminderTriggers = ["remind me", "don't forget", "remember to", "i need to", "i have to", "todo"]
        let noteTriggers     = ["note that", "remember that", "write down", "jot down", "keep in mind"]
        let calendarTriggers = ["schedule", "meeting", "appointment", "event", "add to calendar"]
        let listTriggers     = ["shopping list", "grocery list", "to-do list", "todo list", "list of"]

        if listTriggers.contains(where:     { text.contains($0) }) { return .list }
        if reminderTriggers.contains(where: { text.contains($0) }) { return .reminder }
        if noteTriggers.contains(where:     { text.contains($0) }) { return .note }
        if calendarTriggers.contains(where: { text.contains($0) }) { return .calendarEvent }
        return .generic
    }

    // MARK: - Title extraction

    private static func extractTitle(from text: String) -> String {
        var title = text
        let fillers = ["remind me to ", "note that ", "remember that ", "write down ", "jot down "]
        for filler in fillers {
            if title.lowercased().hasPrefix(filler) {
                title = String(title.dropFirst(filler.count))
                break
            }
        }
        let first = title.prefix(1).uppercased()
        let rest  = title.dropFirst()
        title = first + rest
        if title.count > 80 { title = String(title.prefix(80)) + "\u{2026}" }
        return title
    }

    // MARK: - Date extraction (extended)

    private static func extractDate(from text: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()

        // Absolute named days
        if text.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: now)
        }
        if text.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }
        if text.contains("next month") {
            return calendar.date(byAdding: .month, value: 1, to: now)
        }
        if text.contains("tonight") || text.contains("this evening") {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = 19; comps.minute = 0
            return calendar.date(from: comps)
        }

        // Day-of-week patterns: "next Monday", "this Friday", "on Tuesday"
        let weekdayNames = [
            "sunday", "monday", "tuesday", "wednesday",
            "thursday", "friday", "saturday"
        ]
        for (idx, name) in weekdayNames.enumerated() {
            if text.contains("next \(name)") {
                return nextWeekday(calendar: calendar, from: now, target: idx + 1, skipCurrent: true)
            }
            if text.contains("this \(name)") || text.contains("on \(name)") {
                return nextWeekday(calendar: calendar, from: now, target: idx + 1, skipCurrent: false)
            }
        }

        // Relative time: "in 3 hours", "in 30 minutes", "in 2 days"
        if let relative = extractRelativeTime(from: text, calendar: calendar, now: now) {
            return relative
        }

        // Specific date: "March 15th", "May 3", "June 22 2026"
        if let specific = extractSpecificDate(from: text, calendar: calendar, now: now) {
            return specific
        }

        return nil
    }

    // MARK: - Relative time parsing

    private static func extractRelativeTime(from text: String, calendar: Calendar, now: Date) -> Date? {
        let patterns: [(String, Calendar.Component)] = [
            ("hour",   .hour),
            ("hours",  .hour),
            ("minute", .minute),
            ("minutes",.minute),
            ("day",    .day),
            ("days",   .day),
            ("week",   .weekOfYear),
            ("weeks",  .weekOfYear),
        ]

        for (unit, component) in patterns {
            // Match "in X <unit>" e.g. "in 3 hours"
            if let range = text.range(of: "in \\d+ \(unit)", options: .regularExpression) {
                let match = String(text[range])
                if let num = Int(match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    return calendar.date(byAdding: component, value: num, to: now)
                }
            }
        }
        return nil
    }

    // MARK: - Specific date parsing

    private static func extractSpecificDate(from text: String, calendar: Calendar, now: Date) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Try: "Month Day Year" (e.g. "March 15 2026" or "March 15, 2026")
        let patterns = [
            "MMMM d yyyy",    // March 15 2026
            "MMMM d, yyyy",   // March 15, 2026
            "MMM d yyyy",     // Mar 15 2026
            "MMM d, yyyy",    // Mar 15, 2026
            "MMMM d",          // March 15 (assume current year)
            "MMM d",           // Mar 15 (assume current year)
        ]

        for pattern in patterns {
            dateFormatter.dateFormat = pattern
            if let range = text.range(of: "\\b[a-zA-Z]+ \\d{1,2}(,? \\d{4})?\\b", options: .regularExpression) {
                let dateStr = String(text[range])
                    .replacingOccurrences(of: "st", with: "")
                    .replacingOccurrences(of: "nd", with: "")
                    .replacingOccurrences(of: "rd", with: "")
                    .replacingOccurrences(of: "th", with: "")
                if let date = dateFormatter.date(from: dateStr) {
                    // If no year in pattern, assume current year
                    if !pattern.contains("yyyy") {
                        var comps = calendar.dateComponents([.month, .day], from: date)
                        comps.year = calendar.component(.year, from: now)
                        if let adjusted = calendar.date(from: comps), adjusted < now {
                            // If the date has already passed this year, use next year
                            comps.year! += 1
                        }
                        return calendar.date(from: comps)
                    }
                    return date
                }
            }
        }
        return nil
    }

    // MARK: - Weekday helper

    private static func nextWeekday(calendar: Calendar, from now: Date, target: Int, skipCurrent: Bool) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: now)
        var daysToAdd = target - currentWeekday
        if daysToAdd < 0 { daysToAdd += 7 }
        if daysToAdd == 0 && skipCurrent { daysToAdd = 7 }
        if daysToAdd == 0 { daysToAdd = 0 } // "this Monday" = today if it's Monday
        return calendar.date(byAdding: .day, value: daysToAdd, to: now)
    }

    // MARK: - Priority extraction

    private static func extractPriority(from text: String) -> Int {
        if text.contains("urgent") || text.contains("asap") || text.contains("immediately") { return 3 }
        if text.contains("important") || text.contains("high priority") { return 3 }
        if text.contains("whenever") || text.contains("low priority") || text.contains("eventually") { return 1 }
        return 0
    }
}
