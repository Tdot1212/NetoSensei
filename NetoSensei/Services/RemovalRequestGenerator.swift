//
//  RemovalRequestGenerator.swift
//  NetoSensei
//
//  Generates GDPR, CCPA, and generic data removal request emails
//  for sending to data brokers and people search sites.
//

import Foundation

class RemovalRequestGenerator {
    static let shared = RemovalRequestGenerator()

    private init() {}

    // MARK: - Generate GDPR Request

    func generateGDPRRequest(for broker: DataBroker, profile: ScanProfile) -> String {
        let date = Date().formatted(date: .long, time: .omitted)

        return """
        Subject: GDPR Data Deletion Request - \(profile.fullName)

        To: Data Protection Officer
        \(broker.name)

        Date: \(date)

        Dear Data Protection Team,

        I am writing to request the erasure of my personal data that you hold, pursuant to Article 17 of the General Data Protection Regulation (GDPR).

        MY DETAILS:
        Full Name: \(profile.fullName)
        \(profile.email != nil ? "Email: \(profile.email!)" : "")
        \(profile.phone != nil ? "Phone: \(profile.phone!)" : "")
        \(profile.city != nil && profile.state != nil ? "Location: \(profile.city!), \(profile.state!)" : "")
        Country: \(profile.country)

        REQUEST:
        I request that you:
        1. Confirm what personal data you hold about me
        2. Delete all personal data you hold about me
        3. Ensure any third parties who have received my data also delete it
        4. Confirm completion of this request within 30 days

        LEGAL BASIS:
        Under GDPR Article 17, I have the right to have my personal data erased where:
        - The personal data is no longer necessary for the purpose it was collected
        - I withdraw my consent for processing
        - I object to the processing and there are no overriding legitimate grounds
        - The personal data was unlawfully processed

        RESPONSE REQUIRED:
        Please respond to this request within one month, as required by GDPR Article 12(3). If you need to extend this period, please inform me within one month of receipt of this request.

        If you do not comply with this request, I reserve the right to lodge a complaint with the relevant supervisory authority.

        Thank you for your attention to this matter.

        Sincerely,
        \(profile.fullName)
        \(profile.email ?? "")
        """
    }

    // MARK: - Generate CCPA Request

    func generateCCPARequest(for broker: DataBroker, profile: ScanProfile) -> String {
        let date = Date().formatted(date: .long, time: .omitted)

        return """
        Subject: California Consumer Privacy Act (CCPA) - Data Deletion Request

        To: Privacy Department
        \(broker.name)

        Date: \(date)

        To Whom It May Concern,

        I am a California resident and I am exercising my rights under the California Consumer Privacy Act (CCPA), California Civil Code Section 1798.100 et seq.

        MY INFORMATION:
        Full Name: \(profile.fullName)
        \(profile.email != nil ? "Email: \(profile.email!)" : "")
        \(profile.phone != nil ? "Phone: \(profile.phone!)" : "")
        \(profile.city != nil && profile.state != nil ? "Location: \(profile.city!), \(profile.state!)" : "")

        I REQUEST THE FOLLOWING:

        1. RIGHT TO DELETE (Section 1798.105):
        Please delete all personal information you have collected about me.

        2. RIGHT TO KNOW (Section 1798.100):
        Prior to deletion, please provide me with:
        - The categories of personal information collected
        - The sources of that information
        - The business purpose for collecting the information
        - The categories of third parties with whom you share the information

        3. DO NOT SELL MY INFORMATION (Section 1798.120):
        If you sell personal information, I opt out of the sale of my personal information.

        VERIFICATION:
        I verify that I am the person whose information is the subject of this request.

        DEADLINE:
        Under CCPA, you must respond to this request within 45 days. If you need an extension, you must notify me within the initial 45-day period.

        CONTACT:
        Please send your response to:
        \(profile.email ?? "[Your email address]")

        Thank you for your prompt attention to this matter.

        Sincerely,
        \(profile.fullName)
        """
    }

    // MARK: - Generate Generic Opt-Out Email

    func generateOptOutEmail(for broker: DataBroker, profile: ScanProfile) -> String {
        let date = Date().formatted(date: .long, time: .omitted)

        return """
        Subject: Opt-Out / Data Removal Request - \(profile.fullName)

        To: \(broker.name) Privacy Team

        Date: \(date)

        Hello,

        I am writing to request the removal of my personal information from your database and website.

        MY DETAILS:
        Name: \(profile.fullName)
        \(profile.email != nil ? "Email: \(profile.email!)" : "")
        \(profile.phone != nil ? "Phone: \(profile.phone!)" : "")
        \(profile.city != nil && profile.state != nil ? "Location: \(profile.city!), \(profile.state!)" : "")

        REQUEST:
        Please remove all listings and records associated with my name and personal information from your service.

        I do not consent to my personal information being publicly available or sold to third parties.

        Please confirm once this removal has been completed.

        Thank you,
        \(profile.fullName)
        """
    }

    // MARK: - Get Appropriate Request Type

    func getRequest(for broker: DataBroker, profile: ScanProfile) -> (subject: String, body: String) {
        let body: String
        let subject: String

        if profile.country == "United States" && (profile.state == "California" || profile.state == "CA") && broker.supportsCCPA {
            body = generateCCPARequest(for: broker, profile: profile)
            subject = "CCPA Data Deletion Request - \(profile.fullName)"
        } else if broker.supportsGDPR {
            body = generateGDPRRequest(for: broker, profile: profile)
            subject = "GDPR Data Deletion Request - \(profile.fullName)"
        } else {
            body = generateOptOutEmail(for: broker, profile: profile)
            subject = "Data Removal Request - \(profile.fullName)"
        }

        return (subject, body)
    }
}
