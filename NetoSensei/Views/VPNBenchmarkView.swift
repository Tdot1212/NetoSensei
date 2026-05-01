//
//  VPNBenchmarkView.swift
//  NetoSensei
//
//  VPN Reality Check - Manual VPN benchmarking with REAL data
//

import SwiftUI

struct VPNBenchmarkView: View {
    @ObservedObject private var benchmarkEngine = VPNBenchmarkEngine.shared
    @ObservedObject private var profileStore = VPNProfileStore.shared
    @Environment(\.dismiss) var dismiss

    @State private var protocolMode: String = "WireGuard"
    @State private var userNotes: String = ""
    @State private var showingResults = false
    @State private var currentProfile: VPNProfile?
    @State private var showingBaseline = false

    let commonProtocols = ["WireGuard", "Stealth", "OpenVPN", "IKEv2", "Shadowsocks", "Trojan", "VLESS", "XProtocol", "WebSocket", "gRPC"]

    var body: some View {
        NavigationView {
            ZStack {
                if benchmarkEngine.isBenchmarking {
                    progressView
                } else if let profile = currentProfile, showingResults {
                    resultsView(profile: profile)
                } else {
                    startView
                }
            }
            .navigationTitle("VPN Reality Check")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if currentProfile != nil && showingResults {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            if let profile = currentProfile {
                                profileStore.saveProfile(profile)
                                dismiss()
                            }
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Start View

    private var startView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.system(size: 60))
                        .foregroundStyle(.purple.gradient)

                    Text("VPN Reality Check")
                        .font(.title.bold())

                    Text("Manual VPN benchmarking with 100% REAL data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)

                // VPN Status
                vpnStatusCard

                // Protocol/Mode Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("VPN Protocol / Mode")
                        .font(.headline)

                    Picker("Protocol", selection: $protocolMode) {
                        ForEach(commonProtocols, id: \.self) { protocolName in
                            Text(protocolName).tag(protocolName)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)

                // Instructions
                instructionsCard

                // Action Buttons
                VStack(spacing: 16) {
                    if !benchmarkEngine.isVPNActive {
                        // Measure WiFi Baseline
                        Button(action: runWiFiBaseline) {
                            HStack {
                                Image(systemName: "wifi")
                                Text("Measure WiFi Baseline (No VPN)")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    } else {
                        // Run VPN Benchmark
                        Button(action: runVPNBenchmark) {
                            HStack {
                                Image(systemName: "bolt.shield.fill")
                                Text("Run VPN Benchmark")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)

                // WiFi Baseline Display
                if let baseline = profileStore.wifiBaseline {
                    baselineCard(baseline: baseline)
                }

                // Recent Profiles
                if !profileStore.profiles.isEmpty {
                    recentProfilesSection
                }
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - VPN Status Card

    private var vpnStatusCard: some View {
        HStack {
            Image(systemName: benchmarkEngine.isVPNActive ? "checkmark.shield.fill" : "xmark.shield.fill")
                .font(.title2)
                .foregroundColor(benchmarkEngine.isVPNActive ? .green : .red)

            VStack(alignment: .leading) {
                Text("VPN Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(benchmarkEngine.isVPNActive ? "VPN ON" : "VPN OFF")
                    .font(.headline)
                    .foregroundColor(benchmarkEngine.isVPNActive ? .green : .red)
            }

            Spacer()

            if !benchmarkEngine.isVPNActive {
                Text("Turn VPN ON to benchmark")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Instructions Card

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("How It Works")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Turn VPN OFF → Measure WiFi baseline")
                instructionRow(number: "2", text: "Turn VPN ON → Choose region & protocol")
                instructionRow(number: "3", text: "Run benchmark → Get REAL measurements")
                instructionRow(number: "4", text: "Repeat for different regions/protocols")
                instructionRow(number: "5", text: "NetoSensei ranks them automatically")
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.bold().monospaced())
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.purple)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Baseline Card

    private func baselineCard(baseline: WiFiBaselineProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(.blue)
                Text("WiFi Baseline (No VPN)")
                    .font(.headline)

                Spacer()

                Text(baseline.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(baseline.displaySummary)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Recent Profiles

    private var recentProfilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Benchmarks")
                .font(.headline)
                .padding(.horizontal)

            ForEach(profileStore.profiles.prefix(3)) { profile in
                profileRow(profile: profile)
            }

            NavigationLink(destination: VPNProfileListView()) {
                HStack {
                    Text("View All (\(profileStore.profiles.count))")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .foregroundColor(.purple)
                .padding()
            }
        }
    }

    private func profileRow(profile: VPNProfile) -> some View {
        HStack {
            Text(profile.connectionQuality.emoji)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.subheadline.bold())
                Text(profile.performanceSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(profile.scoreText)
                .font(.headline)
                .foregroundColor(Color(profile.scoreColor))
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 70))
                .foregroundStyle(.purple.gradient)
                .symbolEffect(.pulse)

            VStack(spacing: 12) {
                Text("Benchmarking VPN")
                    .font(.title2.bold())

                Text(benchmarkEngine.currentTask)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                ProgressView(value: benchmarkEngine.progress)
                    .tint(.purple)
                    .scaleEffect(x: 1, y: 2, anchor: .center)

                Text("\(Int(benchmarkEngine.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    // MARK: - Results View

    private func resultsView(profile: VPNProfile) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Score Summary
                scoreSummaryCard(profile: profile)

                // Performance Details
                performanceDetailsCard(profile: profile)

                // Streaming Quality
                streamingQualityCard(profile: profile)

                // Comparison with Baseline
                if let comparison = profileStore.compareWithBaseline(profile) {
                    comparisonCard(comparison: comparison)
                }

                // Save Button
                Button(action: {
                    profileStore.saveProfile(profile)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Profile")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
    }

    private func scoreSummaryCard(profile: VPNProfile) -> some View {
        VStack(spacing: 16) {
            Text(profile.scoreText)
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(Color(profile.scoreColor))

            Text(profile.displayName)
                .font(.title2.bold())

            HStack(spacing: 16) {
                Label("\(Int(profile.latency))ms", systemImage: "timer")
                Label(String(format: "%.1f Mbps", profile.downloadSpeed), systemImage: "speedometer")
                Label(String(format: "%.1f%%", profile.packetLoss), systemImage: "exclamationmark.triangle")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.purple.opacity(0.1), Color.blue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func performanceDetailsCard(profile: VPNProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Details")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricBox(label: "Latency", value: "\(Int(profile.latency))ms")
                metricBox(label: "Jitter", value: String(format: "%.1fms", profile.jitter))
                metricBox(label: "Download", value: String(format: "%.1f Mbps", profile.downloadSpeed))
                metricBox(label: "Upload", value: String(format: "%.1f Mbps", profile.uploadSpeed))
                metricBox(label: "Packet Loss", value: String(format: "%.1f%%", profile.packetLoss))
                metricBox(label: "Quality", value: profile.connectionQuality.rawValue)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func metricBox(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(.purple)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(8)
    }

    private func streamingQualityCard(profile: VPNProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Streaming Quality")
                .font(.headline)

            Text(profile.streamingText)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func comparisonCard(comparison: VPNComparison) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WiFi vs VPN Comparison")
                .font(.headline)

            Text(comparison.diagnosis)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text("Recommendation:")
                .font(.caption.bold())

            Text(comparison.recommendation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Actions

    private func runVPNBenchmark() {
        Task {
            let profile = await benchmarkEngine.runManualBenchmark(
                protocolMode: protocolMode,
                userNotes: userNotes.isEmpty ? nil : userNotes
            )

            await MainActor.run {
                currentProfile = profile
                showingResults = true
            }
        }
    }

    private func runWiFiBaseline() {
        Task {
            let baseline = await benchmarkEngine.runWiFiBaselineBenchmark()

            await MainActor.run {
                if let baseline = baseline {
                    profileStore.saveBaseline(baseline)
                }
            }
        }
    }
}

// MARK: - VPN Profile List View

struct VPNProfileListView: View {
    @ObservedObject private var profileStore = VPNProfileStore.shared
    @State private var selectedProfile: VPNProfile?
    @State private var showingDetail = false

    var body: some View {
        List {
            // WiFi Baseline Section
            if let baseline = profileStore.wifiBaseline {
                Section(header: Text("WiFi Baseline (No VPN)")) {
                    baselineRow(baseline: baseline)
                }
            }

            // Top VPN Recommendations
            if !profileStore.rankedProfiles.isEmpty {
                Section(header: Text("🏆 Top VPN Servers")) {
                    ForEach(Array(profileStore.rankedProfiles.prefix(3).enumerated()), id: \.element.id) { index, profile in
                        profileDetailRow(profile: profile, rank: index + 1)
                            .onTapGesture {
                                selectedProfile = profile
                                showingDetail = true
                            }
                    }
                }
            }

            // All VPN Profiles
            if profileStore.rankedProfiles.count > 3 {
                Section(header: Text("All VPN Benchmarks (\(profileStore.rankedProfiles.count))")) {
                    ForEach(profileStore.rankedProfiles.dropFirst(3)) { profile in
                        profileDetailRow(profile: profile)
                            .onTapGesture {
                                selectedProfile = profile
                                showingDetail = true
                            }
                    }
                    .onDelete(perform: deleteProfiles)
                }
            }

            // By Region
            if profileStore.profilesByRegion().count > 1 {
                Section(header: Text("By Region")) {
                    ForEach(Array(profileStore.profilesByRegion().keys.sorted()), id: \.self) { region in
                        if let best = profileStore.bestProfileForRegion(region) {
                            regionRow(region: region, profile: best)
                        }
                    }
                }
            }

            // By Protocol
            if profileStore.profilesByProtocol().count > 1 {
                Section(header: Text("By Protocol")) {
                    ForEach(Array(profileStore.profilesByProtocol().keys.sorted()), id: \.self) { protocolName in
                        if let profiles = profileStore.profilesByProtocol()[protocolName],
                           let best = profiles.max(by: { $0.overallScore < $1.overallScore }) {
                            protocolRow(protocolName: protocolName, profile: best, count: profiles.count)
                        }
                    }
                }
            }

            // Clear All
            Section {
                Button(role: .destructive, action: {
                    profileStore.clearAllProfiles()
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Clear All Benchmarks")
                    }
                }
            }
        }
        .navigationTitle("VPN Profiles (\(profileStore.profiles.count))")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingDetail) {
            if let profile = selectedProfile {
                profileDetailSheet(profile: profile)
            }
        }
    }

    private func baselineRow(baseline: WiFiBaselineProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(.blue)
                Text("WiFi Baseline")
                    .font(.headline)
                Spacer()
                Text(baseline.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 16) {
                metricPill(label: "Latency", value: "\(Int(baseline.latency))ms")
                metricPill(label: "Speed", value: String(format: "%.1f Mbps", baseline.downloadSpeed))
                metricPill(label: "Loss", value: String(format: "%.1f%%", baseline.packetLoss))
            }
        }
        .padding(.vertical, 4)
    }

    private func profileDetailRow(profile: VPNProfile, rank: Int? = nil) -> some View {
        HStack(spacing: 12) {
            // Rank badge
            if let rank = rank {
                ZStack {
                    Circle()
                        .fill(rankColor(rank: rank))
                        .frame(width: 32, height: 32)
                    Text("\(rank)")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                }
            } else {
                Text(profile.connectionQuality.emoji)
                    .font(.title2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.subheadline.bold())

                HStack(spacing: 8) {
                    Text("\(Int(profile.latency))ms")
                        .font(.caption2)
                    Text("•")
                    Text(String(format: "%.1f Mbps", profile.downloadSpeed))
                        .font(.caption2)
                    Text("•")
                    Text(profile.streamingText)
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(profile.scoreText)
                    .font(.headline)
                    .foregroundColor(Color(profile.scoreColor))

                if let comparison = profileStore.compareWithBaseline(profile) {
                    Text("-\(Int(comparison.speedDecreasePercentage))% speed")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func regionRow(region: String, profile: VPNProfile) -> some View {
        HStack {
            Text(region)
                .font(.subheadline)

            Spacer()

            Text(profile.scoreText)
                .font(.subheadline.bold())
                .foregroundColor(Color(profile.scoreColor))

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func protocolRow(protocolName: String, profile: VPNProfile, count: Int) -> some View {
        HStack {
            Text(protocolName)
                .font(.subheadline)

            Text("(\(count) tested)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(profile.scoreText)
                .font(.subheadline.bold())
                .foregroundColor(Color(profile.scoreColor))

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(8)
    }

    private func rankColor(rank: Int) -> Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return Color.brown
        default: return .blue
        }
    }

    private func deleteProfiles(at offsets: IndexSet) {
        let profilesToDelete = offsets.map { profileStore.rankedProfiles.dropFirst(3)[$0] }
        for profile in profilesToDelete {
            profileStore.deleteProfile(profile)
        }
    }

    @ViewBuilder
    private func profileDetailSheet(profile: VPNProfile) -> some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Score
                    VStack(spacing: 8) {
                        Text(profile.scoreText)
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(Color(profile.scoreColor))

                        Text(profile.displayName)
                            .font(.title3.bold())

                        Text(profile.timestamp, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()

                    // Performance Metrics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Performance Metrics")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            detailMetricBox(label: "Latency", value: "\(Int(profile.latency))ms")
                            detailMetricBox(label: "Jitter", value: String(format: "%.1fms", profile.jitter))
                            detailMetricBox(label: "Download", value: String(format: "%.1f Mbps", profile.downloadSpeed))
                            detailMetricBox(label: "Upload", value: String(format: "%.1f Mbps", profile.uploadSpeed))
                            detailMetricBox(label: "Packet Loss", value: String(format: "%.1f%%", profile.packetLoss))
                            detailMetricBox(label: "Quality", value: profile.connectionQuality.rawValue)
                        }
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Streaming Quality
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Streaming Quality")
                            .font(.headline)
                        Text(profile.streamingText)
                            .font(.title3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // WiFi Comparison
                    if let comparison = profileStore.compareWithBaseline(profile) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WiFi vs VPN")
                                .font(.headline)

                            Text(comparison.diagnosis)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Recommendation")
                                    .font(.caption.bold())
                                Text(comparison.recommendation)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Notes
                    if let notes = profile.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                            Text(notes)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationTitle("VPN Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showingDetail = false
                    }
                }
            }
        }
    }

    private func detailMetricBox(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(.purple)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(8)
    }
}

#Preview {
    VPNBenchmarkView()
}
