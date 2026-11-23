import Foundation

enum InvestigationTopic: String, CaseIterable, Identifiable {
    case wifi = "Wi-Fi"
    case connection = "Website access"
    case speed = "Speed"
    case privacy = "DNS privacy"
    case security = "Website security"
    case vpn = "VPN routing"

    var id: Self { self }

    var question: String {
        switch self {
        case .wifi: return "Is the slowdown visible at the router or only on the way to a website?"
        case .connection: return "Is one website affected, or do other sites fail on this connection too?"
        case .speed: return "Does one download stall while several simultaneous requests can still transfer data?"
        case .privacy: return "Can encrypted DNS replies get through, and does your browser use the resolver you expect?"
        case .security: return "Does iOS trust the site’s certificate, and does the same result occur on another connection?"
        case .vpn: return "Do the same sites and IPv6 behave differently after one change to your VPN route?"
        }
    }

    var usesHostname: Bool { self == .connection || self == .security || self == .vpn }
}

enum InvestigationMetric: String {
    case router, site, reference, lookup, single, parallel, doh, dot, resolver, certificate, referenceCertificate, ipv6, exit

    var prefersMore: Bool { self == .single || self == .parallel }
}

struct InvestigationReading {
    let label: String
    let detail: String
    var samples: [Double] = []
    var outcome: Bool?
}

struct InvestigationRoute: Equatable {
    let generation: Date
    let interface: String?
    let wifi: String?
    let vpn: VPNState
    let exit: String?

    var description: String {
        let access = interface == "WiFi" ? "Wi-Fi" : interface ?? "No active connection observed"
        switch vpn {
        case .on: return "\(access) · VPN connected"
        case .probablyOn: return "\(access) · VPN or proxy inferred"
        case .off: return "\(access) · VPN off"
        case .probablyOff: return "\(access) · VPN probably off"
        default: return "\(access) · VPN status unverified"
        }
    }

    private func sameVPN(as previous: Self) -> Bool {
        if vpn.isLikelyOff, previous.vpn.isLikelyOff { return true }
        return vpn.isLikelyOn && previous.vpn.isLikelyOn && exit != nil && exit == previous.exit
    }

    func comparisonIssue(after: Self, change: InvestigationChange) -> String? {
        switch change {
        case .nearRouter, .pauseTransfers, .retrySite, .dnsSettings, .timeSettings:
            guard generation == after.generation, interface == after.interface,
                  wifi == after.wifi, vpn == after.vpn,
                  !(exit != nil && after.exit != nil && exit != after.exit) else {
                return "The observed connection changed during this comparison. Take a new baseline before changing the next setting."
            }
        case .otherAccess:
            let changedWiFi = interface == "WiFi" && after.interface == "WiFi"
                && wifi != nil && after.wifi != nil && wifi != after.wifi
            guard let interface, let next = after.interface,
                  changedWiFi || interface != next else {
                return "A different Wi-Fi network or connection type could not be confirmed."
            }
            guard after.sameVPN(as: self) else {
                return "The VPN conditions could not be matched. Check that you kept the same VPN server or kept the VPN off on both routes."
            }
        case .vpnServer, .connectVPN:
            guard interface == "WiFi", after.interface == "WiFi", let wifi, wifi == after.wifi else {
                return "Use the same identified Wi-Fi for both VPN samples."
            }
            if change == .connectVPN {
                guard vpn.isLikelyOff, after.vpn.isLikelyOn, after.exit != nil else {
                    return "A VPN-off baseline and a fresh exit from the connected VPN are needed for this comparison."
                }
                return nil
            }
            guard vpn.isLikelyOn, after.vpn.isLikelyOn, let exit, let otherExit = after.exit, exit != otherExit else {
                return "Both runs need a VPN signal and different observed public exits. A server change can share the same exit."
            }
        }
        return nil
    }
}

enum InvestigationChange: String {
    case nearRouter = "Move closer to the router"
    case pauseTransfers = "Pause background transfers"
    case retrySite = "Retry the affected site"
    case otherAccess = "Try another trusted connection"
    case dnsSettings = "Check the active resolver"
    case timeSettings = "Check date and time"
    case vpnServer = "Try another VPN server"
    case connectVPN = "Compare with your VPN connected"

