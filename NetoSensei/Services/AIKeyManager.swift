//
//  AIKeyManager.swift
//  NetoSensei
//
//  Securely store and manage AI provider API keys using iOS Keychain
//

import Foundation
import Security

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case openai = "OpenAI"
    case claude = "Claude"
    case deepseek = "DeepSeek"
    case gemini = "Gemini"
    case groq = "Groq"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .claude: return "https://api.anthropic.com/v1/messages"
        case .deepseek: return "https://api.deepseek.com/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/models"
        case .groq: return "https://api.groq.com/openai/v1/chat/completions"
        }
    }

    var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o"
        case .claude: return "claude-sonnet-4-20250514"
        case .deepseek: return "deepseek-chat"
        case .gemini: return "gemini-2.0-flash"
        case .groq: return "llama-3.1-70b-versatile"
        }
    }

    var iconName: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .claude: return "sparkles"
        case .deepseek: return "magnifyingglass"
        case .gemini: return "diamond"
        case .groq: return "bolt"
        }
    }

    var displayName: String { rawValue }

    var availableModels: [String] {
        switch self {
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .claude:
            return ["claude-sonnet-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-haiku-20240307"]
        case .deepseek:
            return ["deepseek-chat", "deepseek-coder"]
        case .gemini:
            return ["gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"]
        case .groq:
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .openai: return "sk-..."
        case .claude: return "sk-ant-..."
        case .deepseek: return "sk-..."
        case .gemini: return "AIza..."
        case .groq: return "gsk_..."
        }
    }

    var color: String {
        switch self {
        case .openai: return "green"
        case .claude: return "orange"
        case .deepseek: return "blue"
        case .gemini: return "purple"
        case .groq: return "red"
        }
    }

    var signupURL: String {
        switch self {
        case .openai: return "https://platform.openai.com/api-keys"
        case .claude: return "https://console.anthropic.com/settings/keys"
        case .deepseek: return "https://platform.deepseek.com/api_keys"
        case .gemini: return "https://aistudio.google.com/apikey"
        case .groq: return "https://console.groq.com/keys"
        }
    }
}

// MARK: - Keychain Manager

class AIKeyManager: ObservableObject {
    static let shared = AIKeyManager()
    private let service = "com.netosensei.aikeys"

    @Published private(set) var configuredCount: Int = 0

    private init() {
        configuredCount = getConfiguredProviders().count
    }

    func refreshConfiguredCount() {
        configuredCount = getConfiguredProviders().count
    }

    // MARK: - CRUD

    func saveKey(_ key: String, for provider: AIProvider) {
        // Delete existing first
        deleteKey(for: provider)

        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func getKey(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func deleteKey(for provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    func hasKey(for provider: AIProvider) -> Bool {
        return getKey(for: provider) != nil
    }

    // MARK: - Default Provider

    var defaultProvider: AIProvider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "aiDefaultProvider"),
               let provider = AIProvider(rawValue: raw) {
                return provider
            }
            // Return first provider that has a key
            for provider in AIProvider.allCases {
                if hasKey(for: provider) { return provider }
            }
            return .claude
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "aiDefaultProvider")
        }
    }

    /// Returns true if any provider has a configured key
    var hasAnyKey: Bool {
        AIProvider.allCases.contains { hasKey(for: $0) }
    }

    /// Returns all providers that have a configured key
    func getConfiguredProviders() -> [AIProvider] {
        AIProvider.allCases.filter { hasKey(for: $0) }
    }

    /// Delete all stored API keys
    func deleteAllKeys() {
        for provider in AIProvider.allCases {
            deleteKey(for: provider)
        }
    }

    /// Validates that the key string matches the expected format for a provider
    func isValidKeyFormat(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch provider {
        case .openai:
            return trimmed.hasPrefix("sk-") && trimmed.count > 20
        case .claude:
            return trimmed.hasPrefix("sk-ant-") && trimmed.count > 20
        case .deepseek:
            return trimmed.hasPrefix("sk-") && trimmed.count > 20
        case .gemini:
            return trimmed.hasPrefix("AIza") && trimmed.count > 20
        case .groq:
            return trimmed.hasPrefix("gsk_") && trimmed.count > 20
        }
    }

    // MARK: - Selected Model

    private var selectedModelKey: String { "aiSelectedModel" }

    var selectedModel: String {
        get {
            if let model = UserDefaults.standard.string(forKey: selectedModelKey) {
                return model
            }
            return defaultProvider.defaultModel
        }
        set {
            UserDefaults.standard.set(newValue, forKey: selectedModelKey)
        }
    }

    // MARK: - Test Connection

    func testConnection(provider: AIProvider) async -> (success: Bool, message: String) {
        guard let key = getKey(for: provider) else {
            return (false, "No API key configured")
        }

        do {
            switch provider {
            case .openai, .deepseek, .groq:
                return try await testOpenAICompatible(url: provider.baseURL, key: key, model: provider.defaultModel)
            case .claude:
                return try await testClaude(key: key)
            case .gemini:
                return try await testGemini(key: key, model: provider.defaultModel)
            }
        } catch {
            return (false, "Connection error: \(error.localizedDescription)")
        }
    }

    private func testOpenAICompatible(url: String, key: String, model: String) async throws -> (Bool, String) {
        guard let requestURL = URL(string: url) else {
            return (false, "Invalid URL")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "Hi"]],
            "max_tokens": 5
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        if httpResponse?.statusCode == 200 {
            return (true, "Connected successfully")
        } else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            return (false, "HTTP \(httpResponse?.statusCode ?? 0): \(errorBody.prefix(200))")
        }
    }

    private func testClaude(key: String) async throws -> (Bool, String) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return (false, "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": AIProvider.claude.defaultModel,
            "max_tokens": 5,
            "messages": [["role": "user", "content": "Hi"]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        if httpResponse?.statusCode == 200 {
            return (true, "Connected successfully")
        } else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            return (false, "HTTP \(httpResponse?.statusCode ?? 0): \(errorBody.prefix(200))")
        }
    }

    private func testGemini(key: String, model: String) async throws -> (Bool, String) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            return (false, "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "contents": [["parts": [["text": "Hi"]]]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        if httpResponse?.statusCode == 200 {
            return (true, "Connected successfully")
        } else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            return (false, "HTTP \(httpResponse?.statusCode ?? 0): \(errorBody.prefix(200))")
        }
    }
}
