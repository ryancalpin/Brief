// RecordingView.swift
// Push-to-talk recording interface with live transcript and waveform

import SwiftUI

struct RecordingView: View {
    @Bindable var vm: RecordingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        Task { await vm.cancelRecording() }
                        dismiss()
                    }
                    .foregroundStyle(.secondary)
                    Spacer()
                    if vm.isRecording {
                        Label(vm.formattedDuration, systemImage: "circle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline.monospacedDigit())
                            .symbolEffect(.pulse)
                    }
                }
                .padding()

                Spacer()

                // Live transcript area
                Group {
                    if vm.isProcessing {
                        ProcessingView()
                    } else if !vm.liveTranscript.isEmpty {
                        TranscriptView(text: vm.liveTranscript)
                    } else if vm.isRecording {
                        Text("Listening…")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.purple.opacity(0.3))
                            Text("Hold to record")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("Brief will create reminders, notes,\nor calendar events automatically")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)

                Spacer()

                // Waveform visualizer
                if vm.isRecording {
                    WaveformView(level: vm.audioLevel)
                        .frame(height: 48)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale))
                }

                // Push-to-talk button
                PushToTalkButton(
                    isRecording: vm.isRecording,
                    isProcessing: vm.isProcessing
                ) {
                    Task {
                        if vm.isRecording {
                            await vm.stopRecording()
                        } else {
                            await vm.startRecording()
                        }
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .animation(.spring(duration: 0.3), value: vm.isRecording)
        .animation(.spring(duration: 0.3), value: vm.isProcessing)
        .sheet(item: Binding(
            get: {
                if case .reviewing(let item) = vm.phase { return item }
                return nil
            },
            set: { _ in vm.dismissReview() }
        )) { item in
            ItemReviewSheet(item: item, vm: vm)
        }
        .alert("Error", isPresented: Binding(
            get: { if case .error = vm.phase { return true } else { return false } },
            set: { if !$0 { vm.dismissReview() } }
        )) {
            Button("OK") { vm.dismissReview() }
        } message: {
            if case .error(let error) = vm.phase {
                Text(error.localizedDescription)
            }
        }
    }
}

// MARK: - Subviews

struct PushToTalkButton: View {
    let isRecording: Bool
    let isProcessing: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer pulse ring
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 110, height: 110)
                        .symbolEffect(.pulse)
                }

                Circle()
                    .fill(buttonColor)
                    .frame(width: 88, height: 88)
                    .shadow(color: buttonColor.opacity(0.4), radius: 12, y: 4)

                Image(systemName: buttonIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isRecording)
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(.spring(duration: 0.2), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var buttonColor: Color {
        if isProcessing { return .gray }
        return isRecording ? .red : .purple
    }

    private var buttonIcon: String {
        if isProcessing { return "ellipsis" }
        return isRecording ? "stop.fill" : "mic.fill"
    }
}

struct WaveformView: View {
    let level: Float
    private let barCount = 24

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    let height = barHeight(for: i, in: geo.size.height)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.gradient)
                        .frame(width: (geo.size.width - CGFloat(barCount - 1) * 3) / CGFloat(barCount),
                               height: height)
                        .animation(.spring(duration: 0.1), value: level)
                }
            }
        }
    }

    private func barHeight(for index: Int, in maxHeight: CGFloat) -> CGFloat {
        // Distribute level across bars with some variation
        let center = Float(barCount) / 2
        let distance = abs(Float(index) - center) / center
        let variance = (1.0 - distance * 0.5) * level
        let noise = Float.random(in: 0.5...1.0)
        let normalized = min(max(variance * noise, 0.05), 1.0)
        return CGFloat(normalized) * maxHeight
    }
}

struct TranscriptView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
        }
        .frame(maxHeight: 200)
    }
}

struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.purple)
                .symbolEffect(.pulse)
            Text("Processing with AI…")
                .font(.headline)
            Text("Identifying type and destination")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Review Sheet (shown after AI processing)

struct ItemReviewSheet: View {
    let item: BriefItem
    let vm: RecordingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("What Brief heard") {
                    Text(item.rawTranscript)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Section("Processed as") {
                    LabeledContent("Type") {
                        Label(item.itemType.displayName, systemImage: item.itemType.systemImage)
                    }
                    LabeledContent("Send to") {
                        Label(item.destination.displayName, systemImage: item.destination.systemImage)
                    }
                    LabeledContent("Title") {
                        Text(item.title)
                    }
                    if let content = item.content {
                        LabeledContent("Content") {
                            Text(content).lineLimit(3)
                        }
                    }
                    if let due = item.dueDate {
                        LabeledContent("Due") {
                            Text(due.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                if item.destination == .notes && !item.syncedToApple {
                    Section {
                        Button {
                            vm.syncItemToNotes(item)
                        } label: {
                            Label("Open in Notes", systemImage: "note.text.badge.plus")
                        }
                    }
                }

                if let aiProvider = item.aiProviderUsed {
                    Section {
                        Label("Processed by \(aiProvider)", systemImage: "cpu")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        vm.dismissReview()
                    }
                }
            }
        }
    }
}
