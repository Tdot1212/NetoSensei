//
//  OnboardingView.swift
//  NetoSensei
//
//  3-card first-launch walkthrough. Persists completion via
//  @AppStorage("hasCompletedOnboarding"); a re-launch with the flag
//  set won't show this again. Reachable later from
//  SettingsView → "Show Welcome Again".
//

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    private let cards: [OnboardingCard.Content] = [
        .init(
            symbol: "antenna.radiowaves.left.and.right",
            title: "Diagnose your network",
            body: "NetoSensei tests your WiFi, internet, VPN, and DNS to find what's slow or broken — and explains it in plain language."
        ),
        .init(
            symbol: "lock.shield",
            title: "Your data stays on your device",
            body: "All scan results and history are stored locally. We don't operate a server. The optional AI Assistant sends your typed messages and current network state directly to your chosen AI provider — never to us."
        ),
        .init(
            symbol: "sparkles",
            title: "AI Assistant is optional",
            body: "To use the AI Assistant, tap the sparkle button on Home and add your own API key from OpenAI, Anthropic, DeepSeek, Gemini, or Groq. Without a key, all other features still work."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Skip button row
            HStack {
                Spacer()
                Button("Skip") {
                    completeOnboarding()
                }
                .padding()
            }

            // Card pager
            TabView(selection: $currentPage) {
                ForEach(cards.indices, id: \.self) { idx in
                    OnboardingCard(content: cards[idx])
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Get Started CTA on last card; placeholder on earlier cards
            // so layout doesn't jump.
            ZStack {
                if currentPage == cards.count - 1 {
                    Button(action: completeOnboarding) {
                        Text("Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(height: 50)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.2), value: currentPage)
        }
        .background(Color(.systemBackground))
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}

struct OnboardingCard: View {
    struct Content {
        let symbol: String
        let title: String
        let body: String
    }
    let content: Content

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: content.symbol)
                .font(.system(size: 80, weight: .light))
                .foregroundColor(.blue)
                .padding(.bottom, 8)

            Text(content.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text(content.body)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
    }
}
