import Foundation

struct ConnectionNextStep {
    let title: String
    let change: String
    let verify: String

    static func speed(_ result: SpeedTestResult, passesPlan: Bool? = nil) -> Self {
        if let response = result.responsiveness,
           let idle = response.idleMs,
           let loaded = [response.downloadMs, response.uploadMs].compactMap({ $0 }).max(),
           loaded >= idle * 2, loaded - idle >= 75 {
            return Self(title: "Web requests slowed down during the transfer",
                change: "Pause large downloads, uploads and cloud backups on devices you control. Keep the same Wi-Fi and VPN server.",
                verify: "Repeat the check and compare idle and loaded HTTPS times. If the gap returns even when the network is idle, repeat near the router and, if available, on a wired device.")
        }
        if result.vpnActive && (result.downloadSpeed < 10 || (result.ping ?? 0) > 150) {
            return Self(title: "Compare a different VPN server on the same Wi-Fi",
                change: "In your VPN app, choose another server you trust. Keep the Wi-Fi network and location fixed.",
                verify: "Run the test again and compare the server name and measured download speed. Use Wi-Fi Assistant for matched before-and-after runs.")
        }
        if result.downloadSpeed < 10 || passesPlan == false {
            if result.connectionType == "Cellular" {
                return Self(title: "Compare cellular in another location",
                    change: "Move near a window or to another nearby location. Keep the same VPN setting.",
                    verify: "Test again with the same speed server. If the problem persists on cellular but Wi-Fi works at the same time, share both results with your carrier.")
            }
            return Self(title: "Check whether slow speed starts on Wi-Fi",
                change: "Pause other traffic and move close to the main router. Repeat on the same network.",
                verify: "If speed improves there, compare again at the original spot. If it stays slow near the router, run a wired test if available and share consistently slow wired readings with your ISP.")
        }
        if result.ping == nil {
            return Self(title: "Check what happens during the lag",
                change: "Choose Diagnose and run the full check where the lag happens. Use the affected website’s hostname if the problem is specific to one site.",
                verify: "Compare HTTPS response and responsiveness under load. If only one service is slow, try that service on another trusted connection.")
        }
        return Self(title: "Test the service that feels slow",
            change: "Use the affected site, call or stream on the same connection. If several services feel slow, pause competing traffic and rerun the speed test.",
            verify: "Compare readings from the same server before and after one change. A good transfer can coexist with slow responses from an individual service.")
    }

    static func speedFailed(_ reason: String, connectionType: String? = nil, vpnActive: Bool = false) -> Self {
        if reason.contains("path changed") || reason.contains("network path changed") {
            return Self(title: "Keep one connection for the whole test",
                change: "Choose Wi-Fi or cellular, keep the VPN setting fixed, and wait for that connection to settle.",
                verify: "Tap Try Again. Compare only tests that completed on one connection.")
        }
        if vpnActive {
            return Self(title: "Check the VPN route to the test server",
                change: "Open a familiar site in Safari. If it loads, choose another trusted server in your VPN app and keep the same Wi-Fi.",
                verify: "Try the speed test again. A successful transfer on the new VPN server gives you a route to compare.")
        }
        return Self(title: "Check whether the problem affects normal browsing",
            change: connectionType == "Cellular"
                ? "Open a familiar site in Safari. If several sites fail, run Diagnose, then compare on trusted Wi-Fi."
                : "Open a familiar site in Safari. Complete any Wi-Fi sign-in page. If several sites still fail, run Diagnose and compare on cellular if available.",
            verify: "Tap Try Again on a stable connection. If browsing works but speed transfers still fail, compare on the other connection and keep the server error.")
    }
}
