//
//  EducationalTooltips.swift
//  NetoSensei
//
//  Reusable educational tooltip system for technical terms
//

import SwiftUI

// MARK: - Glossary Entry

struct GlossaryEntry {
    let term: String
    let definition: String
    let example: String
    let whyItMatters: String
}

// MARK: - Network Glossary

struct NetworkGlossary {
    static let entries: [String: GlossaryEntry] = [
        "ISP": GlossaryEntry(
            term: "ISP",
            definition: "Internet Service Provider - the company that provides your internet connection.",
            example: "Like your electric company, but for internet. Examples: Comcast, AT&T, China Telecom.",
            whyItMatters: "Your ISP can see all your unencrypted traffic and may throttle certain services."
        ),
        "DNS": GlossaryEntry(
            term: "DNS",
            definition: "Domain Name System - translates website names (like google.com) into IP addresses computers understand.",
            example: "Like a phone book for the internet. You look up a name, it gives you a number.",
            whyItMatters: "Slow DNS = slow page loads. Compromised DNS can redirect you to fake websites."
        ),
        "VPN": GlossaryEntry(
            term: "VPN",
            definition: "Virtual Private Network - encrypts all your internet traffic and routes it through a secure server.",
            example: "Like a private tunnel between you and the internet. No one can see what's inside.",
            whyItMatters: "Protects your privacy on public WiFi and hides your activity from your ISP."
        ),
        "SSID": GlossaryEntry(
            term: "SSID",
            definition: "Service Set Identifier - the name of a WiFi network.",
            example: "The network name you see when connecting to WiFi, like 'Starbucks_WiFi' or 'Home_Network'.",
            whyItMatters: "Fake SSIDs can trick you into connecting to malicious networks."
        ),
        "BSSID": GlossaryEntry(
            term: "BSSID",
            definition: "Basic Service Set Identifier - the unique hardware address (MAC) of the WiFi router.",
            example: "Like a serial number for your router. Looks like 'AA:BB:CC:DD:EE:FF'.",
            whyItMatters: "Can identify if you're connected to the real router or a rogue access point."
        ),
        "Gateway": GlossaryEntry(
            term: "Gateway",
            definition: "The router that connects your local network to the internet.",
            example: "Like the front door of your house - all traffic to the outside world goes through it.",
            whyItMatters: "If the gateway is slow or unreachable, nothing on the internet works."
        ),
        "Latency": GlossaryEntry(
            term: "Latency",
            definition: "The time it takes for data to travel from your device to a server and back (round-trip).",
            example: "Like the delay between shouting across a canyon and hearing the echo.",
            whyItMatters: "High latency causes lag in video calls, gaming, and slow-feeling browsing."
        ),
        "Jitter": GlossaryEntry(
            term: "Jitter",
            definition: "Variation in latency over time. Inconsistent response times.",
            example: "Imagine if sometimes mail arrives in 1 day, sometimes 5 days - that unpredictability is jitter.",
            whyItMatters: "High jitter causes stuttering in video calls and audio glitches."
        ),
        "Packet Loss": GlossaryEntry(
            term: "Packet Loss",
            definition: "When data packets fail to reach their destination and are lost in transit.",
            example: "Like sending 10 letters but only 8 arrive. The lost ones need to be re-sent.",
            whyItMatters: "Causes buffering, frozen video, dropped calls, and slow downloads."
        ),
        "HTTPS": GlossaryEntry(
            term: "HTTPS",
            definition: "Secure version of HTTP that encrypts data between your browser and the website.",
            example: "The padlock icon in your browser. Means the connection is encrypted.",
            whyItMatters: "Without HTTPS, anyone on the same network could read your passwords and data."
        ),
        "TLS": GlossaryEntry(
            term: "TLS",
            definition: "Transport Layer Security - the encryption protocol that powers HTTPS.",
            example: "The invisible lock-and-key system that scrambles data so only you and the server can read it.",
            whyItMatters: "Outdated TLS versions have known vulnerabilities that attackers can exploit."
        ),
        "WebRTC": GlossaryEntry(
            term: "WebRTC",
            definition: "Web Real-Time Communication - browser technology for video calls and peer-to-peer connections.",
            example: "What makes browser-based video calls (like Google Meet) work without plugins.",
            whyItMatters: "Can leak your real IP address even when using a VPN, revealing your identity."
        ),
        "IP Address": GlossaryEntry(
            term: "IP Address",
            definition: "A unique number that identifies your device on a network, like a mailing address.",
            example: "Like your home address, but for the internet. Example: 192.168.1.100 or 203.0.113.50.",
            whyItMatters: "Your public IP reveals your approximate location and ISP to every website you visit."
        ),
        "IPv4": GlossaryEntry(
            term: "IPv4",
            definition: "Internet Protocol version 4 - the older addressing system using 4 numbers (like 192.168.1.1).",
            example: "The 'classic' internet address format. Running out of available addresses worldwide.",
            whyItMatters: "Still the most common protocol. Some services only work on IPv4."
        ),
        "IPv6": GlossaryEntry(
            term: "IPv6",
            definition: "Internet Protocol version 6 - the newer addressing system with much more available addresses.",
            example: "The 'next generation' address format, looks like '2001:0db8:85a3::8a2e:0370:7334'.",
            whyItMatters: "Some VPNs don't support IPv6, which can cause IP leaks."
        ),
        "Bandwidth": GlossaryEntry(
            term: "Bandwidth",
            definition: "The maximum amount of data that can be transferred per second on your connection.",
            example: "Like the width of a highway - wider means more cars (data) can flow at once.",
            whyItMatters: "Determines how fast you can download files and stream video."
        ),
        "Ping": GlossaryEntry(
            term: "Ping",
            definition: "A test that sends a small packet to a server and measures the round-trip time.",
            example: "Like saying 'hello' and timing how long it takes to hear 'hello' back.",
            whyItMatters: "Low ping = responsive connection. Essential for gaming and video calls."
        ),
        "Traceroute": GlossaryEntry(
            term: "Traceroute",
            definition: "Maps the path your data takes across the internet, showing every router it passes through.",
            example: "Like tracking a package and seeing every post office it stops at on the way.",
            whyItMatters: "Helps identify WHERE a network problem is occurring along the path."
        ),
        "MTU": GlossaryEntry(
            term: "MTU",
            definition: "Maximum Transmission Unit - the largest packet size your network can handle.",
            example: "Like the maximum box size a delivery truck can carry. Too big and it won't fit.",
            whyItMatters: "Wrong MTU settings cause mysterious connection drops and slow speeds."
        ),
        "TTL": GlossaryEntry(
            term: "TTL",
            definition: "Time To Live - how many network hops a packet can make before being discarded.",
            example: "Like a countdown timer on a package: 'deliver within 64 stops or destroy'.",
            whyItMatters: "Prevents lost packets from circling the internet forever."
        ),
        "NAT": GlossaryEntry(
            term: "NAT",
            definition: "Network Address Translation - lets multiple devices share one public IP address.",
            example: "Like an apartment building with one street address but many units inside.",
            whyItMatters: "Double NAT (CGNAT) can break some apps and reduce connection quality."
        ),
        "Firewall": GlossaryEntry(
            term: "Firewall",
            definition: "Security system that monitors and controls incoming and outgoing network traffic.",
            example: "Like a security guard at a building entrance, checking who can come in and go out.",
            whyItMatters: "Blocks malicious traffic but can also accidentally block legitimate connections."
        ),
        "Proxy": GlossaryEntry(
            term: "Proxy",
            definition: "An intermediary server that forwards your internet requests on your behalf.",
            example: "Like having someone else make a phone call for you so the other person doesn't know your number.",
            whyItMatters: "Can improve privacy but may slow down your connection."
        ),
        "Port": GlossaryEntry(
            term: "Port",
            definition: "A numbered endpoint for network communication. Different services use different ports.",
            example: "Like different doors in a building - door 80 is for web traffic, door 443 for secure web.",
            whyItMatters: "Blocked ports can prevent apps from working. Open ports can be security risks."
        ),
        "Protocol": GlossaryEntry(
            term: "Protocol",
            definition: "A set of rules that defines how data is transmitted between devices.",
            example: "Like the rules of a language - both sides need to speak the same one to communicate.",
            whyItMatters: "Different protocols have different speed, security, and reliability trade-offs."
        )
    ]

