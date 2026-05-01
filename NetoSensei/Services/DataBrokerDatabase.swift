//
//  DataBrokerDatabase.swift
//  NetoSensei
//
//  Database of known data brokers with opt-out information,
//  difficulty ratings, and step-by-step removal instructions.
//

import Foundation

// MARK: - Data Broker Info

struct DataBroker: Identifiable, Codable {
    let id: String
    let name: String
    let category: Category
    let description: String
    let websiteURL: String
    let optOutURL: String?
    let optOutMethod: OptOutMethod
    let difficulty: Difficulty
    let processingTime: String
    let requiresID: Bool
    let requiresEmail: Bool
    let requiresPhone: Bool
    let supportsCCPA: Bool
    let supportsGDPR: Bool
    let searchURL: String?
    let instructions: [String]

    enum Category: String, Codable, CaseIterable {
        case peopleSearch = "People Search"
        case dataAggregator = "Data Aggregator"
        case marketingList = "Marketing List"
        case backgroundCheck = "Background Check"
        case socialMedia = "Social Media"
        case publicRecords = "Public Records"
        case advertising = "Advertising"
        case other = "Other"

        var icon: String {
            switch self {
            case .peopleSearch: return "person.crop.circle.badge.questionmark"
            case .dataAggregator: return "externaldrive.connected.to.line.below"
            case .marketingList: return "envelope.badge"
            case .backgroundCheck: return "doc.text.magnifyingglass"
            case .socialMedia: return "person.2.circle"
            case .publicRecords: return "building.columns"
            case .advertising: return "megaphone"
            case .other: return "folder"
            }
        }
    }

    enum OptOutMethod: String, Codable {
        case webForm = "Web Form"
        case email = "Email"
        case phone = "Phone Call"
        case mail = "Physical Mail"
        case accountDeletion = "Delete Account"
        case combined = "Multiple Methods"
    }

    enum Difficulty: String, Codable {
        case easy = "Easy"
        case medium = "Medium"
        case hard = "Hard"
        case veryHard = "Very Hard"

        var estimatedMinutes: Int {
            switch self {
            case .easy: return 2
            case .medium: return 5
            case .hard: return 15
            case .veryHard: return 30
            }
        }
    }
}

// MARK: - Data Broker Database

class DataBrokerDatabase {
    static let shared = DataBrokerDatabase()

    let brokers: [DataBroker]

    private init() {
        brokers = [
            // PEOPLE SEARCH SITES
            DataBroker(
                id: "spokeo",
                name: "Spokeo",
                category: .peopleSearch,
                description: "Aggregates public records, social media, and other sources to create people profiles.",
                websiteURL: "https://www.spokeo.com",
                optOutURL: "https://www.spokeo.com/optout",
                optOutMethod: .webForm,
                difficulty: .easy,
                processingTime: "24-48 hours",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: "https://www.spokeo.com/search?q={name}",
                instructions: [
                    "Go to spokeo.com/optout",
                    "Search for your listing",
                    "Copy the URL of your profile",
                    "Paste the URL in the opt-out form",
                    "Enter your email address",
                    "Click the confirmation link sent to your email",
                ]
            ),

            DataBroker(
                id: "whitepages",
                name: "Whitepages",
                category: .peopleSearch,
                description: "One of the largest people search databases with phone, address, and background info.",
                websiteURL: "https://www.whitepages.com",
                optOutURL: "https://www.whitepages.com/suppression-requests",
                optOutMethod: .webForm,
                difficulty: .medium,
                processingTime: "24-72 hours",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: true,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: "https://www.whitepages.com/name/{name}",
                instructions: [
                    "Find your listing on Whitepages",
                    "Copy the full URL of your profile",
                    "Go to whitepages.com/suppression-requests",
                    "Paste your profile URL",
                    "Verify via phone call (automated)",
                    "Confirm removal via email",
                ]
            ),

            DataBroker(
                id: "beenverified",
                name: "BeenVerified",
                category: .peopleSearch,
                description: "Background check and people search service.",
                websiteURL: "https://www.beenverified.com",
                optOutURL: "https://www.beenverified.com/app/optout/search",
                optOutMethod: .webForm,
                difficulty: .easy,
                processingTime: "24 hours",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Go to beenverified.com/app/optout/search",
                    "Search for your name and state",
                    "Find your record",
                    "Click 'Proceed with opt out'",
                    "Enter your email",
                    "Confirm via email link",
                ]
            ),

            DataBroker(
                id: "intelius",
                name: "Intelius",
                category: .peopleSearch,
                description: "People search and background check provider.",
                websiteURL: "https://www.intelius.com",
                optOutURL: "https://www.intelius.com/opt-out",
                optOutMethod: .webForm,
                difficulty: .medium,
                processingTime: "7 days",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Go to intelius.com/opt-out",
                    "Search for your listing",
                    "Select all records to remove",
                    "Provide your email address",
                    "Complete verification",
                    "Wait for confirmation email",
                ]
            ),

