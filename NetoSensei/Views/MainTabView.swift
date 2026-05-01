//
//  MainTabView.swift
//  NetoSensei
//
//  Main tab navigation hub
//  6 Tabs: Home, Diagnose, Speed, Security, AI Assist, History
//

import SwiftUI

/// Main tab-based navigation for the app
struct MainTabView: View {
    var body: some View {
        TabView {
            // Tab 1: Home (Dashboard)
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // Tab 2: Diagnose (Full diagnostic + Advanced + DNS Benchmark + Throttle Test)
            DiagnoseTabView()
                .tabItem {
                    Label("Diagnose", systemImage: "stethoscope")
                }
                .tag(1)

            // Tab 3: Speed (Speed Test + Streaming Capability)
            SpeedTabView()
                .tabItem {
                    Label("Speed", systemImage: "speedometer")
                }
                .tag(2)

            // Tab 4: Security (VPN Tools + Network Security Audit)
            SecurityTabView()
                .tabItem {
                    Label("Security", systemImage: "shield.checkerboard")
                }
                .tag(3)

            // Tab 5: AI Assistant (Chat with AI about network issues)
            AIChatView()
                .tabItem {
                    Label("AI Assist", systemImage: "bubble.left.and.text.bubble.right")
                }
                .tag(4)

            // Tab 6: History (Timeline, baseline, stability, past results)
            NetworkHistoryView()
                .tabItem {
                    Label("History", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(5)
        }
        .accentColor(AppColors.accent)
    }
}

// MARK: - Preview

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
