//
//  MainTabView.swift
//  NetoSensei
//
//  Main tab navigation hub
//  5 Tabs: Home, Diagnose, Speed, Security, History
//

import SwiftUI

enum NetoTab: Hashable {
    case home, diagnose, speed, security, history
}

struct MainTabView: View {
    @State private var selection: NetoTab = .home

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(openTab: { selection = $0 })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(NetoTab.home)

            DiagnoseTabView()
                .tabItem { Label("Diagnose", systemImage: "stethoscope") }
                .tag(NetoTab.diagnose)

            SpeedTabView()
                .tabItem { Label("Speed", systemImage: "speedometer") }
                .tag(NetoTab.speed)

            SecurityTabView()
                .tabItem { Label("Security", systemImage: "shield.checkerboard") }
                .tag(NetoTab.security)

            NetworkHistoryView()
                .tabItem { Label("History", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(NetoTab.history)
        }
        .tint(AppColors.accent)
    }
}

// MARK: - Preview

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
