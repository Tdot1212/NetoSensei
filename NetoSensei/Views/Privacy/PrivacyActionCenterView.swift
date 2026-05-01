//
//  PrivacyActionCenterView.swift
//  NetoSensei
//
//  Main hub for the Privacy Action Center — progress tracking,
//  quick wins, category browsing, paid services, and Google tools.
//

import SwiftUI

struct PrivacyActionCenterView: View {
    @StateObject private var manager = PrivacyActionCenterManager.shared
    @State private var showingProfileSetup = false
    @State private var selectedCategory: OptOutAction.BrokerCategory?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard

                if manager.profile == nil {
                    profilePrompt
                } else {
                    progressCard
                }

                quickStartSection

                categoriesSection

                paidServicesSection

                googleToolsSection
            }
            .padding()
        }
        .navigationTitle("Privacy Center")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { showingProfileSetup = true }) {
                        Label("Edit Profile", systemImage: "person.circle")
                    }

                    if manager.completedCount > 0 || manager.submittedCount > 0 {
                        Button(role: .destructive, action: manager.resetAll) {
                            Label("Reset Progress", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingProfileSetup) {
            PrivacyProfileSetupView()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy Action Center")
                        .font(.headline)
                    Text("Take control of your personal data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text("Remove your info from data brokers, opt out of tracking, and clean up your digital footprint. Every action here opens the real opt-out page so you can take action immediately.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Profile Prompt

    private var profilePrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Set Up Your Profile")
                .font(.subheadline.bold())

            Text("Add your name so we can generate removal request emails for you.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { showingProfileSetup = true }) {
                Text("Set Up Profile")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Progress")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray4), lineWidth: 6)
                        .frame(width: 70, height: 70)

                    Circle()
                        .trim(from: 0, to: manager.progressPercent / 100)
                        .stroke(progressColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(manager.progressPercent))%")
                        .font(.subheadline.bold())
                }

                VStack(alignment: .leading, spacing: 6) {
                    ProgressStatRow(icon: "checkmark.circle.fill", color: .green, label: "Confirmed", count: manager.completedCount)
                    ProgressStatRow(icon: "clock.fill", color: .orange, label: "Submitted", count: manager.submittedCount)
                    ProgressStatRow(icon: "circle", color: .gray, label: "Remaining", count: manager.totalCount - manager.completedCount - manager.submittedCount)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var progressColor: Color {
        if manager.progressPercent >= 75 { return .green }
        if manager.progressPercent >= 40 { return .orange }
        return .red
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quick Wins")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)

                Spacer()

                if !manager.easyActions.isEmpty {
                    Text("\(manager.easyActions.count) easy opt-outs")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if manager.easyActions.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All easy opt-outs completed!")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    ForEach(manager.easyActions.prefix(3)) { action in
                        NavigationLink(destination: OptOutActionDetailView(actionID: action.id)) {
                            OptOutActionRow(action: action)
                        }
                        .buttonStyle(.plain)
                    }

                    if manager.easyActions.count > 3 {
                        NavigationLink(destination: AllActionsView(filter: .easy)) {
                            Text("View all \(manager.easyActions.count) easy opt-outs")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Browse by Category")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(OptOutAction.BrokerCategory.allCases, id: \.self) { category in
                    NavigationLink(destination: AllActionsView(filterCategory: category)) {
                        PrivacyCategoryCard(category: category, count: manager.optOutActions.filter { $0.category == category }.count)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Paid Services Section

    private var paidServicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Professional Removal Services")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            Text("These services handle 100+ brokers automatically. Worth it if you want comprehensive coverage without doing it yourself.")
                .font(.caption)
                .foregroundColor(.secondary)

            NavigationLink(destination: DeletionServicesView()) {
                HStack(spacing: 12) {
                    Image(systemName: "building.2.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Compare Deletion Services")
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        Text("Incogni, DeleteMe, Optery, Kanary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Google Tools Section

    private var googleToolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Free Google Tools")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            let googleActions = manager.optOutActions.filter { $0.category == .searchEngine }
            ForEach(googleActions) { action in
                NavigationLink(destination: OptOutActionDetailView(actionID: action.id)) {
                    OptOutActionRow(action: action)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Progress Stat Row

struct ProgressStatRow: View {
    let icon: String
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)")
                .font(.caption.bold())
        }
    }
}

// MARK: - Opt-Out Action Row

struct OptOutActionRow: View {
    let action: OptOutAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.status.icon)
                .foregroundColor(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.brokerName)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    Text(action.difficulty.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(difficultyColor)
                        .cornerRadius(3)
                }

                Text("~\(action.estimatedMinutes) min  •  \(action.method.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var statusColor: Color {
        switch action.status {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .submitted: return .orange
        case .confirmed: return .green
        }
    }

    private var difficultyColor: Color {
        switch action.difficulty {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }
}

// MARK: - Category Card

struct PrivacyCategoryCard: View {
    let category: OptOutAction.BrokerCategory
    let count: Int

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: category.icon)
                .font(.title3)
                .foregroundColor(.purple)

            Text(category.rawValue)
                .font(.caption.bold())
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(count) sites")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
