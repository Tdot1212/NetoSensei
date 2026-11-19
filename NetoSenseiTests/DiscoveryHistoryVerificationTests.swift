import Testing
import Foundation
@testable import NetoSensei

struct DiscoveryHistoryVerificationTests {
    @Test func subnetUsesActualMaskAndNeverLeavesNetwork() {
        let small = IPv4Subnet(address: "192.168.1.6", netmask: "255.255.255.252")!
        #expect(small.candidates == ["192.168.1.5"])
        #expect(IPv4Subnet(address: "192.168.1.6", netmask: "255.0.255.0") == nil)
        #expect(IPv4Subnet(address: "999.1.1.1", netmask: "255.255.255.0") == nil)
        #expect(IPv4Subnet(address: "192.168.1.6", netmask: "255.255.255.255")!.candidates.isEmpty)
        #expect(IPv4Subnet(address: "192.168.1.6", netmask: "255.255.255.254")!.candidates == ["192.168.1.7"])
        let wide = IPv4Subnet(address: "10.1.2.9", netmask: "255.255.0.0")!
        #expect(wide.candidates.count == 255)
        #expect(wide.candidates.allSatisfy { $0.hasPrefix("10.1.2.") })
    }
    @MainActor @Test func networkIsolationUserLabelsReturnAlertsAndPersistence() {
        let suite = "DeviceHistoryVerification-"+UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = Date()
        let manager = DeviceHistoryManager(defaults: defaults, clock: { now })
        let device = NetworkDeviceDiscovery.DiscoveredDevice(ipAddress: "192.168.1.5", responseTimeMs: 1, hostname: "iphone")
        manager.processDiscoveredDevices([device], currentSSID: "A")
        let id = manager.devices[0].id
        #expect(manager.connectedDevices.count == 1 && !manager.devices[0].isTrusted)
        manager.trustDevice(id); manager.setCustomName(id, name: "My phone")
        manager.setNotes(id, notes: "Mine"); manager.setDeviceType(id, type: .tablet)
        #expect(manager.devices[0].displayName == "My phone")
        manager.processDiscoveredDevices([device], currentSSID: "B")
        #expect(manager.devices.count == 2 && manager.connectedDevices.count == 1)
        #expect(manager.devices.last?.isTrusted == false)
        manager.processDiscoveredDevices([], currentSSID: "A")
        now = now.addingTimeInterval(9*86400)
        manager.processDiscoveredDevices([device], currentSSID: "A")
        #expect(manager.alerts.contains { $0.type == .deviceReturned })
        #expect(manager.devices.first { $0.id == id }?.deviceType == .tablet)
        #expect(!manager.eventsForDevice(id).isEmpty)
        let saved = DeviceHistoryManager(defaults: defaults)
        #expect(saved.devices == manager.devices)
        manager.markAlertRead(manager.alerts[0].id)
        #expect(manager.unreadAlertCount == manager.alerts.filter { !$0.isRead }.count)
        manager.markAllAlertsRead(); #expect(manager.unreadAlertCount == 0)
        manager.untrustDevice(id); #expect(manager.untrustedDevices.count == 2)
        manager.deleteDevice(id); #expect(manager.eventsForDevice(id).isEmpty)
        manager.clearAlerts(); #expect(manager.alerts.isEmpty)
        manager.trackDeviceHistory = false; manager.saveSettings()
        #expect(!DeviceHistoryManager(defaults: defaults).trackDeviceHistory)
        manager.processDiscoveredDevices([device], currentSSID: "C")
        #expect(manager.devices.count == 1)
        manager.clearAllHistory(); #expect(manager.devices.isEmpty && manager.events.isEmpty)
    }
    @MainActor @Test func anonymousNetworksCannotShareFamiliarLabels() {
        let suite = "AnonymousHistory-"+UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = DeviceHistoryManager(defaults: defaults)
        let d = NetworkDeviceDiscovery.DiscoveredDevice(ipAddress: "192.168.1.1", responseTimeMs: 1, isGateway: true)
        manager.processDiscoveredDevices([d], currentSSID: nil)
        let id = manager.devices[0].id
        #expect(manager.devices[0].deviceType == .router)
        manager.trustDevice(id)
        manager.processDiscoveredDevices([d], currentSSID: nil)
        #expect(manager.devices.count == 2 && manager.devices.last?.isTrusted == false)
        #expect(manager.connectedDevices.count == 1)
    }
    @MainActor @Test func malformedDiscoveryPacketsAreBounded() {
        let parser = NetworkDeviceDiscovery.shared
        for count in 0...128 {
            #expect(parser.parseNetBIOSResponse(buffer: [UInt8](repeating: 255, count: count), length: count) == nil)
        }
        #expect(parser.parseNetBIOSResponse(buffer: [], length: 4096) == nil)
        let headers = parser.parseSSDPHeaders("HTTP/1.1 200 OK\r\nSERVER: fixture\r\nLocation: http://192.0.2.1/x\r\n\r\n")
        #expect(headers["server"] == "fixture")
    }
    @MainActor @Test func timelineHasUnknownHoursAndOnlyObservedStates() {
        let now = Date()
        #expect(ConnectionStabilityMonitor.timeline([], hours: 24, now: now).allSatisfy { $0 == nil })
        let samples = [ConnectionStabilityMonitor.Observation(timestamp: now.addingTimeInterval(-10), connected: true, latency: 20),
                       .init(timestamp: now.addingTimeInterval(-20), connected: false, latency: nil)]
        let buckets = ConnectionStabilityMonitor.timeline(samples, hours: 24, now: now)
        #expect(buckets.last! == false && buckets.dropLast().allSatisfy { $0 == nil })
        #expect(ConnectionStabilityMonitor.timeline(samples, hours: -1, now: now).isEmpty)
        var geo = GeoIPInfo.empty
        #expect(geo.isCGNAT == nil && !geo.hasSecurityFlags)
        geo.isCGNAT = true; #expect(geo.hasSecurityFlags)
    }
}