    var instructions: String {
        switch self {
        case .nearRouter:
            return "Move close to the main router. Stay on the same Wi-Fi and keep the VPN setting. Come back here to rerun the router and web tests."
        case .pauseTransfers:
            return "Pause a large download, upload or backup on a device you control. Stay on the same connection with the same VPN server."
        case .retrySite:
            return "Open the affected site in Safari and note whether the page loads. Stay on the same connection and repeat these website checks."
        case .otherAccess:
            return "Switch to another trusted Wi-Fi or cellular connection. Keep the same VPN server if you use one. Return here to repeat the same checks."
        case .dnsSettings:
            return "Check the DNS or leak-protection setting in your VPN app, or your installed DNS profile. Use the provider’s verification page in the browser you actually use. Record whether it shows the resolver you expect before and after changing one setting."
        case .timeSettings:
            return "Open Settings → General → Date & Time and check that the device clock is correct. Return here and rerun the same certificate checks."
        case .vpnServer:
            return "In your VPN app, choose another trusted server. Leave Wi-Fi unchanged. Return here and repeat the same website and IPv6 checks."
        case .connectVPN:
            return "Connect to your usual VPN in its app. Keep this Wi-Fi network. Return here and repeat the same website and IPv6 checks."
        }
    }
}

struct InvestigationSample {
    let route: InvestigationRoute
    let at: Date
    var readings: [InvestigationMetric: InvestigationReading]
    var ipv6: String?

    static let order: [InvestigationMetric] = [
        .router, .site, .reference, .lookup, .single, .parallel, .doh, .dot,
        .resolver, .certificate, .referenceCertificate, .exit, .ipv6
    ]

    var orderedReadings: [InvestigationReading] { Self.order.compactMap { readings[$0] } }
}

struct InvestigationLead {
    let headline: String
    let evidence: String
    let change: InvestigationChange
    let metric: InvestigationMetric
    let nextIfUnchanged: String

    var acrossAccess: Self {
        Self(headline: "Test the same symptom on a second connection",
            evidence: "The first change did not improve the measured result. Compare access networks while keeping the other conditions fixed.",
            change: .otherAccess, metric: metric == .router ? .site : metric, nextIfUnchanged: nextIfUnchanged)
    }
}

enum InvestigationVerdict {
    case improved, worsened, noChange, couldNotCompare

    var title: String {
        switch self {
        case .improved: return "Improved in this test"
        case .worsened: return "Worse in this test"
        case .noChange: return "No clear improvement"
        case .couldNotCompare: return "Could not compare"
        }
    }
}

