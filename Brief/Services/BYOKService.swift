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
        if title.count > 80 { title = String(title.prefix(80)) + "…" }
        return title
    }

    private static func extractDate(from text: String) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        if text.contains("tomorrow") { return calendar.date(byAdding: .day, value: 1, to: now) }
        if text.contains("next week") { return calendar.date(byAdding: .weekOfYear, value: 1, to: now) }
        if text.contains("tonight") || text.contains("this evening") {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = 19; comps.minute = 0
            return calendar.date(from: comps)
        }
        return nil
    }

    private static func extractPriority(from text: String) -> Int {
        if text.contains("urgent") || text.contains("asap") || text.contains("immediately") { return 3 }
        if text.contains("important") || text.contains("high priority") { return 3 }
        if text.contains("whenever") || text.contains("low priority") || text.contains("eventually") { return 1 }
        return 0
    }
}

// MARK: - Errors (kept for backward compatibility)

enum BYOKError: LocalizedError {
    case networkError(String)
    case invalidAPIKey(String)
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .networkError(let msg):  return "Network error: \(msg)"
        case .invalidAPIKey(let p):   return "Invalid \(p) API key. Check your key in Settings."
        case .apiError(let msg):      return msg
        case .invalidResponse:        return "The AI service returned an unexpected response."
        }
    }
}
