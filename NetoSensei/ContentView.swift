//
//  ContentView.swift
//  NetoSensei
//
//  Created by Tosh Yagishita on 15/12/2025.
//

import SwiftUI

struct ContentView: View {
    @State private var isLoaded = false

    var body: some View {
        ZStack {
            // Background color to ensure something is always visible
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            if isLoaded {
                // FIXED: MainTabView with proper NavigationView handling
                MainTabView()
            } else {
                // Show a loading screen while services initialize
                VStack(spacing: 20) {
                    Image(systemName: "network")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .tint(.blue)

                    Text("Initializing NetoSensei...")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Setting up network monitoring...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            // Debug: Print to console when view appears
            print("📱 ContentView appeared, isLoaded: \(isLoaded)")
        }
        .task {
            print("📱 ContentView task started")
            // Simple delay to let UI render first, then show main content
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            print("📱 ContentView setting isLoaded = true")
            isLoaded = true
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        // Simple preview that doesn't require services
        TabView {
            // Dashboard Tab
            NavigationView {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "network")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text("NetoSensei")
                        .font(.largeTitle.bold())

                    Text("Network Diagnostic Tool")
                        .font(.title3)
                        .foregroundColor(.gray)

                    Spacer()

                    // Sample status cards
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "wifi")
                                .foregroundColor(.green)
                            Text("WiFi Connected")
                            Spacer()
                            Text("Excellent")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)

                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.green)
                            Text("Internet")
                            Spacer()
                            Text("25 ms")
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .navigationTitle("Dashboard")
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            // Diagnose Tab
            Text("Diagnose")
                .tabItem {
                    Label("Diagnose", systemImage: "stethoscope")
                }

            // Streaming Tab
            Text("Streaming")
                .tabItem {
                    Label("Streaming", systemImage: "play.tv.fill")
                }

            // Speed Tab
            Text("Speed")
                .tabItem {
                    Label("Speed", systemImage: "speedometer")
                }

            // IP Info Tab
            Text("IP Info")
                .tabItem {
                    Label("IP Info", systemImage: "globe")
                }
        }
        .previewDisplayName("NetoSensei Preview")
    }
}
