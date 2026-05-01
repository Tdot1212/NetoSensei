//
//  ChatModels.swift
//  NetoSensei
//
//  Chat session model for AI conversations. ChatMessage is in AIChatService,
//  AIProvider is in AIKeyManager, NetworkDiagnosticReport is in DiagnosticDataCollector.
//

import Foundation

// MARK: - Chat Session

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var hasDiagnosticContext: Bool
    let createdAt: Date
    var updatedAt: Date

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.hasDiagnosticContext = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()

        // Auto-generate title from first user message
        if title == "New Chat", message.role == "user" {
            let preview = String(message.content.prefix(30))
            title = preview + (message.content.count > 30 ? "..." : "")
        }
    }
}
