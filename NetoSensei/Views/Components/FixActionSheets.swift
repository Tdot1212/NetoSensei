//
//  FixActionSheets.swift
//  NetoSensei
//
//  Auto-fix action sheets and instruction guides
//

import SwiftUI

// MARK: - Router Restart Guide

struct RouterRestartGuideSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Icon
                    HStack {
                        Spacer()
                        Image(systemName: "wifi.router")
                            .font(.system(size: 80))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    // Title
                    Text("How to Restart Your Router")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Steps
                    InstructionStep(
                        number: 1,
                        title: "Unplug the Power",
                        description: "Disconnect the power cable from your router. Wait 10 seconds."
                    )

                    InstructionStep(
                        number: 2,
                        title: "Plug It Back In",
                        description: "Reconnect the power cable. Wait 1-2 minutes for router to fully boot."
                    )

                    InstructionStep(
                        number: 3,
                        title: "Check WiFi Connection",
                        description: "Make sure your device reconnects to WiFi automatically."
                    )

                    InstructionStep(
                        number: 4,
                        title: "Run Diagnostic Again",
                        description: "Return to NetoSensei and run the diagnostic to verify the fix."
                    )

                    // Warning
                    CardView {
                        HStack(alignment: .top, spacing: UIConstants.spacingM) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                Text("Tip")
                                    .font(.subheadline.bold())

                                Text("Restarting your router clears temporary congestion and resets connections. Do this monthly for best performance.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Restart Router")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - WiFi Optimization Tips

struct WiFiOptimizationSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Icon
                    HStack {
                        Spacer()
                        Image(systemName: "wifi")
                            .font(.system(size: 80))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    Text("WiFi Optimization Tips")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // FIXED: Focus on actionable router/network tips, not WiFi signal
                    WiFiTipCard(
                        icon: "arrow.clockwise",
                        title: "Restart Your Router",
                        description: "A router restart often fixes latency issues. Unplug for 30 seconds, then reconnect."
                    )

                    WiFiTipCard(
                        icon: "desktopcomputer",
                        title: "Disconnect Unused Devices",
                        description: "Too many connected devices can overload your router. Disconnect devices you're not using."
                    )

                    WiFiTipCard(
                        icon: "5.circle.fill",
                        title: "Try 5GHz Band",
                        description: "If available, connect to 5GHz WiFi (faster, less congested). 2.4GHz has better range but slower."
                    )

                    WiFiTipCard(
                        icon: "square.grid.2x2",
                        title: "Change WiFi Channel",
                        description: "Your router may be on a crowded channel. Login to router settings and try channels 1, 6, or 11."
                    )

                    WiFiTipCard(
                        icon: "arrow.down.doc",
                        title: "Check for Background Downloads",
                        description: "Other apps/devices downloading can slow your connection. Pause large downloads."
                    )

                    Button("Got It!") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("WiFi Tips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - DNS Change Instructions

struct DNSChangeSheet: View {
    let recommendedDNS: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Icon
                    HStack {
                        Spacer()
                        Image(systemName: "network")
                            .font(.system(size: 80))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    Text("Change DNS Servers")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Recommended DNS
                    CardView {
                        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                            Text("Recommended DNS")
                                .font(.headline)

                            HStack {
                                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                    if recommendedDNS.contains("1.1.1.1") {
                                        Text("Cloudflare DNS")
                                            .font(.subheadline.bold())
                                        Text("1.1.1.1")
                                            .font(.body.monospaced())
                                            .foregroundColor(AppColors.accent)
                                        Text("1.0.0.1")
                                            .font(.body.monospaced())
                                            .foregroundColor(AppColors.textSecondary)
                                    } else {
                                        Text("Google DNS")
                                            .font(.subheadline.bold())
                                        Text("8.8.8.8")
                                            .font(.body.monospaced())
                                            .foregroundColor(AppColors.accent)
                                        Text("8.8.4.4")
                                            .font(.body.monospaced())
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title)
                                    .foregroundColor(AppColors.green)
                            }
                        }
                    }

                    // Instructions
                    InstructionStep(
                        number: 1,
                        title: "Open Settings",
                        description: "Go to Settings → Wi-Fi"
                    )

                    InstructionStep(
                        number: 2,
                        title: "Select Your WiFi",
                        description: "Tap the (i) icon next to your connected WiFi network"
                    )

                    InstructionStep(
                        number: 3,
                        title: "Configure DNS",
                        description: "Scroll down → Tap 'Configure DNS' → Select 'Manual'"
                    )

                    InstructionStep(
                        number: 4,
                        title: "Add DNS Servers",
                        description: recommendedDNS.contains("1.1.1.1") ?
                            "Remove existing servers, add: 1.1.1.1 and 1.0.0.1" :
                            "Remove existing servers, add: 8.8.8.8 and 8.8.4.4"
                    )

                    InstructionStep(
                        number: 5,
                        title: "Save & Test",
                        description: "Tap Save, then run NetoSensei diagnostic again"
                    )

                    // Quick Action Button
                    Button(action: {
                        openWiFiSettings()
                    }) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                            Text("Open WiFi Settings")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("I'll Do It Later") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Change DNS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func openWiFiSettings() {
        if let url = URL(string: "App-prefs:root=WIFI") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - VPN Setup Guide

struct VPNSetupGuideSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Icon
                    HStack {
                        Spacer()
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 80))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    Text("Turn On Your VPN")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Text("If you have a VPN app installed, turning it on may help with the detected network issue.")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // What VPN Can Help With
                    CardView {
                        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text("What VPN Can Help With")
                                    .font(.subheadline.bold())
                            }

                            VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(AppColors.accent)
                                    Text("Bypassing ISP congestion or slow routing")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(AppColors.accent)
                                    Text("Accessing content from different regions")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .foregroundColor(AppColors.accent)
                                    Text("Improving privacy and security")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                    }

                    // Steps
                    InstructionStep(
                        number: 1,
                        title: "Open Your VPN App",
                        description: "Launch your VPN app (e.g., Shadowsocks, V2Ray, Clash, Surge, or any VPN client)"
                    )

                    InstructionStep(
                        number: 2,
                        title: "Connect to a Server",
                        description: "Choose a server location and connect. Closer servers usually have better speed."
                    )

                    InstructionStep(
                        number: 3,
                        title: "Run Diagnostic Again",
                        description: "Return to NetoSensei and run the diagnostic again to see if the VPN improved your connection."
                    )

                    // Tip
                    CardView {
                        HStack(alignment: .top, spacing: UIConstants.spacingM) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                Text("Tip")
                                    .font(.subheadline.bold())

                                Text("After connecting to VPN, run NetoSensei diagnostic again to compare results and see if your connection improved.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    Button("Got It") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("VPN Suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - ISP Contact Info

struct ISPContactSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Icon
                    HStack {
                        Spacer()
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    Text("Contact Your ISP")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // What to say
                    CardView {
                        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                            HStack {
                                Image(systemName: "quote.bubble.fill")
                                    .foregroundColor(AppColors.accent)
                                Text("What to Say")
                                    .font(.headline)
                            }

                            Text("\"I'm experiencing high internet latency (over 600ms). My router and WiFi are working fine, but external connectivity is very slow. Is there an outage or congestion in my area?\"")
                                .font(.body)
                                .italic()
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    // Info to have ready
                    Text("Have This Info Ready:")
                        .font(.headline)

                    InstructionStep(
                        number: 1,
                        title: "Account Number",
                        description: "Your ISP account or customer number"
                    )

                    InstructionStep(
                        number: 2,
                        title: "Service Address",
                        description: "The address where internet is installed"
                    )

                    InstructionStep(
                        number: 3,
                        title: "Problem Details",
                        description: "High latency, slow speeds, started today/recently"
                    )

                    // Common ISP numbers (US examples)
                    Text("Common ISP Phone Numbers:")
                        .font(.headline)
                        .padding(.top)

                    ISPContactCard(name: "Comcast/Xfinity", phone: "1-800-XFINITY")
                    ISPContactCard(name: "AT&T", phone: "1-800-288-2020")
                    ISPContactCard(name: "Verizon", phone: "1-800-VERIZON")
                    ISPContactCard(name: "Spectrum", phone: "1-855-243-8892")

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Contact ISP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - VPN Region Picker

struct VPNRegionPickerSheet: View {
    let recommendedRegion: String?
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var optimizer = VPNOptimizer.shared
    @State private var selectedRegion: VPNOptimizer.VPNRegion?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Header
                    HStack {
                        Spacer()
                        Image(systemName: "globe")
                            .font(.system(size: 60))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    Text("Choose VPN Region")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Optimization status
                    if optimizer.isOptimizing {
                        CardView {
                            HStack(spacing: UIConstants.spacingM) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                    Text("Testing Regions...")
                                        .font(.subheadline.bold())
                                    Text("This may take a minute")
                                        .font(.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }
                            }
                        }
                    }

                    // Test button
                    if !optimizer.isOptimizing && optimizer.regionResults.isEmpty {
                        Button(action: {
                            Task {
                                await optimizer.optimizeVPN(for: .general)
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Test All Regions")
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Results
                    if !optimizer.regionResults.isEmpty {
                        Text("Test Results")
                            .font(.headline)

                        ForEach(optimizer.regionResults) { result in
                            VPNRegionResultCard(result: result, isSelected: selectedRegion?.id == result.region.id) {
                                selectedRegion = result.region
                            }
                        }

                        // Action buttons
                        if let region = selectedRegion {
                            VStack(spacing: UIConstants.spacingM) {
                                // Guidance card instead of fake action
                                CardView {
                                    VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                                        HStack {
                                            Image(systemName: "hand.point.right.fill")
                                                .foregroundColor(AppColors.accent)
                                            Text("How to Apply")
                                                .font(.subheadline.bold())
                                        }

                                        Text("Open your VPN app and select:")
                                            .font(.caption)
                                            .foregroundColor(AppColors.textSecondary)

                                        HStack {
                                            Text(region.flagEmoji)
                                                .font(.title2)
                                            Text(region.displayName)
                                                .font(.headline)
                                                .foregroundColor(AppColors.accent)
                                        }
                                        .padding(.vertical, UIConstants.spacingS)
                                        .frame(maxWidth: .infinity)
                                        .background(Color(UIColor.tertiarySystemBackground))
                                        .cornerRadius(UIConstants.cornerRadiusS)
                                    }
                                }

                                Button(action: {
                                    // Haptic feedback
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()

                                    // Copy region name to clipboard for convenience
                                    UIPasteboard.general.string = region.displayName
                                    dismiss()
                                }) {
                                    HStack {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Region Name & Close")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        Button("Test Again") {
                            Task {
                                await optimizer.optimizeVPN(for: .general)
                            }
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }

                    // Info
                    CardView {
                        HStack(alignment: .top, spacing: UIConstants.spacingM) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                Text("Note")
                                    .font(.subheadline.bold())

                                Text("To change VPN regions, open your VPN app and select the region shown above. NetoSensei can test which regions are fastest for you.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("VPN Regions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            // Auto-start optimization if no results
            if optimizer.regionResults.isEmpty && !optimizer.isOptimizing {
                await optimizer.optimizeVPN(for: .general)
            }
        }
    }
}

struct VPNRegionResultCard: View {
    let result: VPNOptimizer.RegionTestResult
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CardView {
                HStack(spacing: UIConstants.spacingM) {
                    // Flag
                    Text(result.region.flagEmoji)
                        .font(.largeTitle)

                    VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                        // Name and quality
                        HStack {
                            Text(result.region.displayName)
                                .font(.subheadline.bold())
                                .foregroundColor(AppColors.textPrimary)

                            if result.isRecommended {
                                Text("BEST")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(AppColors.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }

                            Spacer()

                            Text(result.quality)
                                .font(.caption)
                                .foregroundColor(qualityColor(result.quality))
                        }

                        // Stats
                        HStack(spacing: UIConstants.spacingL) {
                            if let latency = result.latency {
                                StatBadge(icon: "timer", value: "\(Int(latency))ms", label: "Latency")
                            }
                            if let throughput = result.throughput {
                                StatBadge(icon: "speedometer", value: String(format: "%.1f", throughput), label: "Mbps")
                            }
                            if let loss = result.packetLoss, loss > 0 {
                                StatBadge(icon: "exclamationmark.triangle", value: String(format: "%.1f%%", loss), label: "Loss")
                            }
                        }
                    }

                    // Selection indicator
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(AppColors.accent)
                    } else {
                        Image(systemName: "circle")
                            .font(.title2)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func qualityColor(_ quality: String) -> Color {
        switch quality {
        case "Excellent": return AppColors.green
        case "Good": return Color.blue
        case "Fair": return Color.orange
        default: return AppColors.red
        }
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(value)
                .font(.caption.bold())
        }
        .foregroundColor(AppColors.textSecondary)
    }
}

// MARK: - Streaming Optimization Guide

struct StreamingOptimizationSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var optimizer = VPNOptimizer.shared
    @State private var recommendations: [VPNOptimizer.StreamingRecommendation] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Header
                    HStack {
                        Spacer()
                        Image(systemName: "play.tv.fill")
                            .font(.system(size: 60))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    Text("Optimize for Streaming")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Text("Choose the best VPN region for your favorite streaming platform")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Recommendations
                    if recommendations.isEmpty {
                        CardView {
                            HStack(spacing: UIConstants.spacingM) {
                                ProgressView()
                                Text("Analyzing best regions...")
                                    .font(.subheadline)
                            }
                        }
                    } else {
                        Text("VPN Recommendations")
                            .font(.headline)

                        ForEach(recommendations, id: \.platform) { rec in
                            StreamingRecommendationCard(recommendation: rec)
                        }
                    }

                    // Explanation
                    CardView {
                        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text("How This Works")
                                    .font(.subheadline.bold())
                            }

                            Text("Streaming services use CDN (Content Delivery Network) servers in specific locations. Connecting your VPN to a region near the CDN server reduces buffering and improves video quality.")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    // Tips
                    CardView {
                        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text("Streaming Tips")
                                    .font(.subheadline.bold())
                            }

                            VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                TipRow(text: "Use WireGuard protocol for fastest speeds")
                                TipRow(text: "Connect to recommended region before streaming")
                                TipRow(text: "Close other apps to maximize bandwidth")
                                TipRow(text: "Use 5GHz WiFi for better streaming")
                            }
                        }
                    }

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Streaming Optimizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            // Load recommendations
            recommendations = optimizer.getStreamingRecommendations()
        }
    }
}

struct StreamingRecommendationCard: View {
    let recommendation: VPNOptimizer.StreamingRecommendation

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                // Platform and region
                HStack {
                    Text(recommendation.platform)
                        .font(.headline)

                    Spacer()

                    Text(recommendation.vpnRegion.flagEmoji)
                        .font(.title2)
                }

                // Recommended region
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.green)
                        .font(.caption)

                    Text("Connect to: \(recommendation.vpnRegion.displayName)")
                        .font(.subheadline)
                        .foregroundColor(AppColors.accent)
                }

                // Stats
                HStack(spacing: UIConstants.spacingL) {
                    StatInfo(icon: "timer", value: "\(Int(recommendation.estimatedLatency))ms", label: "Est. Latency")
                    StatInfo(icon: "arrow.left.arrow.right", value: "\(Int(recommendation.distanceToCDN))km", label: "To CDN")
                }
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
            }
        }
    }
}

struct StatInfo: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption.bold())
                Text(label)
                    .font(.caption2)
            }
        }
    }
}

struct TipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundColor(AppColors.accent)
            Text(text)
                .font(.caption)
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - VPN Protocol Selector

struct VPNProtocolSelectorSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedProtocol: VPNOptimizer.VPNProtocol = .wireGuard

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: UIConstants.spacingL) {
                    // Header
                    HStack {
                        Spacer()
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.system(size: 60))
                            .foregroundColor(AppColors.accent)
                        Spacer()
                    }

                    Text("Choose VPN Protocol")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Text("Different protocols offer different speeds, security, and compatibility.")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    // Protocol options
                    ForEach(VPNOptimizer.VPNProtocol.allCases, id: \.self) { protocol_ in
                        VPNProtocolCard(
                            protocol_: protocol_,
                            isSelected: selectedProtocol == protocol_,
                            isRecommended: protocol_ == .wireGuard
                        ) {
                            selectedProtocol = protocol_
                        }
                    }

                    // Guidance card with selected protocol
                    CardView {
                        VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                            HStack {
                                Image(systemName: "hand.point.right.fill")
                                    .foregroundColor(AppColors.accent)
                                Text("How to Apply")
                                    .font(.subheadline.bold())
                            }

                            Text("Open your VPN app's settings and select:")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)

                            HStack {
                                Image(systemName: "network.badge.shield.half.filled")
                                    .foregroundColor(AppColors.accent)
                                Text(selectedProtocol.displayName)
                                    .font(.headline)
                                    .foregroundColor(AppColors.accent)
                            }
                            .padding(.vertical, UIConstants.spacingS)
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.tertiarySystemBackground))
                            .cornerRadius(UIConstants.cornerRadiusS)

                            Text("Look for 'Protocol', 'Connection Type', or 'Advanced Settings' in your VPN app.")
                                .font(.caption)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    // Action button with haptic feedback
                    Button(action: {
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()

                        // Copy protocol name for convenience
                        UIPasteboard.general.string = selectedProtocol.displayName
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Protocol Name & Close")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    // Info
                    CardView {
                        HStack(alignment: .top, spacing: UIConstants.spacingM) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                                Text("Why Manual?")
                                    .font(.subheadline.bold())

                                Text("iOS security prevents apps from changing other apps' VPN settings. This protects your privacy by ensuring only you control your VPN configuration.")
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("VPN Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct VPNProtocolCard: View {
    let protocol_: VPNOptimizer.VPNProtocol
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CardView {
                VStack(alignment: .leading, spacing: UIConstants.spacingM) {
                    // Header
                    HStack {
                        Text(protocol_.displayName)
                            .font(.headline)
                            .foregroundColor(AppColors.textPrimary)

                        if isRecommended {
                            Text("RECOMMENDED")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(AppColors.accent)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(AppColors.accent)
                        } else {
                            Image(systemName: "circle")
                                .font(.title3)
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }

                    // Description
                    Text(protocol_.description)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)

                    Divider()

                    // Pros
                    VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                        Text("Pros:")
                            .font(.caption.bold())
                            .foregroundColor(AppColors.green)

                        ForEach(protocol_.pros, id: \.self) { pro in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(AppColors.green)
                                Text(pro)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    // Cons
                    VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                        Text("Cons:")
                            .font(.caption.bold())
                            .foregroundColor(Color.orange)

                        ForEach(protocol_.cons, id: \.self) { con in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(Color.orange)
                                Text(con)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    // Recommended for
                    VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                        Text("Best for:")
                            .font(.caption.bold())
                            .foregroundColor(.blue)

                        ForEach(protocol_.recommendedFor, id: \.self) { use in
                            HStack(alignment: .top, spacing: 6) {
                                Text("•")
                                    .foregroundColor(.blue)
                                Text(use)
                                    .font(.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Components

struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.spacingM) {
            ZStack {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 32, height: 32)

                Text("\(number)")
                    .font(.headline.bold())
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                Text(title)
                    .font(.subheadline.bold())

                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WiFiTipCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        CardView {
            HStack(alignment: .top, spacing: UIConstants.spacingM) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(AppColors.accent)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: UIConstants.spacingS) {
                    Text(title)
                        .font(.subheadline.bold())

                    Text(description)
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}


struct ISPContactCard: View {
    let name: String
    let phone: String

    var body: some View {
        CardView {
            HStack {
                Text(name)
                    .font(.subheadline.bold())

                Spacer()

                Button(action: {
                    if let url = URL(string: "tel://\(phone.replacingOccurrences(of: "-", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text(phone)
                    }
                    .font(.caption)
                    .foregroundColor(AppColors.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Previews

#Preview("Router Restart") {
    RouterRestartGuideSheet()
}

#Preview("WiFi Tips") {
    WiFiOptimizationSheet()
}

#Preview("DNS Change") {
    DNSChangeSheet(recommendedDNS: "1.1.1.1")
}

#Preview("VPN Guide") {
    VPNSetupGuideSheet()
}

#Preview("ISP Contact") {
    ISPContactSheet()
}

#Preview("VPN Region Picker") {
    VPNRegionPickerSheet(recommendedRegion: "US East")
}

#Preview("VPN Protocol Selector") {
    VPNProtocolSelectorSheet()
}

#Preview("Streaming Optimizer") {
    StreamingOptimizationSheet()
}
