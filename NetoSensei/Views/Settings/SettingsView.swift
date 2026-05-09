//
//  SettingsView.swift
//  NetoSensei
//
//  App-wide settings sheet: AI provider settings, About, legal links, support.
//

import SwiftUI

extension Bundle {
    /// Formatted as "v1.0 (19)" using CFBundleShortVersionString + CFBundleVersion.
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private struct IdentifiedURL: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    @State private var showingAISettings = false
    @State private var browserURL: IdentifiedURL?

    private let privacyURL = URL(string: "https://tdot1212.github.io/NetoSensei/privacy.html")
    private let termsURL = URL(string: "https://tdot1212.github.io/NetoSensei/terms.html")
    private let supportEmailURL = URL(string: "mailto:toshlabs.dev+netosensei@gmail.com")

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        showingAISettings = true
                    } label: {
                        Label("AI Provider Settings", systemImage: "brain")
                            .foregroundColor(.primary)
                    }
                } header: {
                    Text("AI Assistant")
                }

                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.appVersion)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        if let privacyURL { browserURL = IdentifiedURL(url: privacyURL) }
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                            .foregroundColor(.primary)
                    }

                    Button {
                        if let termsURL { browserURL = IdentifiedURL(url: termsURL) }
                    } label: {
                        Label("Terms of Service", systemImage: "doc.text.fill")
                            .foregroundColor(.primary)
                    }

                    Button {
                        if let supportEmailURL { UIApplication.shared.open(supportEmailURL) }
                    } label: {
                        Label("Support Email", systemImage: "envelope.fill")
                            .foregroundColor(.primary)
                    }

                    Button {
                        hasCompletedOnboarding = false
                        dismiss()
                    } label: {
                        Label("Show Welcome Again", systemImage: "sparkles")
                            .foregroundColor(.primary)
                    }
                } header: {
                    Text("About")
                }

                Section {
                    Text("Built by Tosh")
                        .foregroundColor(.secondary)
                } header: {
                    Text("Acknowledgments")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAISettings) {
                AISettingsView()
            }
            .sheet(item: $browserURL) { wrapped in
                InAppBrowserView(url: wrapped.url)
            }
        }
    }
}
