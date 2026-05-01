//
//  VPNToolsView.swift
//  NetoSensei
//
//  Unified VPN Tools - Intelligence & Snapshots in one place
//

import SwiftUI

struct VPNToolsView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Tab Picker
                Picker("VPN Tools", selection: $selectedTab) {
                    Text("Intelligence").tag(0)
                    Text("Snapshots").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab Content
                TabView(selection: $selectedTab) {
                    VPNIntelligenceView()
                        .tag(0)

                    VPNSnapshotView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("VPN Tools")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    VPNToolsView()
}
