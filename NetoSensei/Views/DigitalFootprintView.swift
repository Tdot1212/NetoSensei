//
//  DigitalFootprintView.swift
//  NetoSensei
//
//  Privacy tool to find and remove personal information from data
//  broker sites. Shows scan results, privacy score, and removal tracking.
//

import SwiftUI

struct DigitalFootprintView: View {
    @StateObject private var scanner = DigitalFootprintScanner.shared
    @State private var showingProfileSetup = false
    @State private var showingBrokerList = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if let profile = scanner.scanProfile {
                    profileCard(profile: profile)
                } else {
                    setupProfileCard
                }

                if scanner.isScanning {
                    scanProgressCard
                }

                if !scanner.scanResults.isEmpty {
                    resultsSummary
                }

                categoriesSection

                quickActionsSection
            }
            .padding()
        }
        .navigationTitle("Digital Footprint")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingProfileSetup = true }) {
                        Label("Edit Profile", systemImage: "person.circle")
                    }

                    Button(action: { showingBrokerList = true }) {
                        Label("View All Brokers", systemImage: "list.bullet")
                    }

                    if scanner.scanProfile != nil {
                        Button(role: .destructive, action: scanner.clearAllData) {
                            Label("Clear All Data", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingProfileSetup) {
            ProfileSetupView()
        }
        .sheet(isPresented: $showingBrokerList) {
            DataBrokerListView()
        }
        .refreshable {
            if let profile = scanner.scanProfile {
                await scanner.startScan(profile: profile)
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "eye.slash.fill")
                    .font(.title2)
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Digital Footprint")
                        .font(.headline)
                    Text("Find & remove your data from the web")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Profile Card

    private func profileCard(profile: ScanProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.title)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.fullName)
                        .font(.headline)

                    if let city = profile.city, let state = profile.state {
                        Text("\(city), \(state)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: { showingProfileSetup = true }) {
                    Text("Edit")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Divider()

            Button(action: startScan) {
                HStack {
                    if scanner.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(width: 20, height: 20)
                        Text("Scanning...")
                    } else {
                        Image(systemName: "magnifyingglass")
                        Text(scanner.scanResults.isEmpty ? "Scan Data Brokers" : "Scan Again")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(scanner.isScanning ? Color.gray : Color.purple)
                .cornerRadius(10)
            }
            .disabled(scanner.isScanning)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Setup Profile Card

    private var setupProfileCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text("Set Up Your Profile")
                .font(.headline)

            Text("Enter your information to search for your data across data broker sites.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingProfileSetup = true }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Create Profile")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Scan Progress

    private var scanProgressCard: some View {
        VStack(spacing: 8) {
            ProgressView(value: scanner.progress)
                .progressViewStyle(.linear)

            HStack {
                Text("Checking: \(scanner.currentBroker)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(scanner.progress * 100))%")
                    .font(.caption.bold())
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Results Summary

    private var resultsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy Score")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color(UIColor.systemGray4), lineWidth: 8)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: Double(scanner.exposureScore) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(scanner.exposureScore)")
                            .font(.title2.bold())
                        Text("/ 100")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    FootprintStatRow(icon: "exclamationmark.triangle.fill", color: .red, label: "Found", value: "\(scanner.foundCount)")
                    FootprintStatRow(icon: "clock.fill", color: .orange, label: "Pending", value: "\(scanner.pendingCount)")
                    FootprintStatRow(icon: "checkmark.circle.fill", color: .green, label: "Removed", value: "\(scanner.removedCount)")
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    private var scoreColor: Color {
        if scanner.exposureScore >= 80 { return .green }
        if scanner.exposureScore >= 50 { return .orange }
        return .red
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse by Category")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12) {
                ForEach(DataBroker.Category.allCases, id: \.self) { category in
                    NavigationLink(destination: CategoryBrokersView(category: category)) {
                        FootprintCategoryCard(category: category)
                    }
                }
            }
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            NavigationLink(destination: EasyOptOutsView()) {
                FootprintQuickActionRow(
                    icon: "bolt.fill",
                    title: "Easy Opt-Outs",
                    subtitle: "Quick removals you can do now",
                    color: .green
                )
            }

            NavigationLink(destination: RemovalGuideView()) {
                FootprintQuickActionRow(
                    icon: "book.fill",
                    title: "Removal Guide",
                    subtitle: "Step-by-step instructions",
                    color: .blue
                )
            }

            NavigationLink(destination: RemovalProgressView()) {
                FootprintQuickActionRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Track Progress",
                    subtitle: "Monitor your removal requests",
                    color: .purple
                )
            }
        }
    }

    // MARK: - Actions

    private func startScan() {
        guard let profile = scanner.scanProfile else { return }
        Task {
            await scanner.startScan(profile: profile)
        }
    }
}

// MARK: - Supporting Views

private struct FootprintStatRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}

struct FootprintCategoryCard: View {
    let category: DataBroker.Category

    var brokerCount: Int {
        DataBrokerDatabase.shared.getBrokersByCategory(category).count
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.icon)
                .font(.title2)
                .foregroundColor(categoryColor)

            Text(category.rawValue)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text("\(brokerCount) sites")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }

    var categoryColor: Color {
        switch category {
        case .peopleSearch: return .blue
        case .dataAggregator: return .purple
        case .marketingList: return .orange
        case .backgroundCheck: return .red
        case .socialMedia: return .green
        case .publicRecords: return .gray
        case .advertising: return .yellow
        case .other: return .secondary
        }
    }
}

struct FootprintQuickActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        DigitalFootprintView()
    }
}
