// OnboardingView.swift
// First-launch onboarding: permissions, AI setup, quick tutorial

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var eventKitService = EventKitService()
    @State private var voiceService = VoiceRecordingService()

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "mic.fill",
            iconColor: .purple,
            title: "Meet Brief",
            subtitle: "Voice-first capture for everything",
            description: "Just speak. Brief listens, understands, and automatically sends reminders to Reminders, notes to Notes, and events to Calendar.",
            actionTitle: nil
        ),
        OnboardingPage(
            icon: "sparkles",
            iconColor: .purple,
            title: "Powered by AI",
            subtitle: "Understands natural language",
            description: "Say \"Remind me to call mom tomorrow at 3pm\" and Brief creates a reminder with an alarm. Say \"Note: the WiFi password is Brief123\" and it goes to Notes.",
            actionTitle: nil
        ),
        OnboardingPage(
            icon: "mic.badge.plus",
            iconColor: .red,
            title: "Microphone Access",
            subtitle: "Required for voice capture",
            description: "Brief needs microphone and speech recognition access to transcribe your voice. All processing happens on-device by default.",
            actionTitle: "Grant Microphone Access"
        ),
        OnboardingPage(
            icon: "checklist",
            iconColor: .blue,
            title: "Apple Apps",
            subtitle: "Sync to Reminders & Calendar",
            description: "Allow Brief to create reminders and calendar events on your behalf. You can review everything before it syncs.",
            actionTitle: "Allow Reminders & Calendar"
        ),
        OnboardingPage(
            icon: "figure.walk",
            iconColor: .green,
            title: "You're Ready",
            subtitle: "Start capturing",
            description: "Tap the microphone button and speak naturally. Try: \"Remind me to buy milk tomorrow\" or \"Note that I need to review the contract.\"",
            actionTitle: "Get Started"
        )
    ]

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.purple.opacity(0.1), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? Color.purple : Color.secondary.opacity(0.3))
                            .frame(width: i == currentPage ? 20 : 6, height: 6)
                            .animation(.spring(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.top, 24)

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Action button
                VStack(spacing: 12) {
                    if let action = pages[currentPage].actionTitle {
                        Button(action: { handleAction(for: currentPage) }) {
                            Text(action)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal, 24)
                    }

                    HStack {
                        if currentPage > 0 {
                            Button("Back") { withAnimation { currentPage -= 1 } }
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if currentPage < pages.count - 1 {
                            Button("Skip") { withAnimation { currentPage += 1 } }
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 48)
            }
        }
    }

    private func handleAction(for page: Int) {
        switch page {
        case 2: // Microphone access
            Task {
                await voiceService.requestPermissions()
                withAnimation { currentPage += 1 }
            }
        case 3: // Reminders & Calendar
            Task {
                try? await eventKitService.requestRemindersAccess()
                try? await eventKitService.requestCalendarAccess()
                withAnimation { currentPage += 1 }
            }
        case 4: // Get started
            SettingsViewModel.shared.hasCompletedOnboarding = true
            isPresented = false
        default:
            withAnimation { currentPage += 1 }
        }
    }
}

struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String
    let actionTitle: String?
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: page.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(page.iconColor)
            }

            // Text
            VStack(spacing: 10) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(page.subtitle)
                    .font(.title3)
                    .foregroundStyle(page.iconColor)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
    }
}