            DataBroker(
                id: "peoplefinder",
                name: "PeopleFinder",
                category: .peopleSearch,
                description: "Public records search engine.",
                websiteURL: "https://www.peoplefinder.com",
                optOutURL: "https://www.peoplefinder.com/optout",
                optOutMethod: .webForm,
                difficulty: .easy,
                processingTime: "24-48 hours",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Visit peoplefinder.com/optout",
                    "Search for your name",
                    "Select your record",
                    "Submit opt-out request",
                    "Verify via email",
                ]
            ),

            DataBroker(
                id: "truepeoplesearch",
                name: "TruePeopleSearch",
                category: .peopleSearch,
                description: "Free people search with addresses and phone numbers.",
                websiteURL: "https://www.truepeoplesearch.com",
                optOutURL: "https://www.truepeoplesearch.com/removal",
                optOutMethod: .webForm,
                difficulty: .easy,
                processingTime: "24-72 hours",
                requiresID: false,
                requiresEmail: false,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: false,
                searchURL: "https://www.truepeoplesearch.com/results?name={name}",
                instructions: [
                    "Find your listing on TruePeopleSearch",
                    "Scroll to bottom of your profile",
                    "Click 'Remove This Record'",
                    "Complete the CAPTCHA",
                    "Confirm removal",
                ]
            ),

            DataBroker(
                id: "fastpeoplesearch",
                name: "FastPeopleSearch",
                category: .peopleSearch,
                description: "Free people search directory.",
                websiteURL: "https://www.fastpeoplesearch.com",
                optOutURL: "https://www.fastpeoplesearch.com/removal",
                optOutMethod: .webForm,
                difficulty: .easy,
                processingTime: "24-48 hours",
                requiresID: false,
                requiresEmail: false,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: false,
                searchURL: nil,
                instructions: [
                    "Find your listing",
                    "Click the record",
                    "Scroll to 'Remove This Record'",
                    "Complete CAPTCHA",
                    "Confirm removal",
                ]
            ),

            // DATA AGGREGATORS
            DataBroker(
                id: "acxiom",
                name: "Acxiom",
                category: .dataAggregator,
                description: "One of the largest data brokers, sells consumer data to marketers.",
                websiteURL: "https://www.acxiom.com",
                optOutURL: "https://isapps.acxiom.com/optout/optout.aspx",
                optOutMethod: .webForm,
                difficulty: .medium,
                processingTime: "2-4 weeks",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Go to Acxiom's opt-out page",
                    "Fill in your personal information",
                    "Submit the request",
                    "Verify via email",
                    "Allow 2-4 weeks for processing",
                ]
            ),

            DataBroker(
                id: "lexisnexis",
                name: "LexisNexis",
                category: .dataAggregator,
                description: "Legal and business data provider with extensive consumer records.",
                websiteURL: "https://www.lexisnexis.com",
                optOutURL: "https://optout.lexisnexis.com",
                optOutMethod: .combined,
                difficulty: .hard,
                processingTime: "30 days",
                requiresID: true,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Visit LexisNexis opt-out portal",
                    "Download and complete the opt-out form",
                    "Provide a copy of your ID",
                    "Mail or fax the completed form",
                    "Wait up to 30 days for processing",
                ]
            ),

            DataBroker(
                id: "oracle",
                name: "Oracle Data Cloud",
                category: .dataAggregator,
                description: "Large-scale data broker for advertising and marketing.",
                websiteURL: "https://www.oracle.com/data-cloud",
                optOutURL: "https://datacloudoptout.oracle.com",
                optOutMethod: .webForm,
                difficulty: .medium,
                processingTime: "30 days",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Go to Oracle Data Cloud opt-out",
                    "Complete the online form",
                    "Verify your email",
                    "Allow 30 days for processing",
                ]
            ),

            // MARKETING LISTS
            DataBroker(
                id: "epsilon",
                name: "Epsilon",
                category: .marketingList,
                description: "Marketing data company, sends targeted mail and ads.",
                websiteURL: "https://www.epsilon.com",
                optOutURL: "https://www.epsilon.com/privacy-policy/",
                optOutMethod: .email,
                difficulty: .easy,
                processingTime: "10 business days",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Send email to optout@epsilon.com",
                    "Include your full name and address",
                    "Request removal from all marketing lists",
                    "Wait for confirmation",
                ]
            ),

            DataBroker(
                id: "dmachoice",
                name: "DMA Choice (Direct Marketing Association)",
                category: .marketingList,
                description: "Opt-out of direct mail from many companies at once.",
                websiteURL: "https://www.dmachoice.org",
                optOutURL: "https://www.dmachoice.org",
                optOutMethod: .webForm,
                difficulty: .easy,
                processingTime: "30-90 days",
                requiresID: false,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: false,
                searchURL: nil,
                instructions: [
                    "Register at dmachoice.org",
                    "Verify your email",
                    "Select mail preferences",
                    "Complete the opt-out process",
                    "Allow 30-90 days for mail to stop",
                ]
            ),

            // BACKGROUND CHECK
            DataBroker(
                id: "checkr",
                name: "Checkr",
                category: .backgroundCheck,
                description: "Background check service used by employers.",
                websiteURL: "https://checkr.com",
                optOutURL: "https://candidate.checkr.com",
                optOutMethod: .webForm,
                difficulty: .medium,
                processingTime: "7-10 days",
                requiresID: true,
                requiresEmail: true,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Go to candidate.checkr.com",
                    "Request a copy of your report",
                    "Submit dispute if information is incorrect",
                    "Request deletion under CCPA/GDPR",
                ]
            ),

            // ADVERTISING
            DataBroker(
                id: "google_ads",
                name: "Google Ad Personalization",
                category: .advertising,
                description: "Controls what data Google uses for personalized ads.",
                websiteURL: "https://adssettings.google.com",
                optOutURL: "https://adssettings.google.com",
                optOutMethod: .accountDeletion,
                difficulty: .easy,
                processingTime: "Immediate",
                requiresID: false,
                requiresEmail: false,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Go to adssettings.google.com",
                    "Sign into your Google account",
                    "Toggle off 'Ad personalization'",
                    "Changes take effect immediately",
                ]
            ),

            DataBroker(
                id: "facebook_ads",
                name: "Facebook/Meta Ad Preferences",
                category: .advertising,
                description: "Controls what data Facebook uses for ads.",
                websiteURL: "https://www.facebook.com/ads/preferences",
                optOutURL: "https://www.facebook.com/ads/preferences",
                optOutMethod: .accountDeletion,
                difficulty: .easy,
                processingTime: "Immediate",
                requiresID: false,
                requiresEmail: false,
                requiresPhone: false,
                supportsCCPA: true,
                supportsGDPR: true,
                searchURL: nil,
                instructions: [
                    "Go to Facebook Ad Preferences",
                    "Review 'Advertisers' section",
                    "Adjust 'Ad settings'",
                    "Disable 'Ads based on partners' data",
                ]
            ),
        ]
    }

    // MARK: - Search

    func getBrokersByCategory(_ category: DataBroker.Category) -> [DataBroker] {
        brokers.filter { $0.category == category }
    }

    func getBrokersByDifficulty(_ difficulty: DataBroker.Difficulty) -> [DataBroker] {
        brokers.filter { $0.difficulty == difficulty }
    }

    func getEasyOptOuts() -> [DataBroker] {
        brokers.filter { $0.difficulty == .easy }
    }

    func searchBrokers(_ query: String) -> [DataBroker] {
        let lowercased = query.lowercased()
        return brokers.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased)
        }
    }
}
