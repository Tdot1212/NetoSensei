//
//  ProblemSolutions.swift
//  NetoSensei
//
//  Actionable solutions for common network problems
//

import SwiftUI

// MARK: - Problem Solution

struct ProblemSolution: Identifiable {
    let id = UUID()
    let problem: String
    let icon: String
    let severity: Severity
    let explanation: String
    let steps: [String]
    let proTip: String?

    enum Severity {
        case info
        case warning
        case critical

        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .yellow
            case .critical: return .red
            }
        }
    }
}

// MARK: - Solution Engine

struct SolutionEngine {
    @MainActor static func solutions(for status: NetworkStatus) -> [ProblemSolution] {
        var results: [ProblemSolution] = []
        // FIXED: Use SmartVPNDetector as single source of truth for VPN status
        let vpnActive = SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false

        // DNS issues
        // FIX (Issue 3): only act on REAL latency values. 999 sentinel values from
        // probe timeouts must not produce "Slow DNS" cards.
        if let dnsLatency = status.dns.displayableLatency, dnsLatency > 150 {
            results.append(ProblemSolution(
                problem: "Slow DNS",
                icon: "server.rack",
                severity: dnsLatency > 300 ? .critical : .warning,
                explanation: "Your DNS server is responding slowly (\(Int(dnsLatency))ms). This delays every website you visit.",
                steps: [
                    "Open Settings > Wi-Fi > tap your network > Configure DNS",
                    "Change to Manual and add: 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google)",
                    "If using VPN, enable 'Use VPN DNS' in your VPN app"
                ],
                proTip: "Cloudflare (1.1.1.1) is often the fastest. Google (8.8.8.8) is the most reliable."
            ))
        }

        // FIX (Issue 3/6): only declare DNS Resolution Failed after MULTIPLE
        // consecutive failures with no recent success. A single timed-out probe
        // used to trigger this card while the user was clearly browsing fine.
        if MeasurementValidityTracker.shared.dnsHasHardFailure {
            results.append(ProblemSolution(
                problem: "DNS Resolution Failed",
                icon: "xmark.icloud",
                severity: .critical,
                explanation: "Your device cannot resolve domain names. Websites won't load.",
                steps: [
                    "Try switching to a different DNS: Settings > Wi-Fi > Configure DNS",
                    "Set DNS to 1.1.1.1 or 8.8.8.8",
                    "If on VPN, try disconnecting and reconnecting",
                    "Restart your router if the problem persists"
                ],
                proTip: nil
            ))
        }

        // High latency
        if let internetLatency = status.internet.latencyToExternal, internetLatency > 200 {
            let vpnActive = vpnActive
            if vpnActive {
                results.append(ProblemSolution(
                    problem: "High Latency (VPN)",
                    icon: "clock.arrow.2.circlepath",
                    severity: .info,
                    explanation: "Your latency is \(Int(internetLatency))ms. This is partly caused by VPN routing, which adds ~\(Int(internetLatency * 0.4))ms to protect your privacy.",
                    steps: [
                        "This is normal for VPN connections",
                        "Try a VPN server geographically closer to you",
                        "Switch to WireGuard protocol if available (fastest VPN protocol)"
                    ],
                    proTip: "VPN latency is the price of privacy. A server in your country typically adds 20-50ms."
                ))
            } else {
                results.append(ProblemSolution(
                    problem: "High Latency",
                    icon: "clock.arrow.2.circlepath",
                    severity: internetLatency > 500 ? .critical : .warning,
                    explanation: "Your connection has \(Int(internetLatency))ms latency. This causes lag in video calls and slow browsing.",
                    steps: [
                        "Move closer to your WiFi router",
                        "Reduce the number of connected devices",
                        "Restart your router",
                        "Check if other devices are downloading large files",
                        "Contact your ISP if the problem persists"
                    ],
                    proTip: "Under 50ms is excellent, 50-100ms is good, over 200ms causes noticeable lag."
                ))
            }
        }

        // Router issues
        // FIX (Issue 2/6): only declare "Router Unreachable" when there's been NO
        // successful gateway measurement recently AND multiple consecutive failures.
        // A working 51ms latency reading is proof the router is reachable — don't
        // call it unreachable just because one isReachable flag is stale.
        if MeasurementValidityTracker.shared.gatewayHasHardFailure && !vpnActive {
            results.append(ProblemSolution(
                problem: "Router Unreachable",
                icon: "wifi.exclamationmark",
                severity: .critical,
                explanation: "Your device can't reach the router. This usually means a WiFi problem.",
                steps: [
                    "Toggle WiFi off and on in Settings",
                    "Move closer to your router",
                    "Restart your router (unplug for 30 seconds)",
                    "Forget and rejoin the WiFi network"
                ],
                proTip: nil
            ))
        }

        if let routerLatency = status.router.displayableLatency, routerLatency > 30, !vpnActive {
            results.append(ProblemSolution(
                problem: "Slow Local Network",
                icon: "antenna.radiowaves.left.and.right",
                severity: routerLatency > 50 ? .warning : .info,
                explanation: "Router response time is \(Int(routerLatency))ms. Under 10ms is ideal.",
                steps: [
                    "Move closer to your router to improve signal",
                    "Switch to 5GHz band if available (faster but shorter range)",
                    "Check for interference: microwaves, Bluetooth devices, other routers",
                    "Reduce the number of devices on the network"
                ],
                proTip: "5GHz WiFi is faster but doesn't go through walls as well as 2.4GHz."
            ))
        }

        // Packet loss
        if let loss = status.router.packetLoss, loss > 2 {
            results.append(ProblemSolution(
                problem: "Packet Loss Detected",
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                severity: loss > 5 ? .critical : .warning,
                explanation: "\(String(format: "%.1f", loss))% of data packets are being lost. This causes buffering and freezing.",
                steps: [
                    "Restart your router",
                    "Check WiFi signal strength - move closer to router",
                    "Reduce network congestion - disconnect unused devices",
                    "Check for faulty Ethernet cables if using wired connection",
                    "Contact ISP if loss persists on wired connection"
                ],
                proTip: "Under 1% packet loss is normal. Over 5% severely impacts video calls and streaming."
            ))
        }

        // Internet down
        if !status.internet.isReachable {
            results.append(ProblemSolution(
                problem: "No Internet Connection",
                icon: "globe",
                severity: .critical,
                explanation: "Your device cannot reach the internet.",
                steps: [
                    "Check if other devices can connect",
                    "Restart your router and modem",
                    "If on VPN, try disconnecting the VPN",
                    "Check if your ISP has an outage (use cellular data to check)",
                    "Reset network settings: Settings > General > Reset > Reset Network Settings"
                ],
                proTip: nil
            ))
        }

        // VPN overhead
        if vpnActive,
           let tunnelLatency = status.vpn.tunnelLatency, tunnelLatency > 100 {
            results.append(ProblemSolution(
                problem: "VPN Overhead",
                icon: "lock.shield",
                severity: .info,
                explanation: "Your VPN adds ~\(Int(tunnelLatency))ms latency. This is the cost of encrypting your traffic.",
                steps: [
                    "This is expected behavior - your privacy is being protected",
                    "For lower latency, connect to a server closer to you",
                    "Switch to WireGuard protocol if your VPN app supports it",
                    "Only use VPN when needed on trusted networks"
                ],
                proTip: "WireGuard typically adds 5-20ms overhead vs 30-100ms for OpenVPN."
            ))
        }

        // VPN DNS leak
        if vpnActive && status.vpn.dnsLeakDetected {
            results.append(ProblemSolution(
                problem: "VPN DNS Leak",
                icon: "eye.trianglebadge.exclamationmark",
                severity: .critical,
                explanation: "Your DNS queries are leaking outside the VPN tunnel. Websites you visit may be visible to your ISP.",
                steps: [
                    "Enable 'Kill Switch' or 'DNS Leak Protection' in your VPN app",
                    "Manually set DNS to your VPN provider's DNS servers",
                    "As a fallback, use 1.1.1.1 or 9.9.9.9 (Quad9) as DNS"
                ],
                proTip: "A DNS leak means your ISP can see which websites you visit, even with VPN active."
            ))
        }

        // Hotspot connection
        if status.isHotspot {
            results.append(ProblemSolution(
                problem: "Mobile Hotspot Detected",
                icon: "personalhotspot",
                severity: .info,
                explanation: "You're connected via a mobile hotspot. Performance depends on cellular signal.",
                steps: [
                    "Hotspot connections are typically slower than dedicated WiFi",
                    "Monitor your mobile data usage",
                    "Connect to a regular WiFi network when available"
                ],
                proTip: "Hotspot connections share your phone's cellular data and can drain battery quickly."
            ))
        }

        return results
    }
}

