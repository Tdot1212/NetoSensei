//
//  OptOutActionDetailView.swift
//  NetoSensei
//
//  Detail view for a single opt-out action with instructions,
//  status control, in-app browser, and email generation.
//

import SwiftUI
import SafariServices
import MessageUI

struct OptOutActionDetailView: View {
    let actionID: String

    @StateObject private var manager = PrivacyActionCenterManager.shared
    @State private var showingBrowser = false
    @State private var showingEmailSheet = false
    @State private var showingCopiedToast = false
    @State private var browserURL: URL?

    var action: OptOutAction? {
        manager.optOutActions.first { $0.id == actionID }
    }

    var body: some View {
        ScrollView {
            if let action = action {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard(action)
                    statusControl(action)
                    instructionsCard(action)
                    actionsSection(action)

                    if action.supportsGDPR || action.supportsCCPA {
                        emailSection(action)
                    }

                    detailsCard(action)
                }
                .padding()
            }
        }
        .navigationTitle(action?.brokerName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingBrowser) {
            if let url = browserURL {
                InAppBrowserView(url: url, tintColor: .systemPurple)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingEmailSheet) {
            if let action = action {
                PrivacyRemovalEmailView(action: action)
            }
        }
        .overlay {
            if showingCopiedToast {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Copied to clipboard")
                            .font(.subheadline.bold())
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header Card

    private func headerCard(_ action: OptOutAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: action.category.icon)
                    .font(.title2)
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.brokerName)
                        .font(.headline)
                    Text(action.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(action.difficulty.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(difficultyColor(action.difficulty))
                    .cornerRadius(6)
            }

            Text(action.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Status Control

    private func statusControl(_ action: OptOutAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach([OptOutAction.CompletionStatus.notStarted, .inProgress, .submitted, .confirmed], id: \.self) { status in
                    Button(action: { manager.updateStatus(action.id, status: status) }) {
                        VStack(spacing: 4) {
                            Image(systemName: status.icon)
                                .font(.title3)
                            Text(statusLabel(status))
                                .font(.system(size: 9))
                        }
                        .foregroundColor(action.status == status ? .white : statusColor(status))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(action.status == status ? statusColor(status) : statusColor(status).opacity(0.15))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Instructions Card

    private func instructionsCard(_ action: OptOutAction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How to Opt Out")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)

                Spacer()

                Text("~\(action.estimatedMinutes) min")
                    .font(.caption)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(action.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.purple)
                            .clipShape(Circle())

                        Text(step)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Actions Section

    private func actionsSection(_ action: OptOutAction) -> some View {
        VStack(spacing: 10) {
            // Main action: Open opt-out page in-app
            Button(action: {
                if let url = URL(string: action.optOutURL) {
                    browserURL = url
                    showingBrowser = true
                    if action.status == .notStarted {
                        manager.updateStatus(action.id, status: .inProgress)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "safari")
                    Text("Open Opt-Out Page")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .cornerRadius(12)
            }

            // Mark as submitted
            if action.status == .inProgress {
                Button(action: { manager.updateStatus(action.id, status: .submitted) }) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("I've Submitted My Request")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(12)
                }
            }

            // Mark as confirmed
            if action.status == .submitted {
                Button(action: { manager.updateStatus(action.id, status: .confirmed) }) {
                    HStack {
                        Image(systemName: "checkmark.seal")
                        Text("Removal Confirmed")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - Email Section

    private func emailSection(_ action: OptOutAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Send Removal Email")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            if manager.profile != nil {
                HStack(spacing: 10) {
                    if action.privacyEmail != nil {
                        Button(action: { showingEmailSheet = true }) {
                            HStack {
                                Image(systemName: "envelope")
                                Text("Generate Email")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                    }

                    if action.supportsGDPR {
                        Button(action: { copyGDPREmail(action) }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Copy GDPR")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(12)
                        }
                    }
                }
            } else {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    Text("Set up your profile first to generate removal emails")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Details Card

    private func detailsCard(_ action: OptOutAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            VStack(spacing: 0) {
                detailRow("Method", action.method.rawValue)
                Divider()
                detailRow("Processing Time", action.processingTime)
                Divider()
                detailRow("GDPR", action.supportsGDPR ? "Supported" : "No")
                Divider()
                detailRow("CCPA", action.supportsCCPA ? "Supported" : "No")

                if let email = action.privacyEmail {
                    Divider()
                    detailRow("Privacy Email", email)
                }

                if let completedAt = action.completedAt {
                    Divider()
                    detailRow("Completed", completedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    private func difficultyColor(_ difficulty: OptOutAction.Difficulty) -> Color {
        switch difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }

    private func statusColor(_ status: OptOutAction.CompletionStatus) -> Color {
        switch status {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .submitted: return .orange
        case .confirmed: return .green
        }
    }

    private func statusLabel(_ status: OptOutAction.CompletionStatus) -> String {
        switch status {
        case .notStarted: return "Not Started"
        case .inProgress: return "Started"
        case .submitted: return "Sent"
        case .confirmed: return "Done"
        }
    }

    private func copyGDPREmail(_ action: OptOutAction) {
        if let email = manager.generateGDPREmail(for: action) {
            UIPasteboard.general.string = "Subject: \(email.subject)\n\n\(email.body)"
            showingCopiedToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showingCopiedToast = false
            }
        }
    }
}
