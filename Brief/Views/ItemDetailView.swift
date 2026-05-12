// ItemDetailView.swift
// Full detail view for a single BriefItem with editing and re-parse support

import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: BriefItem
    let recordingVM: RecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isEditing = false
    @State private var isReparsing = false
    @State private var reparseError: String?
    @State private var showReparseSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                titleSection
                contentSection
                transcriptSection
                scheduleSection
                if item.itemType == .reminder || item.itemType == .list {
                    reminderSection
                }
                if !item.tags.isEmpty { tagsSection }
                syncSection
                dangerSection
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing { item.updatedAt = Date() }
                        isEditing.toggle()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(typeColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.itemType.systemImage)
                        .font(.title3)
                        .foregroundStyle(typeColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.itemType.displayName).font(.caption).foregroundStyle(.secondary)
                    Text(item.destination.displayName).font(.caption).foregroundStyle(typeColor)
                }
                Spacer()
                if item.isCompleted {
                    Label("Completed", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        }
    }

    private var titleSection: some View {
        Section("Title") {
            if isEditing {
                TextField("Title", text: $item.title, axis: .vertical)
            } else {
                Text(item.title).strikethrough(item.isCompleted)
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if isEditing {
            Section("Notes") {
                TextField("Additional notes…", text: Binding(
                    get: { item.content ?? "" },
                    set: { item.content = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(4...)
            }
        } else if let content = item.content, !content.isEmpty {
            Section("Notes") {
                Text(content).foregroundStyle(.secondary)
            }
        }
    }

    // Always-editable transcript field with Re-parse button
    private var transcriptSection: some View {
        Section {
            TextEditor(text: Binding(
                get: { item.rawTranscript },
                set: { newVal in
                    if newVal != item.rawTranscript {
                        item.rawTranscript = newVal
                        item.isEdited = true
                    }
                }
            ))
            .frame(minHeight: 60)

            if item.isEdited {
                if isReparsing {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Re-parsing…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button("Re-parse") { Task { await reparseItem() } }
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                }
                if let err = reparseError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                if showReparseSuccess {
                    Label("Updated", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }
            }
        } header: {
            Text("Transcript")
        } footer: {
            if item.isEdited {
                Text("Transcript has been edited. Tap Re-parse to update this item.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private var scheduleSection: some View {
        // Reminder/list due dates are rendered by reminderSection — skip them here
        // to avoid a duplicate "Due Date" picker.
        let isReminderLike = item.itemType == .reminder || item.itemType == .list
        if !isReminderLike, item.dueDate != nil || item.startDate != nil || isEditing {
            Section("Schedule") {
                if item.itemType == .calendarEvent {
                    if isEditing {
                        DatePicker("Start", selection: Binding(
                            get: { item.startDate ?? Date() },
                            set: { item.startDate = $0 }
                        ))
                        DatePicker("End", selection: Binding(
                            get: { item.endDate ?? Date().addingTimeInterval(3600) },
                            set: { item.endDate = $0 }
                        ))
                    } else if let start = item.startDate {
                        LabeledContent("Start") {
                            Text(start.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let end = item.endDate {
                            LabeledContent("End") {
                                Text(end.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    }
                } else if item.dueDate != nil || isEditing {
                    DatePicker("Due Date", selection: Binding(
                        get: { item.dueDate ?? Date() },
                        set: { item.dueDate = $0 }
                    ))
                }
                if let location = item.location {
                    LabeledContent("Location") { Text(location) }
                }
            }
        }
    }

    private var reminderSection: some View {
        Section("Reminder") {
            // Due date
            if isEditing || item.dueDate != nil {
                DatePicker("Due Date", selection: Binding(
                    get: { item.dueDate ?? Date() },
                    set: { item.dueDate = $0 }
                ))
            }
            // Priority picker
            Picker("Priority", selection: Binding<String>(
                get: { item.priorityRaw ?? "none" },
                set: { item.priorityRaw = $0 == "none" ? nil : $0 }
            )) {
                Text("None").tag("none")
                ForEach(BriefPriority.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p.rawValue)
                }
            }
            // Completion toggle — binding mutates isCompleted directly,
            // then onChange runs side effects without re-toggling.
            Toggle("Completed", isOn: $item.isCompleted)
                .onChange(of: item.isCompleted) { _, _ in
                    recordingVM.applyCompletionSideEffects(item)
                }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            FlowLayout(spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                        .foregroundStyle(.purple)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var syncSection: some View {
        Section {
            SyncStatusRow(item: item, recordingVM: recordingVM)
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                recordingVM.deleteItem(item)
                dismiss()
            } label: {
                Label("Delete Item", systemImage: "trash").foregroundStyle(.red)
            }
        }
    }

    // MARK: - Re-parse

    private func reparseItem() async {
        isReparsing = true
        reparseError = nil
        showReparseSuccess = false
        do {
            let openRouter = OpenRouterService.shared
            let result = try await openRouter.parse(transcript: item.rawTranscript)
            item.title    = result.title
            item.content  = result.body
            if let due = result.dueDate { item.dueDate = due }
            item.tags     = result.tags
            item.isEdited = false
            try? modelContext.save()
            showReparseSuccess = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showReparseSuccess = false
            }
        } catch {
            reparseError = error.localizedDescription
        }
        isReparsing = false
    }

    // MARK: - Type color

    private var typeColor: Color {
        switch item.itemType {
        case .reminder:      return .blue
        case .note:          return .yellow
        case .calendarEvent: return .red
        case .list:          return .green
        case .generic:       return .purple
        case .convo:         return .indigo
        }
    }
}

// MARK: - Sync Status Row

struct SyncStatusRow: View {
    let item: BriefItem
    let recordingVM: RecordingViewModel

    var body: some View {
        HStack {
            Image(systemName: item.syncedToApple ? "checkmark.icloud.fill" : "icloud.slash")
                .foregroundStyle(item.syncedToApple ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.syncedToApple ? "Synced to \(item.destination.displayName)" : "Not yet synced")
                    .font(.subheadline)
                if let id = item.externalIdentifier {
                    Text("ID: \(id.prefix(12))…")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if let err = item.syncError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }
            Spacer()
            if !item.syncedToApple && item.destination == .notes {
                Button("Open Notes") { recordingVM.syncItemToNotes(item) }
                    .font(.caption).buttonStyle(.bordered)
            }
        }
        .listRowSeparator(.hidden)
    }
}

// MARK: - FlowLayout for tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width { x = 0; height += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