// MARK: - Problem Solutions Card

struct ProblemSolutionsCard: View {
    let solutions: [ProblemSolution]
    @State private var expandedSolution: UUID?

    var body: some View {
        if !solutions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.orange)
                    Text("Issues & Solutions")
                        .font(.headline)
                }
                .padding(.leading, 4)

                VStack(spacing: 8) {
                    ForEach(solutions) { solution in
                        solutionRow(solution)
                    }
                }
            }
        }
    }

    private func solutionRow(_ solution: ProblemSolution) -> some View {
        let isExpanded = expandedSolution == solution.id

        return VStack(spacing: 0) {
            // Header (always visible)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedSolution = isExpanded ? nil : solution.id
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: solution.icon)
                        .foregroundColor(solution.severity.color)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(solution.problem)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        Text(solution.explanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            // Expanded steps
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    Text("How to fix:")
                        .font(.caption.bold())
                        .padding(.horizontal)
                        .padding(.top, 4)

                    ForEach(solution.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.caption.bold())
                                .foregroundColor(solution.severity.color)
                                .frame(width: 20, alignment: .trailing)
                            Text(solution.steps[index])
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    if let tip = solution.proTip {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                            Text(tip)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .padding(.horizontal)
                        .padding(.top, 4)
                    }
                }
                .padding(.bottom)
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}
