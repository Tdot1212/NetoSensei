//
//  AISettingsView.swift
//  NetoSensei
//
//  Manage AI provider API keys, model selection, and chat history.
//

import SwiftUI

struct AISettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var chatService = AIChatService.shared

    @State private var selectedProvider: AIProvider?
    @State private var apiKeyInput = ""
    @State private var testResult: (success: Bool, message: String)?
    @State private var isTesting = false
    @State private var defaultProvider: AIProvider = AIKeyManager.shared.defaultProvider
    @State private var selectedModel: String = AIKeyManager.shared.selectedModel
    @State private var showingDeleteConfirm = false

    var body: some View {
        NavigationView {
            List {
                // Default provider picker
                Section {
                    Picker("Default Provider", selection: $defaultProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            HStack {
                                Image(systemName: provider.iconName)
                                Text(provider.rawValue)
                            }
                            .tag(provider)
                        }
                    }
                    .onChange(of: defaultProvider) { newValue in
                        AIKeyManager.shared.defaultProvider = newValue
                        selectedModel = newValue.defaultModel
                        AIKeyManager.shared.selectedModel = newValue.defaultModel
                    }
                } header: {
                    Text("Default AI Provider")
                }

                // Model selection
                if AIKeyManager.shared.hasKey(for: defaultProvider) {
                    Section {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(defaultProvider.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: selectedModel) { newValue in
                            AIKeyManager.shared.selectedModel = newValue
                        }
                    } header: {
                        Text("Model")
                    } footer: {
                        Text("Different models have different capabilities and pricing.")
                    }
                }

                // Provider list with key management
                Section {
                    ForEach(AIProvider.allCases) { provider in
                        AISettingsProviderRow(
                            provider: provider,
                            hasKey: AIKeyManager.shared.hasKey(for: provider),
                            isSelected: selectedProvider == provider,
                            onTap: {
                                withAnimation {
                                    if selectedProvider == provider {
                                        selectedProvider = nil
                                    } else {
                                        selectedProvider = provider
                                        apiKeyInput = AIKeyManager.shared.getKey(for: provider) ?? ""
                                        testResult = nil
                                    }
                                }
                            }
                        )

                        // Expanded key editor
                        if selectedProvider == provider {
                            VStack(alignment: .leading, spacing: 12) {
                                SecureField("Paste API key here", text: $apiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                HStack(spacing: 12) {
                                    Button("Save") {
                                        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                        AIKeyManager.shared.saveKey(trimmed, for: provider)
                                        AIKeyManager.shared.refreshConfiguredCount()
                                        testResult = nil
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(apiKeyInput.isEmpty)

                                    Button("Test") {
                                        testConnection(provider: provider)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(apiKeyInput.isEmpty || isTesting)

                                    if AIKeyManager.shared.hasKey(for: provider) {
                                        Button("Delete", role: .destructive) {
                                            AIKeyManager.shared.deleteKey(for: provider)
                                            AIKeyManager.shared.refreshConfiguredCount()
                                            apiKeyInput = ""
                                            testResult = nil
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    }
                                }

                                if let result = testResult {
                                    HStack(spacing: 6) {
                                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(result.success ? .green : .red)
                                        Text(result.message)
                                            .font(.caption)
                                            .foregroundColor(result.success ? .green : .red)
                                    }
                                }

                                // Validation hint
                                if !apiKeyInput.isEmpty && !AIKeyManager.shared.isValidKeyFormat(apiKeyInput, for: provider) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle")
                                            .font(.caption2)
                                        Text("Key format doesn't match expected pattern (\(provider.keyPlaceholder))")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.orange)
                                }

                                Link("Get API key from \(provider.rawValue)", destination: URL(string: provider.signupURL)!)
                                    .font(.caption)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                } header: {
                    Text("API Keys")
                } footer: {
                    Text("API keys are stored securely in your device's Keychain. They are never sent anywhere except to the AI provider you choose.")
                }

                // Chat history management
                Section {
                    HStack {
                        Text("Chat Sessions")
                        Spacer()
                        Text("\(chatService.sessions.count)")
                            .foregroundColor(.secondary)
                    }

                    Button(role: .destructive, action: { showingDeleteConfirm = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear All Chat History")
                        }
                    }
                    .disabled(chatService.sessions.isEmpty)
                } header: {
                    Text("Data")
                }

                // Info section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "info.circle")
                            .font(.subheadline.bold())

                        Text("NetoSensei AI collects your network diagnostic data (WiFi info, speed, latency, VPN status, devices, security) and sends it to your chosen AI provider for analysis.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("Your data is sent only when you explicitly ask a question. No data is stored on external servers beyond the AI provider's standard processing.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("API calls are billed directly by your provider based on their pricing.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Clear Chat History?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    chatService.clearAllSessions()
                }
            } message: {
                Text("This will delete all chat sessions. This cannot be undone.")
            }
        }
    }

    private func testConnection(provider: AIProvider) {
        // Save first if entered
        if !apiKeyInput.isEmpty {
            let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            AIKeyManager.shared.saveKey(trimmed, for: provider)
            AIKeyManager.shared.refreshConfiguredCount()
        }

        isTesting = true
        testResult = nil

        Task {
            let result = await AIKeyManager.shared.testConnection(provider: provider)
            testResult = result
            isTesting = false
        }
    }
}

// MARK: - Provider Row

private struct AISettingsProviderRow: View {
    let provider: AIProvider
    let hasKey: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: provider.iconName)
                    .font(.title3)
                    .foregroundColor(hasKey ? .blue : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.rawValue)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(provider.defaultModel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if hasKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    AISettingsView()
}
