//
//  PrivacyActionCenterManager.swift
//  NetoSensei
//
//  Manages opt-out actions for data brokers, user privacy profile,
//  GDPR/CCPA email generation, and tracks removal progress.
//

import Foundation
import UIKit

// MARK: - Opt-Out Action

struct OptOutAction: Identifiable, Codable {
    let id: String
    let brokerName: String
    let category: BrokerCategory
    let description: String
    let optOutURL: String
    let difficulty: Difficulty
    let estimatedMinutes: Int
    let processingTime: String
    let method: OptOutMethod
    let steps: [String]
    let privacyEmail: String?
    let supportsGDPR: Bool
    let supportsCCPA: Bool
    var status: CompletionStatus
    var completedAt: Date?
    var notes: String?

    enum BrokerCategory: String, Codable, CaseIterable {
        case peopleSearch = "People Search"
        case dataAggregator = "Data Aggregator"
        case marketing = "Marketing"
        case advertising = "Advertising"
        case socialMedia = "Social Media"
        case searchEngine = "Search Engine"

        var icon: String {
            switch self {
            case .peopleSearch: return "person.crop.circle.badge.questionmark"
            case .dataAggregator: return "externaldrive.connected.to.line.below"
            case .marketing: return "envelope.badge"
            case .advertising: return "megaphone"
            case .socialMedia: return "person.2.circle"
            case .searchEngine: return "magnifyingglass.circle"
            }
        }
    }

    enum Difficulty: String, Codable, CaseIterable {
        case easy = "Easy"
        case medium = "Medium"
        case hard = "Hard"

        var sortOrder: Int {
            switch self {
            case .easy: return 0
            case .medium: return 1
            case .hard: return 2
            }
        }
    }

    enum OptOutMethod: String, Codable {
        case webForm = "Web Form"
        case email = "Email Request"
        case accountSettings = "Account Settings"
        case combined = "Web + Email"
    }

    enum CompletionStatus: String, Codable {
        case notStarted = "Not Started"
        case inProgress = "In Progress"
        case submitted = "Submitted"
        case confirmed = "Confirmed"

        var icon: String {
            switch self {
            case .notStarted: return "circle"
            case .inProgress: return "circle.lefthalf.filled"
            case .submitted: return "clock"
            case .confirmed: return "checkmark.circle.fill"
            }
        }

        var sortOrder: Int {
            switch self {
            case .notStarted: return 0
            case .inProgress: return 1
            case .submitted: return 2
            case .confirmed: return 3
            }
        }
    }
}

// MARK: - Paid Deletion Service

struct DeletionService: Identifiable {
    let id: String
    let name: String
    let description: String
    let websiteURL: String
    let monthlyPrice: String?
    let yearlyPrice: String?
    let freeOption: Bool
    let brokersCovered: Int
    let features: [String]
    let pros: [String]
    let cons: [String]
    let hasIOSApp: Bool
    let rating: Double
}

// MARK: - User Privacy Profile

struct PrivacyProfile: Codable {
    var firstName: String
    var lastName: String
    var email: String?
    var phone: String?
    var city: String?
    var state: String?
    var country: String

    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

// MARK: - Privacy Action Center Manager

@MainActor
class PrivacyActionCenterManager: ObservableObject {
    static let shared = PrivacyActionCenterManager()

    @Published var optOutActions: [OptOutAction] = []
    @Published var profile: PrivacyProfile?

    private let actionsKey = "privacyOptOutActions"
    private let profileKey = "privacyProfile"

    private init() {
        loadProfile()
        loadActions()
        if optOutActions.isEmpty {
            optOutActions = Self.buildDefaultActions()
            saveActions()
        }
    }

    // MARK: - Statistics

    var completedCount: Int {
        optOutActions.filter { $0.status == .confirmed }.count
    }

    var submittedCount: Int {
        optOutActions.filter { $0.status == .submitted }.count
    }

    var totalCount: Int {
        optOutActions.count
    }

    var progressPercent: Double {
        guard totalCount > 0 else { return 0 }
        let done = Double(completedCount)
        let submitted = Double(submittedCount) * 0.5
        return (done + submitted) / Double(totalCount) * 100
    }

