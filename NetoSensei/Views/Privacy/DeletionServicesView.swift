//
//  DeletionServicesView.swift
//  NetoSensei
//
//  Comparison of professional data deletion services
//  (Incogni, DeleteMe, Optery, Kanary).
//

import SwiftUI

struct DeletionServicesView: View {
    @State private var showingBrowser = false
    @State private var browserURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Intro
                VStack(alignment: .leading, spacing: 8) {
                    Text("These services do the work for you — they contact hundreds of data brokers and handle removal requests automatically. If you don't want to manually opt out from each site, this is the way to go.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Service cards
                ForEach(PrivacyActionCenterManager.deletionServices) { service in
                    serviceCard(service)
                }
            }
            .padding()
        }
        .navigationTitle("Deletion Services")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingBrowser) {
            if let url = browserURL {
                InAppBrowserView(url: url, tintColor: .systemPurple)
                    .ignoresSafeArea()
            }
        }
    }

    private func serviceCard(_ service: DeletionService) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.name)
                            .font(.headline)

                        if service.freeOption {
                            Text("FREE TIER")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .cornerRadius(3)
                        }

                        if service.hasIOSApp {
                            Text("iOS APP")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }

                    Text("\(service.brokersCovered)+ brokers covered")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Rating
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(String(format: "%.1f", service.rating))
                        .font(.caption.bold())
                }
            }

            Text(service.description)
                .font(.caption)
                .foregroundColor(.secondary)

            // Pricing
            HStack {
                if let yearly = service.yearlyPrice {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(yearly)
                            .font(.subheadline.bold())
                            .foregroundColor(.green)
                        Text("annual")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let monthly = service.monthlyPrice {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(monthly)
                            .font(.subheadline.bold())
                        Text("monthly")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Pros / Cons
            VStack(alignment: .leading, spacing: 6) {
                ForEach(service.pros.prefix(3), id: \.self) { pro in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(pro)
                            .font(.caption)
                    }
                }

                ForEach(service.cons.prefix(2), id: \.self) { con in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Text(con)
                            .font(.caption)
                    }
                }
            }

            // Visit button
            Button(action: {
                if let url = URL(string: service.websiteURL) {
                    browserURL = url
                    showingBrowser = true
                }
            }) {
                HStack {
                    Image(systemName: "safari")
                    Text("Visit \(service.name)")
                }
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .cornerRadius(10)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}
