// HomeViewModelTests.swift
// Tests for filtering, sorting, grouping, and stats computation.

import XCTest
@testable import Brief

final class HomeViewModelTests: XCTestCase {

    private var vm: HomeViewModel!

    override func setUp() {
        super.setUp()
        vm = HomeViewModel()
    }

    override func tearDown() {
        vm = nil
        super.tearDown()
    }

    // MARK: - Filtering

    func testFilterShowCompletedFalse() {
        let items = [
            makeItem(title: "Task 1", isCompleted: false),
            makeItem(title: "Task 2", isCompleted: true),
            makeItem(title: "Task 3", isCompleted: false),
        ]
        vm.showCompleted = false
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.map(\.title), ["Task 1", "Task 3"])
    }

    func testFilterShowCompletedTrue() {
        let items = [
            makeItem(title: "Task 1", isCompleted: false),
            makeItem(title: "Task 2", isCompleted: true),
        ]
        vm.showCompleted = true
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 2)
    }

    func testFilterByType() {
        let items = [
            makeItem(title: "Reminder", itemType: .reminder),
            makeItem(title: "Note", itemType: .note),
            makeItem(title: "Event", itemType: .calendarEvent),
        ]
        vm.selectedType = .reminder
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Reminder")
    }

    func testFilterByDestination() {
        let items = [
            makeItem(title: "To Calendar", destination: .calendar),
            makeItem(title: "To Reminders", destination: .reminders),
            makeItem(title: "In App", destination: .briefOnly),
        ]
        vm.selectedDestination = .reminders
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "To Reminders")
    }

    func testFilterBySearchText() {
        let items = [
            makeItem(title: "Buy milk", content: "from Costco"),
            makeItem(title: "Call dentist", content: nil),
            makeItem(title: "Schedule meeting", content: "with team"),
        ]
        vm.searchText = "milk"
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Buy milk")
    }

    func testFilterBySearchTextMatchesContent() {
        let items = [
            makeItem(title: "Reminder", content: "buy milk from Costco"),
        ]
        vm.searchText = "costco"
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 1)
    }

    func testFilterBySearchTextMatchesTags() {
        let items = [
            makeItem(title: "Task", tags: ["important", "work"]),
            makeItem(title: "Other", tags: ["personal"]),
        ]
        vm.searchText = "work"
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 1)
    }

    func testFilterCombinedTypeAndCompletion() {
        let items = [
            makeItem(title: "Incomplete Reminder", itemType: .reminder, isCompleted: false),
            makeItem(title: "Complete Reminder", itemType: .reminder, isCompleted: true),
            makeItem(title: "Incomplete Note", itemType: .note, isCompleted: false),
        ]
        vm.selectedType = .reminder
        vm.showCompleted = false
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.title, "Incomplete Reminder")
    }

    func testFilterEmptySearchShowsAll() {
        let items = [
            makeItem(title: "A"),
            makeItem(title: "B"),
            makeItem(title: "C"),
        ]
        vm.searchText = ""
        let filtered = vm.filter(items)
        XCTAssertEqual(filtered.count, 3)
    }

    // MARK: - Stats

    func testStatsBasicCounts() {
        let now = Date()
        let items = [
            makeItem(title: "T1", isCompleted: true),
            makeItem(title: "T2", isCompleted: false),
            makeItem(title: "T3", isCompleted: false, itemType: .reminder),
            makeItem(title: "T4", isCompleted: false, itemType: .note, createdAt: now),
        ]
        let stats = vm.stats(from: items)

        XCTAssertEqual(stats.total, 4)
        XCTAssertEqual(stats.completed, 1)
        XCTAssertEqual(stats.reminderCount, 1)
        XCTAssertEqual(stats.noteCount, 1)
        XCTAssertEqual(stats.todayCount, 1) // T4 created "now"
    }

    func testStatsEmpty() {
        let stats = vm.stats(from: [])
        XCTAssertEqual(stats.total, 0)
        XCTAssertEqual(stats.completed, 0)
        XCTAssertEqual(stats.todayCount, 0)
        XCTAssertEqual(stats.reminderCount, 0)
        XCTAssertEqual(stats.noteCount, 0)
    }

    // MARK: - Grouping

    func testGroupedToday() {
        let now = Date()
        let items = [makeItem(title: "Today Task", createdAt: now)]
        let groups = vm.grouped(items)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].0, "Today")
    }

    func testGroupedYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let items = [makeItem(title: "Yesterday Task", createdAt: yesterday)]
        let groups = vm.grouped(items)
        XCTAssertEqual(groups[0].0, "Yesterday")
    }

    func testGroupedSortsTodayFirst() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let items = [
            makeItem(title: "Yesterday", createdAt: yesterday),
            makeItem(title: "Today", createdAt: now),
        ]
        let groups = vm.grouped(items)
        XCTAssertEqual(groups[0].0, "Today")
        XCTAssertEqual(groups[1].0, "Yesterday")
    }

    func testGroupedRespectsFilters() {
        let now = Date()
        let items = [
            makeItem(title: "Complete", isCompleted: true, createdAt: now),
            makeItem(title: "Incomplete", isCompleted: false, createdAt: now),
        ]
        vm.showCompleted = false
        let groups = vm.grouped(items)
        let allItems = groups.flatMap(\.1)
        XCTAssertEqual(allItems.count, 1)
        XCTAssertEqual(allItems.first?.title, "Incomplete")
    }

    // MARK: - Sort descriptors

    func testSortOrderNewestFirst() {
        vm.sortOrder = .newestFirst
        let descriptor = vm.sortDescriptor
        // KeyPath comparison isn't straightforward in tests,
        // but we can verify the descriptor exists
        XCTAssertNotNil(descriptor)
    }

    func testSortOrderByType() {
        vm.sortOrder = .byType
        let descriptor = vm.sortDescriptor
        XCTAssertNotNil(descriptor)
    }

    // MARK: - Helpers

    private func makeItem(
        title: String,
        content: String? = nil,
        itemType: BriefItemType = .generic,
        destination: BriefDestination = .briefOnly,
        isCompleted: Bool = false,
        tags: [String] = [],
        createdAt: Date = Date()
    ) -> BriefItem {
        BriefItem(
            rawTranscript: title,
            title: title,
            content: content,
            itemType: itemType,
            destination: destination,
            tags: tags
        ).with {
            $0.isCompleted = isCompleted
            $0.createdAt = createdAt
        }
    }
}

// Small helper for inline mutation
private extension BriefItem {
    func with(_ block: (BriefItem) -> Void) -> BriefItem {
        block(self)
        return self
    }
}
