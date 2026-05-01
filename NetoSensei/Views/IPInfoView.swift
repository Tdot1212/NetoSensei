//
//  IPInfoView.swift
//  NetoSensei
//
//  IP geolocation and information view
//

import SwiftUI
import MapKit

struct IPInfoView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var geoIPService = GeoIPService.shared
    @ObservedObject private var networkMonitor = NetworkMonitorService.shared
    @State private var isRefreshing = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    if geoIPService.isLoading {
                        ProgressView("Loading IP information...")
                            .padding()
                    } else {
                        // FIXED: Use SmartVPNDetector as single source of truth
                        if SmartVPNDetector.shared.detectionResult?.isVPNActive ?? false {
                            VPNActiveBanner()
                        }

                        // IP Address Card
                        IPAddressCard(geoIP: geoIPService.currentGeoIP)

                        // Location Card
                        LocationCard(geoIP: geoIPService.currentGeoIP, networkStatus: networkMonitor.currentStatus)

                        // ISP Card
                        ISPCard(geoIP: geoIPService.currentGeoIP)

                        // Security Flags
                        if geoIPService.currentGeoIP.hasSecurityFlags {
                            SecurityFlagsCard(geoIP: geoIPService.currentGeoIP)
                        }

                        // Local Network Info
                        LocalNetworkCard(networkStatus: networkMonitor.currentStatus)
                    }
                }
                .padding()
            }
            .navigationTitle("IP Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
            .onAppear {
                if geoIPService.currentGeoIP.publicIP == "0.0.0.0" {
                    refresh()
                }
            }
        }
    }

    private func refresh() {
        isRefreshing = true

        Task {
            _ = await geoIPService.fetchGeoIPInfo()
            isRefreshing = false
        }
    }
}

// MARK: - IP Address Card

struct IPAddressCard: View {
    let geoIP: GeoIPInfo

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "globe")
                .font(.system(size: 50))
                .foregroundColor(.blue)

            Text(geoIP.publicIP)
                .font(.system(size: 28, weight: .bold, design: .monospaced))

            Text(geoIP.ipVersion)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(8)

            if let hostname = geoIP.hostname {
                Text(hostname)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Location Card

struct LocationCard: View {
    let geoIP: GeoIPInfo
    let networkStatus: NetworkStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.red)

                Text("Location")
                    .font(.headline)

                Spacer()
            }

            if !geoIP.displayLocation.isEmpty {
                VStack(spacing: 8) {
                    if let city = geoIP.city {
                        LocationRow(icon: "building.2", label: "City", value: city)
                    }

                    if let region = geoIP.region {
                        LocationRow(icon: "map", label: "Region", value: region)
                    }

                    if let country = geoIP.country {
                        LocationRow(icon: "flag", label: "Country", value: country)
                    }

                    if let timezone = geoIP.timezone {
                        LocationRow(icon: "clock", label: "Timezone", value: timezone)
                    }

                    if let lat = geoIP.latitude, let lon = geoIP.longitude {
                        LocationRow(
                            icon: "mappin.and.ellipse",
                            label: "Coordinates",
                            value: "\(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))"
                        )
                    }

                    // Cellular accuracy disclaimer
                    if networkStatus.connectionType == .cellular {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text("On cellular data, location shows your carrier's network location, not your exact physical location.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 8)
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            } else {
                Text("Location information unavailable")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct LocationRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - ISP Card

struct ISPCard: View {
    let geoIP: GeoIPInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.orange)

                Text("Internet Service Provider")
                    .font(.headline)

                Spacer()
            }

            if let isp = geoIP.isp {
                ISPRow(icon: "network", label: "ISP", value: isp)
            }

            if let org = geoIP.org, org != geoIP.isp {
                ISPRow(icon: "building.2", label: "Organization", value: org)
            }

            if let asn = geoIP.asn {
                ISPRow(icon: "number", label: "ASN", value: asn)
            }

            if let asnOrg = geoIP.asnOrg {
                ISPRow(icon: "server.rack", label: "AS Organization", value: asnOrg)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct ISPRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Security Flags Card

struct SecurityFlagsCard: View {
    let geoIP: GeoIPInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.red)

                Text("Security Flags")
                    .font(.headline)

                Spacer()
            }

            ForEach(geoIP.securityWarnings, id: \.self) { warning in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text(warning)
                        .font(.subheadline)

                    Spacer()
                }
            }

            if geoIP.isCGNAT {
                Text("CGNAT may affect certain online services and peer-to-peer connections.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Local Network Card

struct LocalNetworkCard: View {
    let networkStatus: NetworkStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(.blue)

                Text("Local Network")
                    .font(.headline)

                Spacer()
            }

            if let localIP = networkStatus.localIP {
                LocalNetworkRow(icon: "personalhotspot", label: "Local IP", value: localIP)
            }

            if let gateway = networkStatus.router.gatewayIP {
                // FIXED: "router" is not a valid SF Symbol - use "wifi.router" (iOS 16+) or fallback
                LocalNetworkRow(icon: "wifi.router", label: "Gateway", value: gateway)
            }

            if let ssid = networkStatus.wifi.ssid {
                LocalNetworkRow(icon: "wifi", label: "Wi-Fi Network", value: ssid)
            }

            LocalNetworkRow(
                icon: "network",
                label: "Connection",
                value: networkStatus.connectionType?.displayName ?? "Unknown"
            )

            HStack {
                Image(systemName: "4.circle")
                    .frame(width: 20)
                    .foregroundColor(.secondary)

                Text("IPv4")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: networkStatus.isIPv4Enabled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(networkStatus.isIPv4Enabled ? .green : .red)
            }

            HStack {
                Image(systemName: "6.circle")
                    .frame(width: 20)
                    .foregroundColor(.secondary)

                Text("IPv6")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: networkStatus.isIPv6Enabled ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(networkStatus.isIPv6Enabled ? .green : .red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct LocalNetworkRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - VPN Active Banner
// FIXED: Issue 14 - Indicate this is VPN IP, not real location

struct VPNActiveBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("VPN Active")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Showing VPN exit point, not your real location")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }

            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct IPInfoView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // IP Address Card
                    VStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)

                        Text("203.0.113.45")
                            .font(.title.bold())
                            .fontDesign(.monospaced)

                        Text("IPv4")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)

                    // Location Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                            Text("Location")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("San Francisco, California")
                            Text("United States")
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)

                    // ISP Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "building.2")
                                .foregroundColor(.purple)
                            Text("ISP")
                                .font(.headline)
                        }

                        Text("Example Internet Provider")
                        Text("AS12345")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("IP Information")
            .navigationBarTitleDisplayMode(.inline)
        }
        .previewDisplayName("IP Info")
    }
}
