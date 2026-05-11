// ConvoView.swift
// Chat thread view for AI conversation items grouped by sessionID

import SwiftUI
import SwiftData

struct ConvoView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<BriefItem> { $0.itemTypeRaw == "convo" },
        sort: \BriefItem.createdAt
    ) private var convoItems: [BriefItem]

    var recordingVM: RecordingViewModel

    private var groupedSessions: [(UUID?, [BriefItem])] {
        var result: [(UUID?, [BriefItem])] = []
        var seen: [UUID?: Bool] = [:]
        for item in convoItems {
            let key = item.sessionID
            if seen[key] == nil {
                seen[key] = true
                let group = convoItems.filter { $0.sessionID == key }
                result.append((key, group))
            }
        }
        return result
    }

    var body: some View {
        Group {
            if convoItems.isEmpty {
                ContentUnavailableView {
                    Label("No Conversations", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Ask Brief anything. Hold the mic and speak a question or share a thought.")
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(groupedSessions, id: \.0) { sessionID, items in
                                SessionDivider(item: items.first)
                                ForEach(items) { item in
                                    ConvoBubblePair(item: item, recordingVM: recordingVM)
                                        .id(item.id)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: convoItems.count) { _, _ in
                        if let last = convoItems.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Session Divider

private struct SessionDivider: View {
    let item: BriefItem?

    var body: some View {
        HStack {
            VStack { Divider() }
            if let date = item?.createdAt {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            VStack { Divider() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Bubble Pair

private struct ConvoBubblePair: View {
    let item: BriefItem
    let recordingVM: RecordingViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // User transcript — right-aligned
            HStack {
                Spacer(minLength: 48)
                Text(item.rawTranscript)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.purple, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
            }

            // AI response — left-aligned
            if let response = item.aiResponse, !response.isEmpty {
                HStack {
                    Text(response)
                        .font(.body)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 48)
                }
            }

            // Timestamp
            Text(item.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                saveAsNote(item)
            } label: {
                Label("Save as Note", systemImage: "note.text.badge.plus")
            }
        }
    }

    private func saveAsNote(_ item: BriefItem) {
        let note = BriefItem(
            rawTranscript: item.rawTranscript,
            title: item.title,
            content: item.aiResponse ?? item.rawTranscript,
            itemType: .note,
            destination: .notes
        )
        modelContext.insert(note)
        try? modelContext.save()
    }
}