struct SignalVerificationTests {
    @MainActor @Test func invalidOrChangedNetworkCannotShowStaleSignal() {
        let tracker = SignalStrengthTracker()
        tracker.recordSample(strength: 0.8, ssid: "A")
        #expect(tracker.currentStrength == 0.8)
        for invalid in [0, -1, Double.nan, Double.infinity, 1.1] {
            tracker.recordSample(strength: invalid, ssid: "A")
            #expect(tracker.currentStrength == nil)
        }
        tracker.recordSample(strength: 0.4, ssid: "B")
        #expect(tracker.samples.count == 1 && tracker.averageStrength == 0.4)
        tracker.clearCurrent(); #expect(tracker.currentStrength == nil)
    }
}

struct EgressValidationTests {
    @Test func addressesMustBeActualIPv4OrIPv6() {
        for ip in ["203.0.113.1", "2001:db8::1", "8.8.8.8"] { #expect(GeoIPService.validIPAddress(ip)) }
        for ip in ["", "999.1.1.1", "0.0.0.0", "::", "apple.com", "1.2.3"] { #expect(!GeoIPService.validIPAddress(ip)) }
    }
}

struct PrivacyEvidenceVerificationTests {
    @Test func unverifiedChecksDoNotBecomeFailedProtectionOrConfirmedLeaks() {
        let unknown = PrivacyShieldStatus.CheckResult(passed: false, title: "Unverified", detail: "No evidence", recommendation: nil, severity: .warning)
        let status = PrivacyShieldStatus(vpnStatus: unknown, dnsPrivacy: unknown, ipHidden: unknown, webRTCLeak: unknown, httpsIntegrity: unknown, ipv6Leak: unknown)
        #expect(status.overallStatus.displayText == "Privacy Unverified")
        let exposure = ExposureInfo(publicIP: "203.0.113.1", visibleLocation: "Example", visibleISP: nil, ipType: "Unknown", isRealIP: true)
        #expect(exposure.locationDetail.contains("Approximate") && !exposure.locationDetail.contains("real location"))
    }
}
