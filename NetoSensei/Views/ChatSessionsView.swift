//
//  ChatSessionsView.swift
//  NetoSensei
//
//  Chat session history — browse, select, and delete past conversations.
//

import SwiftUI

struct ChatSessionsView: View {
    @StateObject private var chatService = AIChatService.shared
    @State private var showingDeleteConfirm = false
    @State private var sessionToDelete: ChatSession?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if chatService.sessions.isEmpty {
                    emptyState
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !chatService.sessions.isEmpty {
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                            sessionToDelete = nil
                        } label: {
                            Text("Clear All")
                                .font(.subheadline)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                sessionToDelete != nil ? "Delete Chat?" : "Clear All Chats?",
                isPresented: $showingDeleteConfirm
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let session = sessionToDelete {
                        chatService.deleteSession(session)
                    } else {
                        chatService.clearAllSessions()
                    }
                }
            } message: {
                Text(sessionToDelete != nil
                     ? "This chat will be permanently deleted."
                     : "All chat sessions will be permanently deleted.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Chat History")
                .font(.headline)

            Text("Your conversations with the AI assistant will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        List {
            ForEach(chatService.sessions) { session in
                ChatSessionRow(
                    session: session,
                    isActive: session.id == chatService.currentSession?.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    chatService.selectSession(session)
                    dismiss()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        sessionToDelete = session
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Session Row

private struct ChatSessionRow: View {
    let session: ChatSession
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(isActive ? Color.blue.opacity(0.2) : Color(UIColor.systemGray5))
                    .frame(width: 40, height: 40)

                Image(systemName: session.hasDiagnosticContext ? "waveform.path.ecg" : "bubble.left")
                    .font(.caption)
                    .foregroundColor(isActive ? .blue : .secondary)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                HStack(spacing: 4) {
                    let userMessageCount = session.messages.filter { $0.role == "user" }.count
                    Text("\(userMessageCount) message\(userMessageCount != 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Text(formatDate(session.updatedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Preview of last assistant message
                if let lastResponse = session.messages.last(where: { $0.role == "assistant" }) {
                    Text(lastResponse.content)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isActive {
                Text("Active")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue)
                    .cornerRadius(4)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

#Preview {
    ChatSessionsView()
}
