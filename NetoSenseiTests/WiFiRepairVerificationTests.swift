import Foundation
import Testing
@testable import NetoSensei

struct WiFiRepairVerificationTests {
    @Test func namesAttachOnlyToObservedAddressesAndServiceNamesDoNotInflateCount() {
        let tcp = [
            NetworkDeviceDiscovery.DiscoveredDevice(ipAddress: "192.168.1.1", responseTimeMs: 1, isGateway: true),
            .init(ipAddress: "192.168.1.2", responseTimeMs: 2, hostname: "Phone"),
            .init(ipAddress: "192.168.1.4", responseTimeMs: 2)
        ]
        let ssdp = [NetworkDeviceDiscovery.SSDPDevice(id: "a", ip: "192.168.1.2", friendlyName: "Living room",
                                                   deviceType: nil, manufacturer: nil, modelName: nil, server: nil),
                    .init(id: "b", ip: "192.168.1.3", friendlyName: "Printer", deviceType: nil, manufacturer: nil, modelName: nil, server: nil)]
        let bonjour = [NetworkDeviceDiscovery.BonjourDevice(id: "a", name: "MacBook", serviceType: "_ssh._tcp", domain: "local."),
                       .init(id: "b", name: "MacBook", serviceType: "_smb._tcp", domain: "local.")]
        let inventory = WiFiDeviceInventory(tcp: tcp, ssdp: ssdp, bonjour: bonjour, gateway: "192.168.1.1",
            localAddress: "192.168.1.4", resolvedNames: ["192.168.1.2": ["MacBook"], "192.168.1.200": ["Unlinked"]])
        #expect(inventory.otherAddressCount == 2)
        #expect(inventory.observations.map(\.name) == [nil, "MacBook", "Printer", nil])
        #expect(inventory.advertisedNames == ["MacBook"])
        let ambiguous = WiFiDeviceInventory(tcp: tcp, ssdp: ssdp, bonjour: [], gateway: nil, localAddress: nil,
            resolvedNames: ["192.168.1.2": ["Name A", "Name B"]])
        #expect(ambiguous.observations[1].name == "Living room")
    }

    @Test func routerShortcutRequiresAnObservedGatewayOnTheWifiSubnet() {
        let subnet = IPv4Subnet(address: "192.168.1.42", netmask: "255.255.255.0")
        #expect(WiFiRepairGuide.routerURL(gateway: "192.168.1.1", localSubnet: subnet)?.absoluteString == "https://192.168.1.1")
        for address in [nil, "192.168.1.42", "192.168.1.255", "192.168.1.0", "192.168.2.1", "192.168.1.1@host.test"] {
            #expect(WiFiRepairGuide.routerURL(gateway: address, localSubnet: subnet) == nil)
        }
    }

    @Test func missingDelayInEitherBatchStaysUnavailable() throws {
        func run(_ ms: Double?) -> SpeedTestResult {
            .init(downloadSpeed: 50, uploadSpeed: 10, ping: ms, jitter: nil, packetLoss: nil,
                  serverUsed: "Test", testDuration: 10, connectionType: "WiFi", vpnActive: false,
                  networkSSID: "Home", localSubnet: "192.168.1")
        }
        let before = [run(40),run(60),run(50)]
        let after = [run(20),run(10),run(30)]
        let complete = try #require(WiFiSpeedComparison.evaluate(before: before, after: after))
        #expect(complete.beforeLatencyMs == 50 && complete.afterLatencyMs == 20)
        let partial = try #require(WiFiSpeedComparison.evaluate(before: before, after: [run(nil),run(10),run(30)]))
        #expect(partial.beforeLatencyMs == nil && partial.afterLatencyMs == nil)
    }