enum InvestigationReasoning {
    static func lead(for topic: InvestigationTopic, sample: InvestigationSample) -> InvestigationLead {
        let reading = sample.readings
        let anotherSite = "If only this site keeps failing across connections, contact the site operator and include the hostname and test times."
        let access = "Try the same checks on a second trusted connection. If several devices fail on the original network, share the evidence with the network operator."
        switch topic {
        case .wifi:
            let local = reading[.router].flatMap { MeasurementStatistics.median($0.samples) }
            if let local, local > 30 {
                return InvestigationLead(headline: "The router response was slow", evidence: "The delay was measurable on the local hop. Repeating it close to the router helps test whether position matters.", change: .nearRouter, metric: .router, nextIfUnchanged: access)
            }
            let explanation = local == nil
                ? "The router check didn’t return a timing. Compare the same websites on another connection before blaming Wi-Fi hardware."
                : "The local router answered. Compare the same websites on a second connection to narrow down where the difference occurs."
            return InvestigationLead(headline: "Compare the website path", evidence: explanation, change: .otherAccess, metric: .site, nextIfUnchanged: access)
        case .connection:
            if reading[.site]?.outcome == false, reading[.reference]?.outcome == true {
                let lookup = reading[.lookup]?.outcome == false ? "The hostname lookup also failed. " : ""
                return InvestigationLead(headline: "The affected site and the reference behaved differently", evidence: lookup + "The reference responded successfully. Test the affected hostname on another connection before changing settings that affect every site.", change: .otherAccess, metric: .site, nextIfUnchanged: anotherSite)
            }
            if reading[.site]?.outcome == true, reading[.reference]?.outcome == true {
                if let site = reading[.site].flatMap({ MeasurementStatistics.median($0.samples) }),
                   let reference = reading[.reference].flatMap({ MeasurementStatistics.median($0.samples) }),
                   site >= 1_000, reference >= 1_000 {
                    return InvestigationLead(headline: "Both sites responded slowly",
                        evidence: "Both HTTPS header checks took around a second or more. Compare the same endpoints on another connection to see whether the delay follows this route.",
                        change: .otherAccess, metric: .site, nextIfUnchanged: access)
                }
                return InvestigationLead(headline: "Both test sites responded", evidence: "This check captured working HTTPS requests. If the problem is intermittent, repeat when you notice it.", change: .retrySite, metric: .site, nextIfUnchanged: anotherSite)
            }
            return InvestigationLead(headline: "The web checks were inconclusive or failed", evidence: "Compare these same sites on a trusted second connection. Complete a network sign-in page if one appears.", change: .otherAccess, metric: .site, nextIfUnchanged: access)
        case .speed:
            let single = reading[.single]?.samples ?? []
            let parallel = reading[.parallel]?.samples ?? []
            let gap = parallel.count >= 2 && (single.isEmpty ||
                (single.count >= 2 && (parallel.min() ?? 0) > (single.max() ?? 0) * 1.5))
            return InvestigationLead(headline: gap ? "Parallel requests transferred data more reliably or quickly" : "Check how the single-request download repeats",
                evidence: gap ? "This difference occurred with the same hostname and total bytes. A good aggregate speed can hide a slow individual transfer. The exact cause is still open." : "The samples measure fixed-size downloads to one endpoint. A second run after pausing competing traffic can show whether that change helps.",
                change: gap ? .otherAccess : .pauseTransfers, metric: .single, nextIfUnchanged: gap
                    ? "If single requests are still slow on both connections, share the paired results with the network operator. Parallel transfer may help apps that support it."
                    : access)
        case .privacy:
            let responded = reading[.doh]?.outcome == true || reading[.dot]?.outcome == true
            return InvestigationLead(headline: responded ? "An encrypted DNS test reply got through" : "No validated encrypted DNS reply arrived",
                evidence: "These probes test reachability. Your provider’s verification page is the evidence for the resolver your browser actually uses.",
                change: .dnsSettings, metric: .resolver, nextIfUnchanged: "If the resolver still differs from the one you configured, ask your DNS or VPN provider which resolver it expects under your settings.")
        case .security:
            if reading[.certificate]?.outcome == false, reading[.referenceCertificate]?.outcome == true {
                return InvestigationLead(headline: "iOS rejected the affected site’s certificate", evidence: "The reference site passed system trust. Compare the affected host on another trusted connection to see whether the trust failure follows the site.", change: .otherAccess, metric: .certificate, nextIfUnchanged: "If the same site still fails trust, leave the warning in place and contact the site operator.")
            }
            let trusted = reading[.certificate]?.outcome == true && reading[.referenceCertificate]?.outcome == true
            return InvestigationLead(headline: trusted ? "iOS trusted both tested certificates" : "Check whether certificate trust changes",
                evidence: trusted ? "The result applies to the two hostnames and this connection. Repeat while the browser warning is present if it returns." : "An incorrect device clock can affect certificate evaluation. A missing certificate still needs a reachable endpoint to assess it.",
                change: .timeSettings, metric: .certificate, nextIfUnchanged: anotherSite)
        case .vpn:
            let identifiedWiFi = sample.route.interface == "WiFi" && sample.route.wifi != nil
            let change: InvestigationChange
            if identifiedWiFi && sample.route.vpn.isLikelyOff {
                change = .connectVPN
            } else if identifiedWiFi && sample.route.vpn.isLikelyOn && sample.route.exit != nil {
                change = .vpnServer
            } else {
                change = .otherAccess
            }
            return InvestigationLead(headline: "Compare the same sites across one route change",
                evidence: "The website results describe this route. IPv6 is sampled separately and a missing sample leaves protection unverified.",
                change: change, metric: .site, nextIfUnchanged: "Keep both sets of observations. If the same problem persists on multiple routes, report the website and test results to the provider or site operator.")
        }
    }

    static func compare(_ before: InvestigationSample, _ after: InvestigationSample, using lead: InvestigationLead) -> (InvestigationVerdict, String) {
        if let issue = before.route.comparisonIssue(after: after.route, change: lead.change) {
            return (.couldNotCompare, issue)
        }
        guard let first = before.readings[lead.metric], let second = after.readings[lead.metric] else {
            return (.couldNotCompare, "Both runs need a reading for the same test.")
        }
        if let a = first.outcome, let b = second.outcome, a != b {
            return (b ? .improved : .worsened, "\(first.label) changed from \(first.detail) to \(second.detail).")
        }
        if let lowBefore = first.samples.min(), let highBefore = first.samples.max(),
           let lowAfter = second.samples.min(), let highAfter = second.samples.max(),
           let a = MeasurementStatistics.median(first.samples), let b = MeasurementStatistics.median(second.samples),
           first.samples.count == second.samples.count {
            let threshold = max(a * 0.2, lead.metric.prefersMore ? 1 : 25)
            let difference = lead.metric.prefersMore ? b - a : a - b
            let separates = difference > 0
                ? (lead.metric.prefersMore ? lowAfter > highBefore : highAfter < lowBefore)
                : (lead.metric.prefersMore ? highAfter < lowBefore : lowAfter > highBefore)
            if abs(difference) >= threshold, separates {
                return (difference > 0 ? .improved : .worsened, "\(first.label) changed from \(first.detail) to \(second.detail).")
            }
            return (.noChange, "The measured difference was small or the sample ranges overlapped. \(lead.nextIfUnchanged)")
        }
        if let a = first.outcome, a == second.outcome {
            return (.noChange, "The result repeated for \(first.label). \(lead.nextIfUnchanged)")
        }
        return (.couldNotCompare, "The two runs did not produce matching usable readings. Repeat the same measurement before drawing a conclusion.")
    }
}
