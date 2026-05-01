//
//  PrivacyRemovalEmailView.swift
//  NetoSensei
//
//  GDPR/CCPA email generator with type picker and copy-to-clipboard.
//

import SwiftUI
import MessageUI

struct PrivacyRemovalEmailView: View {
    let action: OptOutAction

    @StateObject private var manager = PrivacyActionCenterManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var emailType: EmailType = .gdpr
    @State private var showingCopied = false

    enum EmailType: String, CaseIterable {
        case gdpr = "GDPR"
        case ccpa = "CCPA"
    }

    var emailContent: (subject: String, body: String)? {
        switch emailType {
        case .gdpr: return manager.generateGDPREmail(for: action)
        case .ccpa: return manager.generateCCPAEmail(for: action)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Type picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email Type")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)

                        Picker("Type", selection: $emailType) {
                            ForEach(EmailType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if let email = emailContent {
                        // Recipient
                        if let privacyEmail = action.privacyEmail {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Send to:")
                                    .font(.caption.bold())
                                    .foregroundColor(.secondary)
                                Text(privacyEmail)
                                    .font(.subheadline.monospaced())
                            }
                        }

                        // Subject
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Subject:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Text(email.subject)
                                .font(.subheadline)
                                .padding(8)
                                .background(Color(.systemGray5))
                                .cornerRadius(6)
                        }

                        // Body
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Body:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Text(email.body)
                                .font(.system(.caption, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray5))
                                .cornerRadius(6)
                        }

                        // Actions
                        VStack(spacing: 10) {
                            Button(action: {
                                UIPasteboard.general.string = "Subject: \(email.subject)\n\n\(email.body)"
                                showingCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showingCopied = false }
                            }) {
                                HStack {
                                    Image(systemName: "doc.on.doc")
                                    Text(showingCopied ? "Copied!" : "Copy to Clipboard")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(showingCopied ? Color.green : Color.blue)
                                .cornerRadius(12)
                            }

                            Button(action: {
                                manager.updateStatus(action.id, status: .submitted)
                                dismiss()
                            }) {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                    Text("I've Sent This Email")
                                }
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(12)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.title)
                                .foregroundColor(.orange)
                            Text("Set up your profile to generate emails")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                }
                .padding()
            }
            .navigationTitle("Removal Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
