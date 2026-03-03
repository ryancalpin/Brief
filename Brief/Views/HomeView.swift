// HomeView.swift
// Main list view showing all captured items with filtering and search

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [BriefItem]

    @State private var homeVM = HomeViewModel()
    @State private var showingRecording = false
    @State private var showingSettings = false
    @State private var selectedItem: BriefItem?

    // Injected from parent
    var recordingVM: RecordingViewModel

    init(recordingVM: RecordingViewModel) {
        self.recordingVM = recordingVM
    }

    private var filteredGroups: [(String, [BriefItem])] {
        homeVM.grouped(allItems)
    }

    var body: some View {
        NavigationStack {
            Group {
                if allItems.isEmpty {
                    EmptyStateView(onRecord: { showingRecording = true })
                } else {
                    itemList
                }
            }
            .navigationTitle("Brief")
            .searchable(text: $homeVM.searchText, prompt: "Search notes, reminders…")
            .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showingRecording) {
            RecordingView(vm: recordingVM)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $selectedItem) { item in
            ItemDetailView(item: item, recordingVM: recordingVM)
        }
        .onReceive(NotificationCenter.default.publisher(for: .briefStartRecording)) { _ in
            showingRecording = true
        }
        .task {
            recordingVM.setModelContext(modelContext)
            await recordingVM.processPendingTranscript()
        }
    }

    // MARK: - List

    private var itemList: some View {
        List {
            // Stats strip
            if homeVM.searchText.isEmpty {
                statsSection
            }

            // Filter chips
            filterChips
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            // Grouped items
            ForEach(filteredGroups, id: \.0) { groupName, items in
                Section(groupName) {
                    ForEach(items) { item in
                        ItemRow(item: item) {
                            recordingVM.toggleComplete(item)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItem = item }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                recordingVM.deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if item.destination == .reminders || item.itemType == .reminder {
                                Button {
                                    recordingVM.toggleComplete(item)
                                } label: {
                                    Label(item.isCompleted ? "Undo" : "Complete",
                                          systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: allItems.count)
    }

    // MARK: - Stats strip

    private var statsSection: some View {
        let stats = homeVM.stats(from: allItems)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatChip(value: stats.todayCount, label: "Today", icon: "sun.max.fill", color: .orange)
                StatChip(value: stats.reminderCount, label: "Reminders", icon: "checklist", color: .blue)
                StatChip(value: stats.noteCount, label: "Notes", icon: "note.text", color: .yellow)
            }
            .padding(.vertical, 4)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Type filters
                ForEach(BriefItemType.allCases, id: \.self) { type in
                    FilterChip(
                        label: type.displayName,
                        icon: type.systemImage,
                        isSelected: homeVM.selectedType == type
                    ) {
                        homeVM.selectedType = homeVM.selectedType == type ? nil : type
                    }
                }

                Divider().frame(height: 20)

                // Show completed toggle
                FilterChip(
                    label: "Completed",
                    icon: "checkmark.circle",
                    isSelected: homeVM.showCompleted
                ) {
                    homeVM.showCompleted.toggle()
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $homeVM.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.displayName).tag(order)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }

        ToolbarItem(placement: .bottomBar) {
            HStack {
                Spacer()
                Button {
                    showingRecording = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 56, height: 56)
                            .shadow(color: .purple.opacity(0.4), radius: 8, y: 4)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }
}

// MARK: - Supporting Views

struct ItemRow: View {
    let item: BriefItem
    let onToggleComplete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Completion button for reminders
            if item.itemType == .reminder || item.destination == .reminders {
                Button(action: onToggleComplete) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: item.itemType.systemImage)
                    .font(.body)
                    .foregroundStyle(.purple)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    // Due date badge
                    if let due = item.dueDate {
                        Label(due.formatted(.relative(presentation: .named)), systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(due < Date() && !item.isCompleted ? .red : .secondary)
                    }

                    // Destination badge
                    if item.destination != .briefOnly {
                        Text(item.destination.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                    // Synced badge
                    if !item.syncedToApple && item.destination != .briefOnly {
                        Image(systemName: "icloud.slash")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .opacity(item.isCompleted ? 0.6 : 1.0)
    }
}

struct StatChip: View {
    let value: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text("\(value)")
                    .font(.headline.monospacedDigit())
            }
            .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.purple : Color.secondary.opacity(0.12),
                            in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}

struct EmptyStateView: View {
    let onRecord: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Items Yet", systemImage: "mic.fill")
        } description: {
            Text("Hold the microphone button and speak.\nBrief will capture notes, reminders, and events automatically.")
        } actions: {
            Button("Start Recording", action: onRecord)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
        }
    }
}