    static func lookup(_ term: String) -> GlossaryEntry? {
        entries[term] ?? entries.first(where: { $0.key.lowercased() == term.lowercased() })?.value
    }
}

// MARK: - Tooltip Button

struct TooltipButton: View {
    let term: String
    @State private var showingTooltip = false

    var body: some View {
        Button(action: { showingTooltip = true }) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundColor(.blue.opacity(0.7))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingTooltip) {
            if let entry = NetworkGlossary.lookup(term) {
                TooltipSheet(entry: entry)
            }
        }
    }
}

// MARK: - Tooltip Text (inline label + info button)

struct TooltipText: View {
    let text: String
    let term: String
    var font: Font = .subheadline

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(font)
            TooltipButton(term: term)
        }
    }
}

// MARK: - Tooltip Sheet

private struct TooltipSheet: View {
    let entry: GlossaryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Term header
                    Text(entry.term)
                        .font(.largeTitle.bold())
                        .padding(.top)

                    // Definition
                    tooltipSection(
                        icon: "book.fill",
                        title: "What is it?",
                        content: entry.definition,
                        color: .blue
                    )

                    // Example
                    tooltipSection(
                        icon: "lightbulb.fill",
                        title: "Think of it like...",
                        content: entry.example,
                        color: .yellow
                    )

                    // Why it matters
                    tooltipSection(
                        icon: "exclamationmark.triangle.fill",
                        title: "Why it matters",
                        content: entry.whyItMatters,
                        color: .orange
                    )

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func tooltipSection(icon: String, title: String, content: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
