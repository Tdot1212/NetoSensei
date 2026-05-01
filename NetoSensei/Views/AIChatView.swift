//
//  AIChatView.swift
//  NetoSensei
//
//  AI-powered network diagnostic chat interface with session management,
//  quick actions, full/quick scan, and diagnostic toggle.
//

import SwiftUI

struct AIChatView: View {
    @StateObject private var chatService = AIChatService.shared
    @StateObject private var preflight = AIPreflightCollector.shared
    @StateObject private var keyManager = AIKeyManager.shared

    @State private var inputText = ""
    @State private var sessionSnapshotJSON: String?
    @State private var showSettings = false
    @State private var showSessions = false

    @FocusState private var isInputFocused: Bool

    private var currentProvider: AIProvider { AIKeyManager.shared.defaultProvider }
    private var hasKey: Bool { AIKeyManager.shared.hasAnyKey }
    private var messages: [ChatMessage] { chatService.currentSession?.messages ?? [] }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Provider indicator
                if hasKey {
                    providerBar
                }

                if !hasKey {
                    noKeyView
                } else if preflight.isCollecting {
                    scanningView
                } else if messages.isEmpty {
                    emptyStateView
                } else {
                    chatView
                }
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        if hasKey {
                            Button(action: { showSessions = true }) {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                        if !messages.isEmpty {
                            Button("New") { newChat() }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                AISettingsView()
            }
            .sheet(isPresented: $showSessions) {
                ChatSessionsView()
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Provider Bar

    private var providerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: currentProvider.iconName)
                .font(.caption2)
            Text(currentProvider.rawValue)
                .font(.caption2.bold())
            Text("(\(AIKeyManager.shared.selectedModel))")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            if sessionSnapshotJSON != nil {
                Label("Diagnostics loaded", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - No API Key View

    private var noKeyView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.6))

            Text("Set Up AI Assistant")
                .font(.title2.bold())

            Text("Add an API key from any supported provider to get AI-powered network diagnosis.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(AIProvider.allCases) { provider in
                    HStack(spacing: 8) {
                        Image(systemName: provider.iconName)
                            .frame(width: 20)
                        Text(provider.rawValue)
                            .font(.subheadline)
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 60)

            Button(action: { showSettings = true }) {
                Label("Configure API Key", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Collecting diagnostic data")
                        .font(.headline)
                }
                Text(preflight.currentStep)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .animation(.easeInOut(duration: 0.15), value: preflight.currentStep)
            }
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(preflight.steps) { step in
                        preflightStepRow(step)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }

            VStack(spacing: 6) {
                ProgressView(value: preflight.progress)
                    .progressViewStyle(.linear)
                Text("\(Int(preflight.progress * 100))%  •  Running every diagnostic so the AI has the full picture")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private func preflightStepRow(_ step: AIPreflightCollector.StepState) -> some View {
        HStack(spacing: 12) {
            preflightStepIcon(for: step.status)
                .frame(width: 22, height: 22)
            Text(step.title)
                .font(.subheadline)
                .foregroundColor(step.status == .pending ? .secondary : .primary)
            Spacer()
            if step.status == .failed {
                Text("skipped")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func preflightStepIcon(for status: AIPreflightCollector.StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.secondary.opacity(0.6))
        case .inProgress:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.orange)
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 20)

                // Header
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue.opacity(0.6))

                    Text("NetoSensei AI")
                        .font(.title2.bold())

                    Text("Your network diagnostics expert")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Scan buttons
                VStack(spacing: 12) {
                    Button(action: { startAnalysis(runSpeedTest: true) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.title2)
                                .foregroundColor(.green)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Full Network Scan")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("Speed test + diagnostics + AI analysis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("~30s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }

                    Button(action: { startAnalysis(runSpeedTest: false) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "bolt.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quick Scan")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                Text("Diagnostics + AI analysis (skip speed test)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("~20s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }

                    if preflight.lastSnapshot != nil && preflight.isSnapshotFresh() {
                        Button(action: { useRecentSnapshot() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "bubble.left.circle")
                                    .font(.title2)
                                    .foregroundColor(.teal)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("💬 Chat with recent data")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text("Use the last scan — no re-testing")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("instant")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.teal.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.teal.opacity(0.4), lineWidth: 1)
                            )
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)

                // Quick action prompts
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or ask a question")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)

                    AIChatQuickAction(
                        icon: "wifi.exclamationmark",
                        title: "Why is my WiFi slow?",
                        color: .orange
                    ) {
                        sendQuickAction("My WiFi feels slow. Can you help me figure out why and how to fix it?")
                    }

                    AIChatQuickAction(
                        icon: "shield.lefthalf.filled",
                        title: "Security Check",
                        color: .red
                    ) {
                        sendQuickAction("Please check my network security. Are there any vulnerabilities or risks I should know about?")
                    }

                    AIChatQuickAction(
                        icon: "lock.shield",
                        title: "VPN Help",
                        color: .purple
                    ) {
                        sendQuickAction("I'm having issues with my VPN. Can you help me diagnose and fix the problem?")
                    }

                    AIChatQuickAction(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Optimize my connection",
                        color: .teal
                    ) {
                        sendQuickAction("What can I do to optimize my current network connection for better performance?")
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 80)
            }
        }
    }

    // MARK: - Chat View

    private var chatView: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Diagnostic context banner
                        if chatService.currentSession?.hasDiagnosticContext == true {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.path.ecg.rectangle.fill")
                                    .foregroundColor(.green)
                                Text("Network diagnostics attached to this conversation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        }

                        ForEach(messages) { message in
                            if !message.isLoading {
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if chatService.isResponding {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    scrollToEnd(proxy: proxy)
                }
                .onChange(of: chatService.isResponding) { responding in
                    if responding {
                        withAnimation {
                            proxy.scrollTo("typing", anchor: .bottom)
                        }
                    }
                }
            }

            // Error banner
            if let error = chatService.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { chatService.lastError = nil }
                        .font(.caption.bold())
                }
                .foregroundColor(.red)
                .padding(8)
                .background(Color.red.opacity(0.1))
            }

            Divider()

            // Input bar with diagnostic toggle
            inputBar
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Fresh-scan button (forces a new preflight before the next send)
            Button(action: { Task { await refreshSnapshot() } }) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .disabled(preflight.isCollecting || chatService.isResponding)

            // Text field
            TextField("Ask about your network...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(10)
                .background(Color(UIColor.systemGroupedBackground))
                .cornerRadius(20)

            // Send button
            Button(action: { sendMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatService.isResponding
    }

    private func scrollToEnd(proxy: ScrollViewProxy) {
        if let lastID = messages.last?.id {
            withAnimation {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    // MARK: - Actions

    /// Ensures we have a fresh diagnostic snapshot for the current session.
    /// Returns the serialized JSON or nil if collection failed entirely.
    @discardableResult
    private func ensureSnapshot(forceRefresh: Bool = false, skipSpeedTest: Bool = false) async -> String? {
        if !forceRefresh, let existing = sessionSnapshotJSON {
            return existing
        }
        let snapshot = await preflight.collectAllData(forceRefresh: forceRefresh, skipSpeedTest: skipSpeedTest)
        let json = preflight.snapshotJSON(snapshot)
        sessionSnapshotJSON = json
        chatService.markDiagnosticContextAttached()
        return json
    }

    private func refreshSnapshot() async {
        _ = await ensureSnapshot(forceRefresh: true)
    }

    private func useRecentSnapshot() {
        guard let cached = preflight.lastSnapshot else { return }
        ensureSession()
        sessionSnapshotJSON = preflight.snapshotJSON(cached)
        chatService.markDiagnosticContextAttached()
        isInputFocused = true
    }

    private func startAnalysis(runSpeedTest: Bool) {
        ensureSession()

        Task {
            guard let json = await ensureSnapshot(forceRefresh: true, skipSpeedTest: !runSpeedTest) else {
                chatService.addMessageToCurrentSession(
                    ChatMessage(role: "assistant",
                                content: "I couldn't collect diagnostic data. Please check your network connection and try again.")
                )
                return
            }

            await generateInitialAnalysis(snapshotJSON: json, runSpeedTest: runSpeedTest)
        }
    }

    private func generateInitialAnalysis(snapshotJSON: String, runSpeedTest: Bool) async {
        let displayText = runSpeedTest
            ? "📊 Full network scan completed — analyze my network"
            : "⚡ Quick scan completed — analyze my network"

        let aiPrompt = """
        Analyze this network data. Format your response as:
        1. One-sentence verdict (is my network OK or not?)
        2. Key findings (2-3 items, use ✅ ℹ️ ⚠️ 🔴 icons, 1-2 sentences each)
        3. Recommendations (only if something needs action, specific steps)
        Total response under 400 words. Do not repeat raw numbers I can see in the app.
        """

        chatService.addMessageToCurrentSession(ChatMessage(role: "user", content: displayText))

        do {
            let history = messages.filter { $0.role == "user" || $0.role == "assistant" }
            let response = try await chatService.sendMessage(
                aiPrompt,
                conversationHistory: Array(history.dropLast()),
                provider: currentProvider,
                preflightJSON: snapshotJSON
            )
            chatService.addMessageToCurrentSession(ChatMessage(role: "assistant", content: response))
        } catch {
            chatService.addMessageToCurrentSession(
                ChatMessage(role: "assistant", content: "I couldn't connect to the AI service. Error: \(error.localizedDescription)\n\nYou can still try again or check your API key in settings.")
            )
        }
    }

    private func sendQuickAction(_ prompt: String) {
        ensureSession()
        inputText = prompt
        sendMessage()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        ensureSession()
        inputText = ""
        isInputFocused = false

        chatService.addMessageToCurrentSession(ChatMessage(role: "user", content: text))

        Task {
            // Always ensure we have a snapshot (preflight runs on first message,
            // cached for follow-ups within the 2-minute fresh window).
            guard let json = await ensureSnapshot(forceRefresh: false) else {
                chatService.addMessageToCurrentSession(
                    ChatMessage(role: "assistant",
                                content: "I couldn't collect diagnostic data. Please check your network connection and try again.")
                )
                return
            }

            do {
                let history = messages.filter { $0.role == "user" || $0.role == "assistant" }
                let response = try await chatService.sendMessage(
                    text,
                    conversationHistory: Array(history.dropLast()),
                    provider: currentProvider,
                    preflightJSON: json
                )
                chatService.addMessageToCurrentSession(ChatMessage(role: "assistant", content: response))
            } catch {
                // Error shown via chatService.lastError banner
            }
        }
    }

    private func newChat() {
        chatService.createNewSession()
        sessionSnapshotJSON = nil
        chatService.lastError = nil
        // Drop any cached preflight snapshot so the next message runs a fresh scan
        // instead of inheriting data from the previous session.
        preflight.invalidateCache()
    }

    private func ensureSession() {
        if chatService.currentSession == nil {
            chatService.createNewSession()
        }
    }
}

// MARK: - Quick Action Button

private struct AIChatQuickAction: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Group {
                    if isUser {
                        Text(message.content)
                            .font(.body)
                    } else {
                        MarkdownText(text: message.content)
                    }
                }
                .padding(12)
                .background(isUser ? Color.blue : Color(UIColor.systemGray5))
                .foregroundColor(isUser ? .white : .primary)
                .cornerRadius(16)

                Text(timeString(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if isUser {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotCount = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(dotCount == index ? 1.0 : 0.3)
            }
        }
        .padding(12)
        .background(Color(UIColor.systemGray5))
        .cornerRadius(16)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount = (dotCount + 1) % 3
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AIChatView()
}
