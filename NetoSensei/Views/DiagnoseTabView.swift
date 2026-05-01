//
//  DiagnoseTabView.swift
//  NetoSensei
//
//  Diagnose tab with Quick Check and Deep Scan
//  Quick Check: ~5s basic test, Deep Scan: ~30s full analysis
//  Tools: DNS Benchmark, Throttle Test
//

import SwiftUI

struct DiagnoseTabView: View {
    @StateObject private var diagnosticVM = DiagnosticViewModel()
    @State private var showingAdvanced = false
    @State private var showingDNSBenchmark = false
    @State private var showingThrottleTest = false
    @State private var showingTraceroute = false
    @State private var showingDNSAnalyzer = false
    @State private var showingConnectionComparison = false
    @State private var showingTLSAnalyzer = false
    // FIX (Phase 3): Privacy moved out of the Diagnose tab — it's not a network
    // diagnostic tool and was crowding the UI.
    // FIX (Phase 3): power-user tools collapse by default.
    @State private var advancedToolsExpanded = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Main Diagnostic Card
                    mainDiagnosticCard

                    // Quick Tools Section
                    quickToolsSection

                    // Results Section (if available)
                    if diagnosticVM.hasResult {
                        resultsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Diagnose")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if diagnosticVM.isRunning {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel", role: .destructive) {
                            diagnosticVM.cancelDiagnostic()
                        }
                    }
                } else if diagnosticVM.hasResult {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            // Share button
                            ShareLink(
                                item: generateReport(),
                                subject: Text("NetoSensei Diagnostic Report"),
                                message: Text("Network diagnostic results")
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }

                            // Run again button
                            Button(action: {
                                diagnosticVM.runFullDiagnostic()
                            }) {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAdvanced) {
                NewAdvancedDiagnosticView()
            }
            .sheet(isPresented: $showingDNSBenchmark) {
                DNSBenchmarkView()
            }
            .sheet(isPresented: $showingThrottleTest) {
                ThrottleDetectionView()
            }
            .sheet(isPresented: $showingTraceroute) {
                NavigationView {
                    TracerouteView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingTraceroute = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingDNSAnalyzer) {
                NavigationView {
                    DNSAnalyzerView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingDNSAnalyzer = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingConnectionComparison) {
                NavigationView {
                    ConnectionComparisonView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingConnectionComparison = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingTLSAnalyzer) {
                NavigationView {
                    TLSAnalyzerView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") { showingTLSAnalyzer = false }
                            }
                        }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Main Diagnostic Card (PART 3: Added Quick Check & Deep Scan)

    private var mainDiagnosticCard: some View {
        VStack(spacing: 12) {
            // Quick Check Button (~5 seconds)
            Button(action: {
                diagnosticVM.runFullDiagnostic()
            }) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Check")
                            .font(.headline)
                        Text("Router • Internet • DNS • VPN • ISP")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    Text("~5s")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.accent)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(diagnosticVM.isRunning)

            // Deep Scan Button (~30 seconds)
            Button(action: {
                showingAdvanced = true
            }) {
                HStack {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Deep Scan")
                            .font(.headline)
                        Text("DNS hijacking • TLS certs • Traceroute • Security")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    Text("~30s")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(LinearGradient(
                    colors: [Color.purple, Color.indigo],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            // Running indicator
            if diagnosticVM.isRunning {
                CardView {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(diagnosticVM.currentTest)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }

            // Last result summary
            if let analysis = diagnosticVM.analysis, !diagnosticVM.isRunning {
                CardView {
                    HStack(spacing: 20) {
                        // Health Score
                        VStack {
                            Text("\(analysis.healthScore)")
                                .font(.title.bold())
                                .foregroundColor(NetworkColors.forHealthScore(analysis.healthScore))
                            Text("Health")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Divider()
                            .frame(height: 40)

                        // Primary Issue
                        VStack(alignment: .leading) {
                            Text(analysis.primaryProblem.rawValue)
                                .font(.subheadline.bold())
                            Text(analysis.beginnerExplanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Quick Tools Section
    // FIX (Phase 3): collapsed by default. Most users want answers (Quick Check
    // / Deep Scan), not a toolkit. The 6 individual tools live behind a
    // disclosure for power users who want to test specific things. "Privacy"
    // was removed from the Diagnose tab — not a network diagnostic.

    private var quickToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    advancedToolsExpanded.toggle()
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced Tools (for power users)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Run individual tests with custom parameters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: advancedToolsExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if advancedToolsExpanded {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    // DNS Benchmark
                    ToolButton(
                        icon: "server.rack",
                        title: "DNS Benchmark",
                        subtitle: "Test DNS servers",
                        color: .blue
                    ) {
                        showingDNSBenchmark = true
                    }

                    // Throttle Detection
                    ToolButton(
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        title: "Throttle Test",
                        subtitle: "Detect ISP throttling",
                        color: .orange
                    ) {
                        showingThrottleTest = true
                    }

                    // Network Path (Traceroute)
                    ToolButton(
                        icon: "point.topleft.down.to.point.bottomright.curvepath",
                        title: "Network Path",
                        subtitle: "Trace route to destination",
                        color: .purple
                    ) {
                        showingTraceroute = true
                    }

                    // DNS Analyzer
                    ToolButton(
                        icon: "lock.shield",
                        title: "DNS Analyzer",
                        subtitle: "DNS security & leaks",
                        color: .green
                    ) {
                        showingDNSAnalyzer = true
                    }

                    // Wi-Fi vs Cellular
                    ToolButton(
                        icon: "arrow.left.arrow.right",
                        title: "Wi-Fi vs Cell",
                        subtitle: "Compare connections",
                        color: .teal
                    ) {
                        showingConnectionComparison = true
                    }

                    // TLS Analyzer
                    ToolButton(
                        icon: "lock.shield.fill",
                        title: "TLS Analyzer",
                        subtitle: "Check TLS & certificates",
                        color: .indigo
                    ) {
                        showingTLSAnalyzer = true
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.headline)
                .padding(.leading, 4)

            DiagnosticContentView(vm: diagnosticVM)
        }
    }

    // MARK: - Report Generation

    private func generateReport() -> String {
        DiagnosticReportGenerator.shared.generateReport(
            diagnostic: diagnosticVM.result,
            speedTest: HistoryManager.shared.speedTestHistory.first,
            vpnInfo: SmartVPNDetector.shared.detectionResult,
            analysis: diagnosticVM.analysis,
            networkStatus: NetworkMonitorService.shared.currentStatus
        )
    }
}

// MARK: - Tool Button

struct ToolButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    DiagnoseTabView()
}
