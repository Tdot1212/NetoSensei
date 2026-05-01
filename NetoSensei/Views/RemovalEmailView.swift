//
//  RemovalEmailView.swift
//  NetoSensei
//
//  Generates and displays a data removal request email (GDPR/CCPA/generic)
//  with options to copy, send via Mail, or mark as sent.
//

import SwiftUI
import MessageUI

struct RemovalEmailView: View {
    let broker: DataBroker

    @StateObject private var scanner = DigitalFootprintScanner.shared
    @Environment(\.dismiss) private var dismiss

    @State private var emailContent = ""
    @State private var emailSubject = ""
    @State private var showingMailComposer = false
    @State private var showingCopied = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoCard
                    emailCard
                    actionsSection
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
            .onAppear {
                generateEmail()
            }
            .overlay {
                if showingCopied {
                    copiedToast
                }
            }
        }
    }

    // MARK: - Info Card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundColor(.blue)
                Text("Email to \(broker.name)")
                    .font(.headline)
            }

            Text("This email requests deletion of your data under applicable privacy laws.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let profile = scanner.scanProfile {
                HStack {
                    Text("Sending as:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(profile.fullName)
                        .font(.caption.bold())
                }
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Email Card

    private var emailCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subject:")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Text(emailSubject)
                .font(.subheadline)
                .padding(8)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(6)

            Text("Body:")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.top, 8)

            ScrollView {
                Text(emailContent)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
            }
            .frame(maxHeight: 300)
            .background(Color(UIColor.systemGray5))
            .cornerRadius(6)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: copyToClipboard) {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text("Copy to Clipboard")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }

            if MFMailComposeViewController.canSendMail() {
                Button(action: { showingMailComposer = true }) {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Open in Mail App")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
                }
                .sheet(isPresented: $showingMailComposer) {
                    FootprintMailComposeView(
                        subject: emailSubject,
                        body: emailContent,
                        recipients: []
                    )
                }
            }

            Button(action: markAsSent) {
                HStack {
                    Image(systemName: "checkmark.circle")
                    Text("I've Sent This Request")
                }
                .font(.headline)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Copied Toast

    private var copiedToast: some View {
        VStack {
            Spacer()

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Copied to clipboard")
                    .font(.subheadline.bold())
            }
            .padding()
            .background(Color(UIColor.systemGray6))
            .cornerRadius(10)
            .shadow(radius: 5)
            .padding(.bottom, 50)
        }
        .transition(.move(edge: .bottom))
        .animation(.easeInOut, value: showingCopied)
    }

    // MARK: - Actions

    private func generateEmail() {
        guard let profile = scanner.scanProfile else {
            emailSubject = "Data Removal Request"
            emailContent = "Please set up your profile first."
            return
        }

        let request = RemovalRequestGenerator.shared.getRequest(for: broker, profile: profile)
        emailSubject = request.subject
        emailContent = request.body
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = "Subject: \(emailSubject)\n\n\(emailContent)"

        showingCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingCopied = false
        }
    }

    private func markAsSent() {
        scanner.markRemovalRequested(broker.id)
        dismiss()
    }
}

// MARK: - Mail Compose View

struct FootprintMailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let recipients: [String]

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        composer.setToRecipients(recipients)
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: FootprintMailComposeView

        init(_ parent: FootprintMailComposeView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }
}
