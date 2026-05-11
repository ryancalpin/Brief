// OnboardingView.swift
// First-launch onboarding: intro, permissions, Reminders, AI setup, Watch pairing

import SwiftUI
import WatchConnectivity

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var eventKitService = EventKitService()
    @State private var voiceService = VoiceRecordingService()
    @State private var openRouterKey = ""
    @State private var showingKeyEntry = false

    // Total pages depends on build mode
    private var pageCount: Int { 5 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.1), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page indicator
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule()
                            .fill(i == currentPage ? Color.purple : Color.secondary.opacity(0.3))
                            .frame(width: i == currentPage ? 20 : 6, height: 6)
                            .animation(.spring(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.top, 24)

                // Pages
                TabView(selection: $currentPage) {
                    page0.tag(0)
                    page1.tag(1)
                    page2.tag(2)
                    page3.tag(3)
                    page4.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Action area
                VStack(spacing: 12) {
                    actionButton
                    navRow
                }
                .padding(.bottom, 48)
            }
        }
    }

    // MARK: - Pages

    private var page0: some View {
        OnboardingPageView(
            icon: "mic.fill", iconColor: .purple,
            title: "Brief.", subtitle: "Just speak.",
            description: "Voice-first AI for iPhone and Apple Watch. Speak naturally — Brief captures todos, notes, and conversations automatically."
        )
    }

    private var page1: some View {
        OnboardingPageView(
            icon: "mic.badge.plus", iconColor: .red,
            title: "Microphone Access",
            subtitle: "Required for voice capture",
            description: "Brief needs microphone and speech recognition access to transcribe your voice. All processing happens on-device when possible."
        )
    }

    private var page2: some View {
        OnboardingPageView(
            icon: "checklist", iconColor: .blue,
            title: "Apple Reminders",
            subtitle: "Optional sync",
            description: "Your todos are always saved in Brief. Optionally sync them to Apple Reminders too."
        )
    }

    private var page3: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: "sparkles")
                    .font(.system(size: 52))
                    .foregroundStyle(.purple)
            }
            VStack(spacing: 10) {
                Text("AI Setup")
                    .font(.largeTitle.bold())
                if APIGatewayService.isAppStoreMode {
                    Text("AI is ready")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    Text("AI is included with your Brief Pro subscription. No setup required.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                } else {
                    Text("Add your OpenRouter key")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    Text("Brief uses OpenRouter for AI. Paste your free API key below, or skip to use offline mode.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    if !APIGatewayService.isAppStoreMode {
                        SecureField("sk-or-...", text: $openRouterKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 24)
                    }
                }
            }
            Spacer()
            Spacer()
        }
    }

    private var page4: some View {
        OnboardingPageView(
            icon: WCSession.isSupported() ? "applewatch" : "figure.walk",
            iconColor: .green,
            title: "You're Ready",
            subtitle: WCSession.isSupported() ? "Open Brief on your Apple Watch" : "Start capturing",
            description: WCSession.isSupported()
                ? "Brief works standalone on your wrist. Open the Watch app to start capturing from your watch."
                : "Tap the microphone button and speak naturally. Try: \"Remind me to buy milk tomorrow.\""
        )
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch currentPage {
        case 1:
            Button("Grant Microphone Access") {
                Task {
                    await voiceService.requestPermissions()
                    advance()
                }
            }
            .primaryButtonStyle()

        case 2:
            VStack(spacing: 8) {
                Button("Allow Reminders") {
                    Task {
                        try? await eventKitService.requestRemindersAccess()
                        SettingsViewModel.shared.remindersSyncEnabled = eventKitService.hasRemindersAccess
                        advance()
                    }
                }
                .primaryButtonStyle()
            }

        case 3:
            if !APIGatewayService.isAppStoreMode && !openRouterKey.isEmpty {
                Button("Save Key") {
                    KeychainService.shared.write(key: .openRouterKey, value: openRouterKey)
                    SettingsViewModel.shared.openRouterKey = openRouterKey
                    advance()
                }
                .primaryButtonStyle()
            }

        case 4:
            Button("Get Started") {
                SettingsViewModel.shared.hasCompletedOnboarding = true
                isPresented = false
            }
            .primaryButtonStyle()

        default:
            EmptyView()
        }
    }

    private var navRow: some View {
        HStack {
            if currentPage > 0 {
                Button("Back") { withAnimation { currentPage -= 1 } }
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if currentPage < pageCount - 1 {
                Button("Skip") { advance() }
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
    }

    private func advance() {
        withAnimation { currentPage = min(currentPage + 1, pageCount - 1) }
    }
}

// MARK: - Supporting views

struct OnboardingPageView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(iconColor)
            }
            VStack(spacing: 10) {
                Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(subtitle).font(.title3).foregroundStyle(iconColor).multilineTextAlignment(.center)
                Text(description).font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
    }
}

private extension View {
    func primaryButtonStyle() -> some View {
        self
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 24)
    }
}
