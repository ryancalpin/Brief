// WatchRecordingView.swift
// Push-to-talk recording interface for Apple Watch

import SwiftUI

struct WatchRecordingView: View {
    @EnvironmentObject var vm: WatchViewModel
    @State private var isHolding = false

    var body: some View {
        ZStack {
            // Background
            Color(.black).ignoresSafeArea()

            VStack(spacing: 8) {
                switch vm.phase {
                case .idle:
                    idleView
                case .recording:
                    recordingView
                case .sending, .waitingForResult:
                    sendingView
                case .done(let item):
                    doneView(item: item)
                case .error(let error):
                    errorView(error: error)
                }
            }
        }
        .navigationTitle("Brief")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Phase views

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 40))
                .foregroundStyle(.purple.opacity(0.6))

            Text("Hold to record")
                .font(.headline)
                .multilineTextAlignment(.center)

            recordButton
        }
    }

    private var recordingView: some View {
        VStack(spacing: 8) {
            // Live transcript (max 3 lines)
            if !vm.liveTranscript.isEmpty {
                Text(vm.liveTranscript)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            } else {
                Label("Listening…", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }

            Text(vm.formattedDuration)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.red)

            recordButton
        }
    }

    private var sendingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.purple)

            Text(vm.phase == .sending as? Bool ?? false
                 ? "Sending to iPhone…"
                 : "Processing…")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }

    private func doneView(item: SharedBriefItem) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)

            Text(item.title)
                .font(.caption.bold())
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text("→ \(item.destination.displayName)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Done") { vm.dismiss() }
                .font(.caption)
                .foregroundStyle(.purple)
        }
        .onAppear {
            WKInterfaceDevice.current().play(.success)
        }
    }

    private func errorView(error: Error) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again") { vm.dismiss() }
                .font(.caption)
                .foregroundStyle(.purple)
        }
        .onAppear { WKInterfaceDevice.current().play(.failure) }
    }

    // MARK: - Record button

    private var recordButton: some View {
        Button {
            Task {
                if vm.isRecording {
                    await vm.stopRecording()
                } else {
                    await vm.startRecording()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(vm.isRecording ? Color.red : Color.purple)
                    .frame(width: 60, height: 60)

                Image(systemName: vm.isRecording ? "stop.fill" : "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Watch Item List View

struct WatchItemListView: View {
    @EnvironmentObject var connectivity: WatchConnectivityHandler

    var body: some View {
        NavigationStack {
            if connectivity.recentItems.isEmpty {
                ContentUnavailableView("No Items", systemImage: "mic.fill")
            } else {
                List {
                    ForEach(connectivity.recentItems.prefix(10)) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .strikethrough(item.isCompleted)
                            HStack {
                                Image(systemName: item.itemType.systemImage)
                                    .font(.caption2)
                                Text(item.destination.displayName)
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.elliptical)
                .navigationTitle("Recent")
            }
        }
    }
}
