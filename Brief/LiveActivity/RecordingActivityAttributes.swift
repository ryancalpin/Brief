// RecordingActivityAttributes.swift
// Dynamic Island and Lock Screen Live Activity for voice recording state

import Foundation
import ActivityKit
import SwiftUI

// MARK: - Activity Attributes

struct RecordingActivityAttributes: ActivityAttributes {
    public typealias RecordingState = ContentState

    /// Dynamic state that updates during the activity
    public struct ContentState: Codable, Hashable {
        var isRecording: Bool
        var liveTranscript: String
        var processingStatus: ProcessingStatus
        var durationSeconds: Int

        enum ProcessingStatus: String, Codable {
            case idle
            case recording
            case processing
            case done
            case failed
        }

        var statusText: String {
            switch processingStatus {
            case .idle:       return "Ready"
            case .recording:  return "Recording…"
            case .processing: return "Processing…"
            case .done:       return "Done"
            case .failed:     return "Failed"
            }
        }
    }

    /// Static data set at activity creation (doesn't change)
    var startedAt: Date
}

// MARK: - Live Activity Manager

@MainActor
final class RecordingActivityManager: ObservableObject {

    private var currentActivity: Activity<RecordingActivityAttributes>?

    func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = RecordingActivityAttributes(startedAt: Date())
        let initialState = RecordingActivityAttributes.ContentState(
            isRecording: true,
            liveTranscript: "",
            processingStatus: .recording,
            durationSeconds: 0
        )

        do {
            currentActivity = try Activity<RecordingActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
        } catch {
            // Live Activities may not be available in all environments
            print("Brief: Failed to start Live Activity: \(error)")
        }
    }

    func updateTranscript(_ transcript: String, duration: Int) {
        Task {
            let state = RecordingActivityAttributes.ContentState(
                isRecording: true,
                liveTranscript: transcript,
                processingStatus: .recording,
                durationSeconds: duration
            )
            await currentActivity?.update(.init(state: state, staleDate: nil))
        }
    }

    func showProcessing() {
        Task {
            let state = RecordingActivityAttributes.ContentState(
                isRecording: false,
                liveTranscript: "",
                processingStatus: .processing,
                durationSeconds: 0
            )
            await currentActivity?.update(.init(state: state, staleDate: nil))
        }
    }

    func endActivity(success: Bool, finalTitle: String? = nil) {
        Task {
            let state = RecordingActivityAttributes.ContentState(
                isRecording: false,
                liveTranscript: finalTitle ?? "",
                processingStatus: success ? .done : .failed,
                durationSeconds: 0
            )
            await currentActivity?.end(
                .init(state: state, staleDate: nil),
                dismissalPolicy: .after(.now + 3)
            )
            currentActivity = nil
        }
    }
}

// MARK: - Dynamic Island Views

/// Compact leading view (shown in the pill when something else is in the Dynamic Island)
struct RecordingCompactLeadingView: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.isRecording ? "mic.fill" : "waveform")
            .foregroundStyle(state.isRecording ? .red : .secondary)
            .symbolEffect(.bounce, isActive: state.isRecording)
    }
}

/// Compact trailing view
struct RecordingCompactTrailingView: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Text(state.isRecording ? formatDuration(state.durationSeconds) : state.statusText)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(state.isRecording ? .red : .secondary)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Minimal view (tiny dot when there are two Live Activities)
struct RecordingMinimalView: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Image(systemName: "mic.fill")
            .foregroundStyle(state.isRecording ? .red : .primary)
    }
}

/// Expanded Dynamic Island view (shown when user taps the island)
struct RecordingExpandedView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: context.state.isRecording ? "mic.fill" : "sparkles")
                    .foregroundStyle(context.state.isRecording ? .red : .purple)
                    .symbolEffect(.bounce, isActive: context.state.isRecording)
                Text("Brief")
                    .font(.headline)
                Spacer()
                Text(context.state.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !context.state.liveTranscript.isEmpty {
                Text(context.state.liveTranscript)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            } else if context.state.processingStatus == .processing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.purple)
            }
        }
        .padding()
    }
}

/// Lock Screen Live Activity view
struct RecordingLockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(context.state.isRecording ? Color.red.opacity(0.2) : Color.purple.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: context.state.isRecording ? "mic.fill" : "sparkles")
                    .foregroundStyle(context.state.isRecording ? .red : .purple)
                    .symbolEffect(.pulse, isActive: context.state.isRecording)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Brief")
                    .font(.headline)
                Text(context.state.liveTranscript.isEmpty ? context.state.statusText : context.state.liveTranscript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if context.state.isRecording {
                Text(timerInterval: context.attributes.startedAt...Date.distantFuture,
                     countsDown: false)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}
