// ItemDetailView.swift
// Full detail view for a single BriefItem with editing support

import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: BriefItem
    let recordingVM: RecordingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            Form {
                // Item header
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
                            Text(item.itemType.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.destination.displayName)
                                .font(.caption)
                                .foregroundStyle(typeColor)
                        }
                        Spacer()
                        if item.isCompleted {
                            Label("Completed", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Title
                Section("Title") {
                    if isEditing {
                        TextField("Title", text: $item.title, axis: .vertical)
                    } else {
                        Text(item.title)
                            .strikethrough(item.isCompleted)
                    }
                }

                // Content
                if let content = item.content, !content.isEmpty, !isEditing {
                    Section("Notes") {
                        Text(content)
                            .foregroundStyle(.secondary)
                    }
                }

                if isEditing {
                    Section("Notes") {
                        TextField("Additional notes…", text: Binding(
                            get: { item.content ?? "" },
                            set: { item.content = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                        .lineLimit(4...)
                    }
                }

                // Scheduling
                if item.dueDate != nil || item.startDate != nil || isEditing {
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
                        } else if let due = item.dueDate {
                            if isEditing {
                                DatePicker("Due Date", selection: Binding(
                                    get: { due },
                                    set: { item.dueDate = $0 }
                                ))
                            } else {
                                LabeledContent("Due") {
                                    Text(due.formatted(date: .abbreviated, time: .shortened))
                                        .foregroundStyle(due < Date() && !item.isCompleted ? .red : .primary)
                                }
                            }
                        }

                        if let location = item.location {
                            LabeledContent("Location") {
                                Text(location)
                            }
                        }
                    }
                }

                // Tags
                if !item.tags.isEmpty {
                    Section("Tags") {
                        FlowLayout(spacing: 6) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.purple)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                // Original transcript
                Section("Original Voice Input") {
                    Text(item.rawTranscript)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Sync status
                Section {
                    SyncStatusRow(item: item, recordingVM: recordingVM)
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        recordingVM.deleteItem(item)
                        dismiss()
                    } label: {
                        Label("Delete Item", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Edit") {
                        if isEditing {
                            item.updatedAt = Date()
                        }
                        isEditing.toggle()
                    }
                }
            }
        }
    }

    private var typeColor: Color {
        switch item.itemType {
        case .reminder:      return .blue
        case .note:          return .yellow
        case .calendarEvent: return .red
        case .list:          return .green
        case .generic:       return .purple
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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !item.syncedToApple && item.destination == .notes {
                Button("Open Notes") {
                    recordingVM.syncItemToNotes(item)
                }
                .font(.caption)
                .buttonStyle(.bordered)
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
            if x + size.width > width {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
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
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