    @Test func responsivenessRequiresCompleteBatchesAndTheSameHTTPSProbe() throws {
        func run(_ delay: Double?, endpoint: String = "https://fixture.test") -> SpeedTestResult {
            var result = SpeedTestResult(downloadSpeed: 50, uploadSpeed: 10, ping: nil, jitter: nil, packetLoss: nil,
                serverUsed: "Fixture", testDuration: 10, connectionType: "WiFi", vpnActive: false,
                networkSSID: "Home", localSubnet: "192.168.1")
            result.responsiveness = HTTPSResponsiveness(endpoint: endpoint, idleMs: 30, downloadMs: delay, uploadMs: nil)
            return result
        }
        let before = [run(110), run(140), run(120)]
        let after = [run(60), run(70), run(50)]
        let outcome = try #require(WiFiSpeedComparison.evaluate(before: before, after: after)?.response)
        #expect(outcome.download?.before == 120 && outcome.download?.after == 60)
        #expect(outcome.download?.rangesOverlap == false)
        #expect(outcome.idle?.rangesOverlap == true && outcome.upload == nil)
        #expect(WiFiSpeedComparison.evaluate(before: before, after: [run(nil), run(70), run(50)])?.response?.download == nil)
        #expect(WiFiSpeedComparison.evaluate(before: before, after: [run(60, endpoint: "https://other.test"), run(70), run(50)])?.response == nil)
        #expect(HTTPSResponsiveness.median([90, .nan, 80]) == nil)
    }

    @Test func deliberateVPNChangeNeedsTwoKnownExitsOnTheSameWiFiAndServer() {
        func run(_ ip: String?, ssid: String = "Home") -> SpeedTestResult {
            .init(downloadSpeed: 50, uploadSpeed: 10, ping: nil, jitter: nil, packetLoss: nil,
                serverUsed: "Fixture", testDuration: 10, connectionType: "WiFi", vpnActive: true,
                ipAddress: ip, networkSSID: ssid, localSubnet: "192.168.1")
        }
        let before = Array(repeating: run("203.0.113.10"), count: 3)
        let after = Array(repeating: run("203.0.113.20"), count: 3)
        #expect(WiFiSpeedComparison.evaluate(before: before, after: after) == nil)
        #expect(WiFiSpeedComparison.evaluate(before: before, after: after, compareVPNExits: true) != nil)
        #expect(WiFiSpeedComparison.evaluate(before: before, after: before, compareVPNExits: true) == nil)
        #expect(WiFiSpeedComparison.evaluate(before: before, after: Array(repeating: run(nil), count: 3), compareVPNExits: true) == nil)
        #expect(WiFiSpeedComparison.evaluate(before: before, after: Array(repeating: run("203.0.113.20", ssid: "Other"), count: 3), compareVPNExits: true) == nil)
    }

    @Test func unifiClientRequestAndPageAreScopedToTheOfficialConnector() throws {
        let site = "00000000-0000-0000-0000-000000000001"
        let request = try UniFiClients.request(console: "host-1:123", site: site, key: "synthetic", offset: 25)
        #expect(request.url?.host == "api.ui.com")
        #expect(request.url?.scheme == "https")
        #expect(request.url?.path.hasSuffix("/sites/\(site)/clients") == true)
        #expect(request.url?.query?.contains("offset=25") == true)
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "synthetic")
        #expect(throws: UniFiClients.Failure.self) {
            try UniFiClients.request(console: "../wrong", site: site, key: "synthetic", offset: 0)
        }
        let fixture = Data("""
        {"offset":25,"count":1,"totalCount":26,"data":[{"id":"1","name":"Phone","type":"WIRELESS","ipAddress":"192.0.2.42"}]}
        """.utf8)
        let page = try UniFiClients.decodePage(fixture, expectedOffset: 25)
        #expect(page.data.first?.displayName == "Phone")
        #expect(page.data.first?.connection == "Wi-Fi")
        #expect(throws: UniFiClients.Failure.self) { try UniFiClients.decodePage(fixture, expectedOffset: 0) }
    }
}