    var easyActions: [OptOutAction] {
        optOutActions.filter { $0.difficulty == .easy && $0.status == .notStarted }
    }

    // MARK: - Actions

    func updateStatus(_ actionID: String, status: OptOutAction.CompletionStatus) {
        if let index = optOutActions.firstIndex(where: { $0.id == actionID }) {
            optOutActions[index].status = status
            if status == .confirmed {
                optOutActions[index].completedAt = Date()
            }
            saveActions()
        }
    }

    func setNotes(_ actionID: String, notes: String?) {
        if let index = optOutActions.firstIndex(where: { $0.id == actionID }) {
            optOutActions[index].notes = notes
            saveActions()
        }
    }

    func resetAll() {
        for i in optOutActions.indices {
            optOutActions[i].status = .notStarted
            optOutActions[i].completedAt = nil
            optOutActions[i].notes = nil
        }
        saveActions()
    }

    func saveProfile(_ profile: PrivacyProfile) {
        self.profile = profile
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: profileKey)
        }
    }

    // MARK: - Persistence

    private func saveActions() {
        if let encoded = try? JSONEncoder().encode(optOutActions) {
            UserDefaults.standard.set(encoded, forKey: actionsKey)
        }
    }

    private func loadActions() {
        if let data = UserDefaults.standard.data(forKey: actionsKey),
           let decoded = try? JSONDecoder().decode([OptOutAction].self, from: data) {
            optOutActions = decoded
        }
    }

    private func loadProfile() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(PrivacyProfile.self, from: data) {
            profile = decoded
        }
    }

    // MARK: - Email Generation

    func generateGDPREmail(for action: OptOutAction) -> (subject: String, body: String)? {
        guard let profile = profile else { return nil }

        let subject = "GDPR Data Deletion Request — \(profile.fullName)"
        let body = """
        Dear Data Protection Team at \(action.brokerName),

        Pursuant to Article 17 of the General Data Protection Regulation (GDPR), I request the erasure of all personal data you hold about me.

        My details:
        Name: \(profile.fullName)
        \(profile.email.map { "Email: \($0)" } ?? "")
        \(profile.phone.map { "Phone: \($0)" } ?? "")
        \(profile.city.map { "City: \($0)" } ?? "")\(profile.state.map { ", \($0)" } ?? "")
        Country: \(profile.country)

        Please confirm deletion within 30 days as required by GDPR Article 12(3).

        Regards,
        \(profile.fullName)
        """

        return (subject, body)
    }

    func generateCCPAEmail(for action: OptOutAction) -> (subject: String, body: String)? {
        guard let profile = profile else { return nil }

        let subject = "CCPA Data Deletion Request — \(profile.fullName)"
        let body = """
        To the Privacy Department at \(action.brokerName),

        Under the California Consumer Privacy Act (CCPA), Section 1798.105, I request deletion of all personal information you have collected about me. I also opt out of the sale of my personal information per Section 1798.120.

        My details:
        Name: \(profile.fullName)
        \(profile.email.map { "Email: \($0)" } ?? "")
        \(profile.phone.map { "Phone: \($0)" } ?? "")
        \(profile.city.map { "City: \($0)" } ?? "")\(profile.state.map { ", \($0)" } ?? "")

        Please respond within 45 days as required by CCPA.

        Regards,
        \(profile.fullName)
        """

        return (subject, body)
    }

    // MARK: - Default Actions Database

    static func buildDefaultActions() -> [OptOutAction] {
        [
            // EASY — People Search
            OptOutAction(
                id: "spokeo", brokerName: "Spokeo", category: .peopleSearch,
                description: "Aggregates public records and social media into people profiles",
                optOutURL: "https://www.spokeo.com/optout",
                difficulty: .easy, estimatedMinutes: 3, processingTime: "24-48 hours",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Search for your name to find your listing",
                    "Copy the URL of your profile page",
                    "Paste it into the opt-out form on the same page",
                    "Enter your email and submit",
                    "Check your email and click the confirmation link",
                ],
                privacyEmail: "customercare@spokeo.com",
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "truepeoplesearch", brokerName: "TruePeopleSearch", category: .peopleSearch,
                description: "Free people search with addresses, phone numbers, and relatives",
                optOutURL: "https://www.truepeoplesearch.com/removal",
                difficulty: .easy, estimatedMinutes: 2, processingTime: "24-72 hours",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Find your listing on their site first",
                    "On your profile page, scroll to the bottom",
                    "Click 'Remove This Record'",
                    "Complete the CAPTCHA verification",
                    "Your record will be removed within 72 hours",
                ],
                privacyEmail: nil,
                supportsGDPR: false, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "fastpeoplesearch", brokerName: "FastPeopleSearch", category: .peopleSearch,
                description: "Free people directory with contact info and addresses",
                optOutURL: "https://www.fastpeoplesearch.com/removal",
                difficulty: .easy, estimatedMinutes: 2, processingTime: "24-48 hours",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Search for your name",
                    "Click on your record",
                    "Scroll down and click 'Remove This Record'",
                    "Complete CAPTCHA and confirm",
                ],
                privacyEmail: nil,
                supportsGDPR: false, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "beenverified", brokerName: "BeenVerified", category: .peopleSearch,
                description: "Background check and people search service",
                optOutURL: "https://www.beenverified.com/app/optout/search",
                difficulty: .easy, estimatedMinutes: 3, processingTime: "24 hours",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Enter your first name, last name, and state",
                    "Find your record in the results",
                    "Click 'Proceed with opt out'",
                    "Enter your email address",
                    "Confirm via the link sent to your email",
                ],
                privacyEmail: "privacy@beenverified.com",
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "peoplefinder", brokerName: "PeopleFinder", category: .peopleSearch,
                description: "Public records search engine with addresses and phone numbers",
                optOutURL: "https://www.peoplefinder.com/optout",
                difficulty: .easy, estimatedMinutes: 3, processingTime: "24-48 hours",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Search for your name and select your record",
                    "Submit the opt-out request",
                    "Verify via email if prompted",
                ],
                privacyEmail: nil,
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            // MEDIUM — People Search
            OptOutAction(
                id: "whitepages", brokerName: "Whitepages", category: .peopleSearch,
                description: "One of the largest people search databases",
                optOutURL: "https://www.whitepages.com/suppression-requests",
                difficulty: .medium, estimatedMinutes: 5, processingTime: "24-72 hours",
                method: .combined,
                steps: [
                    "Search for your name on whitepages.com first",
                    "Copy the full URL of your profile",
                    "Tap 'Open Opt-Out Page' below",
                    "Paste your profile URL into the form",
                    "You'll receive an automated phone call for verification",
                    "Enter the verification code",
                    "Confirm via email",
                ],
                privacyEmail: "support@whitepages.com",
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "intelius", brokerName: "Intelius", category: .peopleSearch,
                description: "People search and background check provider (owns Spokeo, US Search)",
                optOutURL: "https://suppression.peopleconnect.us/login",
                difficulty: .medium, estimatedMinutes: 5, processingTime: "7 days",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Create an account or log in",
                    "Search for your listing",
                    "Select all records you want removed",
                    "Submit the opt-out request",
                    "Wait for confirmation email (up to 7 days)",
                ],
                privacyEmail: "privacy@intelius.com",
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "radaris", brokerName: "Radaris", category: .peopleSearch,
                description: "People search with detailed profiles, property records, and court records",
                optOutURL: "https://radaris.com/control/privacy",
                difficulty: .medium, estimatedMinutes: 5, processingTime: "24-48 hours",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "You'll need to create an account first",
                    "Once logged in, go to Privacy settings",
                    "Search for your profile",
                    "Request removal of your information",
                    "Delete your Radaris account afterward",
                ],
                privacyEmail: nil,
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            // DATA AGGREGATORS
            OptOutAction(
                id: "acxiom", brokerName: "Acxiom", category: .dataAggregator,
                description: "One of the world's largest data brokers — sells consumer data to marketers globally",
                optOutURL: "https://isapps.acxiom.com/optout/optout.aspx",
                difficulty: .medium, estimatedMinutes: 5, processingTime: "2-4 weeks",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Fill in your personal information in the form",
                    "Submit the opt-out request",
                    "Verify your identity via email",
                    "Allow 2-4 weeks for processing",
                ],
                privacyEmail: "consumeradvo@acxiom.com",
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "oracle_datacloud", brokerName: "Oracle Data Cloud", category: .dataAggregator,
                description: "Massive advertising data broker owned by Oracle",
                optOutURL: "https://datacloudoptout.oracle.com",
                difficulty: .medium, estimatedMinutes: 5, processingTime: "30 days",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Complete the online opt-out form",
                    "Verify your email address",
                    "Allow up to 30 days for processing",
                ],
                privacyEmail: nil,
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            // ADVERTISING
            OptOutAction(
                id: "google_ads", brokerName: "Google Ad Personalization", category: .advertising,
                description: "Controls what data Google uses to show you personalized ads",
                optOutURL: "https://adssettings.google.com",
                difficulty: .easy, estimatedMinutes: 1, processingTime: "Immediate",
                method: .accountSettings,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Sign into your Google account",
                    "Toggle off 'Ad personalization'",
                    "Done — takes effect immediately",
                ],
                privacyEmail: nil,
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "facebook_offsite", brokerName: "Facebook Off-Site Tracking", category: .advertising,
                description: "Controls how Meta tracks you across other websites and apps",
                optOutURL: "https://www.facebook.com/off_facebook_activity/",
                difficulty: .easy, estimatedMinutes: 2, processingTime: "Immediate",
                method: .accountSettings,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Sign into Facebook",
                    "Tap 'Clear History' to remove tracked activity",
                    "Tap 'More Options' then 'Manage Future Activity'",
                    "Toggle off future off-Facebook activity tracking",
                ],
                privacyEmail: nil,
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            // SEARCH ENGINE
            OptOutAction(
                id: "google_results_about_you", brokerName: "Google — Results About You", category: .searchEngine,
                description: "Request Google remove search results that show your personal info",
                optOutURL: "https://myactivity.google.com/results-about-you",
                difficulty: .easy, estimatedMinutes: 5, processingTime: "Days to weeks",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Sign into your Google account",
                    "Set up alerts for your name",
                    "Google will notify you when your personal info appears in search results",
                    "Review each result and request removal",
                    "Google reviews requests and removes qualifying results",
                ],
                privacyEmail: nil,
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "google_remove_content", brokerName: "Google — Remove Outdated Content", category: .searchEngine,
                description: "Request removal of outdated cached pages from Google Search results",
                optOutURL: "https://search.google.com/search-console/remove-outdated-content",
                difficulty: .easy, estimatedMinutes: 3, processingTime: "1-2 days",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Sign into your Google account",
                    "Enter the URL of the outdated search result",
                    "Submit the removal request",
                    "Google will process within 1-2 days",
                ],
                privacyEmail: nil,
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            // MARKETING
            OptOutAction(
                id: "epsilon", brokerName: "Epsilon", category: .marketing,
                description: "Marketing data company — sends targeted physical mail and email ads",
                optOutURL: "https://www.epsilon.com/privacy-policy",
                difficulty: .easy, estimatedMinutes: 2, processingTime: "10 business days",
                method: .email,
                steps: [
                    "Use the 'Generate Email' button below",
                    "Or manually email optout@epsilon.com",
                    "Include your full name and mailing address",
                    "Request removal from all marketing lists",
                    "Allow 10 business days",
                ],
                privacyEmail: "optout@epsilon.com",
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),

            OptOutAction(
                id: "dmachoice", brokerName: "DMAchoice", category: .marketing,
                description: "Opt out of direct mail from many companies at once via the Direct Marketing Association",
                optOutURL: "https://www.dmachoice.org/register.php",
                difficulty: .easy, estimatedMinutes: 5, processingTime: "30-90 days",
                method: .webForm,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Register for a free account",
                    "Verify your email",
                    "Select your mail preferences (opt out of all or specific categories)",
                    "Submit — junk mail will decrease over 30-90 days",
                ],
                privacyEmail: nil,
                supportsGDPR: false, supportsCCPA: true, status: .notStarted
            ),

            // HARD
            OptOutAction(
                id: "lexisnexis", brokerName: "LexisNexis", category: .dataAggregator,
                description: "Legal and business data giant with extensive consumer records",
                optOutURL: "https://optout.lexisnexis.com",
                difficulty: .hard, estimatedMinutes: 15, processingTime: "30 days",
                method: .combined,
                steps: [
                    "Tap 'Open Opt-Out Page' below",
                    "Download the opt-out form (PDF)",
                    "Fill it out completely — they require ID verification",
                    "Provide a copy of your government ID",
                    "Mail or fax the completed form (address on the form)",
                    "Allow up to 30 days for processing",
                    "Keep a copy of everything you send",
                ],
                privacyEmail: "privacy.information.mgr@lexisnexis.com",
                supportsGDPR: true, supportsCCPA: true, status: .notStarted
            ),
        ]
    }

    // MARK: - Deletion Services Database

    static let deletionServices: [DeletionService] = [
        DeletionService(
            id: "incogni", name: "Incogni",
            description: "Automated data broker removal service by Surfshark. Sends removal requests on your behalf and monitors for re-listings.",
            websiteURL: "https://incogni.com",
            monthlyPrice: "$12.99", yearlyPrice: "$6.49/mo (billed annually)",
            freeOption: false, brokersCovered: 180,
            features: ["Automated removal requests to 180+ brokers", "Monitors for re-listings", "Progress dashboard", "GDPR and CCPA requests", "30-day money-back guarantee"],
            pros: ["Best value for money", "Large broker coverage (180+)", "Fully automated", "Regular re-scanning"],
            cons: ["No free tier", "No iOS app", "Results take weeks to months"],
            hasIOSApp: false, rating: 4.5
        ),
        DeletionService(
            id: "deleteme", name: "DeleteMe",
            description: "Privacy service by Abine. Team manually submits opt-outs and sends you reports.",
            websiteURL: "https://joindeleteme.com",
            monthlyPrice: nil, yearlyPrice: "$10.75/mo ($129/year)",
            freeOption: false, brokersCovered: 750,
            features: ["Human team submits opt-outs", "Quarterly privacy reports", "750+ data broker coverage", "Family plans available", "Continuously monitors re-listings"],
            pros: ["Largest broker coverage (750+)", "Human review of results", "Detailed quarterly reports", "Good family pricing"],
            cons: ["More expensive than competitors", "Reports only quarterly", "No iOS app"],
            hasIOSApp: false, rating: 4.3
        ),
        DeletionService(
            id: "optery", name: "Optery",
            description: "Data removal service with a free tier that shows where your data exists, and paid tiers that remove it.",
            websiteURL: "https://www.optery.com",
            monthlyPrice: nil, yearlyPrice: "$249/year (Basic)",
            freeOption: true, brokersCovered: 350,
            features: ["Free scan shows where your data is", "Paid tier automates removal", "Exposure report with screenshots", "Monitors for re-listings", "Multiple plan tiers"],
            pros: ["Free tier lets you see results first", "Screenshots prove data was found", "Good mid-range coverage (350+)", "Transparent about what they find"],
            cons: ["Free tier scan-only, no removal", "Expensive for full removal ($249+/year)", "Smaller coverage than DeleteMe"],
            hasIOSApp: false, rating: 4.2
        ),
        DeletionService(
            id: "kanary", name: "Kanary",
            description: "Data broker removal service with its own iOS app for mobile-first privacy management.",
            websiteURL: "https://www.thekanary.com",
            monthlyPrice: "$14.99", yearlyPrice: "$89.99/year",
            freeOption: false, brokersCovered: 400,
            features: ["iOS app for mobile management", "Automated removal requests", "Real-time progress tracking", "Family plans", "Dark web monitoring"],
            pros: ["Has its own iOS app", "Dark web monitoring included", "Good mobile experience", "Competitive yearly pricing"],
            cons: ["Smaller company — less proven track record", "Monthly pricing is high", "Newer service with less history"],
            hasIOSApp: true, rating: 4.0
        ),
    ]
}
