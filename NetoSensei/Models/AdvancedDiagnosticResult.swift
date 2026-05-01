//
//  AdvancedDiagnosticResult.swift
//  NetoSensei
//
//  Advanced diagnostic results for comprehensive network analysis
//

import Foundation

struct AdvancedDiagnosticResult: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // A. WiFi Throughput Test
    var wifiThroughputResult: WiFiThroughputResult?

    // B. Traceroute
    var tracerouteResult: TracerouteResult?

    // C. VPN Performance Benchmark
    var vpnBenchmarkResult: VPNBenchmarkResult?

    // D. Network Noise Scan
    var networkNoiseResult: NetworkNoiseResult?

    // E. Router Load Test
    var routerLoadResult: RouterLoadResult?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        wifiThroughputResult: WiFiThroughputResult? = nil,
        tracerouteResult: TracerouteResult? = nil,
        vpnBenchmarkResult: VPNBenchmarkResult? = nil,
        networkNoiseResult: NetworkNoiseResult? = nil,
        routerLoadResult: RouterLoadResult? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.wifiThroughputResult = wifiThroughputResult
        self.tracerouteResult = tracerouteResult
        self.vpnBenchmarkResult = vpnBenchmarkResult
        self.networkNoiseResult = networkNoiseResult
        self.routerLoadResult = routerLoadResult
    }
}

// MARK: - A. WiFi Throughput Result

struct WiFiThroughputResult: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // Measurements
    let downloadSpeed: Double  // Mbps
    let uploadSpeed: Double    // Mbps
    let latency: Double        // ms
    let jitter: Double         // ms
    let packetLoss: Double     // percentage

    // WiFi specific metrics
    let signalStrength: Int?   // RSSI in dBm
    let linkSpeed: Int?        // Mbps (PHY rate)
    let channel: Int?          // WiFi channel number
    let frequency: Double?     // GHz (2.4 or 5)

    // Quality assessment
    var quality: ThroughputQuality {
        if downloadSpeed >= 100 && uploadSpeed >= 50 && latency < 10 {
            return .excellent
        } else if downloadSpeed >= 50 && uploadSpeed >= 25 && latency < 20 {
            return .good
        } else if downloadSpeed >= 25 && uploadSpeed >= 10 && latency < 40 {
            return .fair
        } else {
            return .poor
        }
    }

    var issues: [String] {
        var problems: [String] = []

        if downloadSpeed < 10 {
            problems.append("Very slow WiFi download speed")
        }
        if uploadSpeed < 5 {
            problems.append("Very slow WiFi upload speed")
        }
        if latency > 50 {
            problems.append("High WiFi latency")
        }
        if jitter > 30 {
            problems.append("Unstable connection (high jitter)")
        }
        if packetLoss > 1.0 {
            problems.append("Packet loss detected")
        }
        // REMOVED: WiFi signal check - iOS cannot measure RSSI
        // signalStrength is always nil on iOS

        return problems
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        downloadSpeed: Double,
        uploadSpeed: Double,
        latency: Double,
        jitter: Double,
        packetLoss: Double,
        signalStrength: Int? = nil,
        linkSpeed: Int? = nil,
        channel: Int? = nil,
        frequency: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.latency = latency
        self.jitter = jitter
        self.packetLoss = packetLoss
        self.signalStrength = signalStrength
        self.linkSpeed = linkSpeed
        self.channel = channel
        self.frequency = frequency
    }
}

enum ThroughputQuality: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
}

// MARK: - B. Traceroute Result

struct TracerouteResult: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let destination: String
    let hops: [TracerouteHop]
    let totalLatency: Double

    // Identify bottleneck
    var bottleneckHop: TracerouteHop? {
        // Find hop with largest latency increase
        guard hops.count > 1 else { return nil }

        var maxIncrease = 0.0
        var bottleneck: TracerouteHop?

        for i in 1..<hops.count {
            let increase = hops[i].latency - hops[i-1].latency
            if increase > maxIncrease && increase > 20 { // Only if > 20ms increase
                maxIncrease = increase
                bottleneck = hops[i]
            }
        }

        return bottleneck
    }

    // AI-Interpreted Diagnosis
    var intelligentDiagnosis: IntelligentDiagnosis {
        guard let bottleneck = bottleneckHop else {
            return IntelligentDiagnosis(
                problemType: .none,
                userFriendlyExplanation: "No performance issues detected. Your connection is running smoothly.",
                technicalExplanation: "All hops show normal latency (<50ms increase per hop).",
                whatUserCanDo: ["Your network is performing well!", "No action needed."],
                severity: .good
            )
        }

        let hopNumber = bottleneck.hopNumber
        let hopName = bottleneck.hostname ?? bottleneck.ipAddress
        let latency = bottleneck.latency

        // Case A: Router Problem (Hop 1)
        // FIXED: Don't speculate about "overheating" from a single latency measurement
        // Also note: traceroute hop 1 timing may differ from direct gateway ping
        if hopNumber == 1 {
            let explanation: String
            if latency > 100 {
                explanation = "Your router is responding slowly (\(Int(latency))ms). Try restarting it."
            } else if latency > 50 {
                explanation = "Gateway latency is elevated (\(Int(latency))ms). May indicate router congestion."
            } else {
                explanation = "Router latency is acceptable (\(Int(latency))ms)."
            }

            return IntelligentDiagnosis(
                problemType: .routerOverload,
                userFriendlyExplanation: explanation,
                technicalExplanation: "First hop latency of \(Int(latency))ms. Compare with direct gateway ping test for consistency.",
                whatUserCanDo: [
                    "Restart your router",
                    "Disconnect unused devices",
                    "Check for bandwidth-heavy apps"
                ],
                severity: latency > 100 ? .warning : .info
            )
        }

        // Case B: ISP Congestion (Hops 2-3)
        else if hopNumber <= 3 {
            let isChinaTelecom = hopName.lowercased().contains("china") ||
                                hopName.lowercased().contains("telecom") ||
                                hopName.lowercased().contains("unicom")

            if isChinaTelecom {
                return IntelligentDiagnosis(
                    problemType: .ispCongestion,
                    userFriendlyExplanation: "High latency at hop \(hopNumber) (China Telecom core). Peak-hour congestion.",
                    technicalExplanation: "Your ISP's network is congested, likely during peak hours (7-10 PM).",
                    whatUserCanDo: [
                        "Wait for off-peak hours",
                        "Contact ISP about congestion",
                        "Consider switching ISP",
                        "Use VPN to route around congestion"
                    ],
                    severity: .warning
                )
            } else {
                return IntelligentDiagnosis(
                    problemType: .ispCongestion,
                    userFriendlyExplanation: "Local ISP issue at hop \(hopNumber). Problem in ISP's network.",
                    technicalExplanation: "Latency spike within your ISP's network infrastructure.",
                    whatUserCanDo: [
                        "Contact your ISP",
                        "Report slow speeds",
                        "Request line quality check"
                    ],
                    severity: .warning
                )
            }
        }

        // Case C: Great Firewall / International Gateway
        else if hopNumber >= 4 && (hopName.lowercased().contains("china") ||
                                    hopName.lowercased().contains("beijing") ||
                                    hopName.lowercased().contains("shanghai")) {
            return IntelligentDiagnosis(
                problemType: .greatFirewall,
                userFriendlyExplanation: "International gateway shows packet filtering — common during peak hours.",
                technicalExplanation: "China's international gateway throttles traffic during peak hours and performs deep packet inspection.",
                whatUserCanDo: [
                    "Use VPN with obfuscation",
                    "Try different VPN protocols (WireGuard, Shadowsocks)",
                    "Avoid peak hours if possible",
                    "Use domestic services when available"
                ],
                severity: .error
            )
        }

        // Case D: VPN Exit Node
        else if hopName.lowercased().contains("vpn") ||
                hopName.lowercased().contains("ash") ||  // Ashburn
                hopName.lowercased().contains("singapore") ||
                hopName.lowercased().contains("london") {
            return IntelligentDiagnosis(
                problemType: .vpnSlowExit,
                userFriendlyExplanation: "Your VPN exit server is overloaded or too far away.",
                technicalExplanation: "VPN server latency indicates overloaded exit node or suboptimal routing.",
                whatUserCanDo: [
                    "Switch to closer VPN server",
                    "Choose less crowded server",
                    "Try different VPN protocol",
                    "Upgrade to premium VPN tier"
                ],
                severity: .warning
            )
        }

        // Case E: Destination Server
        else if hopNumber > hops.count - 2 {
            return IntelligentDiagnosis(
                problemType: .destinationServer,
                userFriendlyExplanation: "The destination server (\(hopName)) is slow or overloaded.",
                technicalExplanation: "High latency at final hops indicates server-side performance issues.",
                whatUserCanDo: [
                    "Try different server/region",
                    "Wait and retry later",
                    "Check service status page",
                    "Contact service provider"
                ],
                severity: .info
            )
        }

        // Default: General backbone congestion
        else {
            return IntelligentDiagnosis(
                problemType: .backboneCongestion,
                userFriendlyExplanation: "Internet backbone congestion at \(hopName).",
                technicalExplanation: "Latency spike in internet transit network, likely due to routing issues or congestion.",
                whatUserCanDo: [
                    "Use VPN to try different route",
                    "Wait for congestion to clear",
                    "Contact service if persistent"
                ],
                severity: .warning
            )
        }
    }

    var diagnosis: String {
        return intelligentDiagnosis.userFriendlyExplanation
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        destination: String,
        hops: [TracerouteHop],
        totalLatency: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.destination = destination
        self.hops = hops
        self.totalLatency = totalLatency
    }
}

struct TracerouteHop: Codable, Identifiable {
    let id: UUID
    let hopNumber: Int
    let ipAddress: String
    let hostname: String?
    let latency: Double        // ms
    let latencyChange: Double  // Change from previous hop
    let asn: String?           // Autonomous System Number
    let isp: String?           // ISP name
    let location: String?      // Geographic location

    var status: HopStatus {
        if latency < 10 {
            return .excellent
        } else if latency < 50 {
            return .good
        } else if latency < 100 {
            return .fair
        } else if latency < 200 {
            return .slow
        } else {
            return .critical
        }
    }

    init(
        id: UUID = UUID(),
        hopNumber: Int,
        ipAddress: String,
        hostname: String? = nil,
        latency: Double,
        latencyChange: Double = 0,
        asn: String? = nil,
        isp: String? = nil,
        location: String? = nil
    ) {
        self.id = id
        self.hopNumber = hopNumber
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.latency = latency
        self.latencyChange = latencyChange
        self.asn = asn
        self.isp = isp
        self.location = location
    }
}

enum HopStatus: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case slow = "Slow"
    case critical = "Critical"
}

// MARK: - C. VPN Performance Benchmark

struct VPNBenchmarkResult: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // Current VPN info
    let isVPNActive: Bool
    let detectedVPNRegion: String?
    let detectedVPNProvider: String?

    // Performance metrics
    let speedWithVPN: Double?      // Mbps
    let speedWithoutVPN: Double?   // Mbps
    let vpnOverhead: Double?       // Percentage slowdown

    let latencyWithVPN: Double?    // ms
    let latencyWithoutVPN: Double? // ms
    let latencyIncrease: Double?   // ms

    // Regional performance
    let regionalBenchmarks: [VPNRegionBenchmark]
    let suggestedRegion: String?

    var efficiency: VPNEfficiency {
        guard let overhead = vpnOverhead else { return .unknown }

        if overhead < 10 {
            return .excellent
        } else if overhead < 25 {
            return .good
        } else if overhead < 50 {
            return .fair
        } else {
            return .poor
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        isVPNActive: Bool,
        detectedVPNRegion: String? = nil,
        detectedVPNProvider: String? = nil,
        speedWithVPN: Double? = nil,
        speedWithoutVPN: Double? = nil,
        vpnOverhead: Double? = nil,
        latencyWithVPN: Double? = nil,
        latencyWithoutVPN: Double? = nil,
        latencyIncrease: Double? = nil,
        regionalBenchmarks: [VPNRegionBenchmark] = [],
        suggestedRegion: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.isVPNActive = isVPNActive
        self.detectedVPNRegion = detectedVPNRegion
        self.detectedVPNProvider = detectedVPNProvider
        self.speedWithVPN = speedWithVPN
        self.speedWithoutVPN = speedWithoutVPN
        self.vpnOverhead = vpnOverhead
        self.latencyWithVPN = latencyWithVPN
        self.latencyWithoutVPN = latencyWithoutVPN
        self.latencyIncrease = latencyIncrease
        self.regionalBenchmarks = regionalBenchmarks
        self.suggestedRegion = suggestedRegion
    }
}

struct VPNRegionBenchmark: Codable, Identifiable {
    let id: UUID
    let region: String
    let country: String
    let city: String?
    let latency: Double
    let estimatedSpeed: Double
    let score: Double  // Combined metric

    init(
        id: UUID = UUID(),
        region: String,
        country: String,
        city: String? = nil,
        latency: Double,
        estimatedSpeed: Double,
        score: Double
    ) {
        self.id = id
        self.region = region
        self.country = country
        self.city = city
        self.latency = latency
        self.estimatedSpeed = estimatedSpeed
        self.score = score
    }
}

enum VPNEfficiency: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unknown = "Unknown"
}

// MARK: - D. Network Noise Result

struct NetworkNoiseResult: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // Current network info
    let currentChannel: Int
    let currentFrequency: Double  // 2.4 or 5 GHz
    let currentSignalStrength: Int // dBm

    // Channel analysis
    let nearbyNetworks: [NearbyNetwork]
    let channelCongestion: ChannelCongestion
    let interference: InterferenceLevel

    // Recommendations
    let suggestedChannel: Int?
    let suggestedFrequency: Double?

    var overallNoiseLevel: NoiseLevel {
        let congestionScore = channelCongestion.rawValue
        let interferenceScore = interference.rawValue
        let avgScore = (congestionScore + interferenceScore) / 2

        if avgScore < 2 {
            return .low
        } else if avgScore < 3 {
            return .moderate
        } else if avgScore < 4 {
            return .high
        } else {
            return .severe
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        currentChannel: Int,
        currentFrequency: Double,
        currentSignalStrength: Int,
        nearbyNetworks: [NearbyNetwork],
        channelCongestion: ChannelCongestion,
        interference: InterferenceLevel,
        suggestedChannel: Int? = nil,
        suggestedFrequency: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.currentChannel = currentChannel
        self.currentFrequency = currentFrequency
        self.currentSignalStrength = currentSignalStrength
        self.nearbyNetworks = nearbyNetworks
        self.channelCongestion = channelCongestion
        self.interference = interference
        self.suggestedChannel = suggestedChannel
        self.suggestedFrequency = suggestedFrequency
    }
}

struct NearbyNetwork: Codable, Identifiable {
    let id: UUID
    let ssid: String
    let bssid: String
    let channel: Int
    let frequency: Double
    let signalStrength: Int  // dBm
    let isOverlapping: Bool

    init(
        id: UUID = UUID(),
        ssid: String,
        bssid: String,
        channel: Int,
        frequency: Double,
        signalStrength: Int,
        isOverlapping: Bool
    ) {
        self.id = id
        self.ssid = ssid
        self.bssid = bssid
        self.channel = channel
        self.frequency = frequency
        self.signalStrength = signalStrength
        self.isOverlapping = isOverlapping
    }
}

enum ChannelCongestion: Int, Codable {
    case minimal = 1
    case light = 2
    case moderate = 3
    case heavy = 4
    case severe = 5
}

enum InterferenceLevel: Int, Codable {
    case none = 1
    case low = 2
    case moderate = 3
    case high = 4
    case severe = 5
}

enum NoiseLevel: String, Codable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
    case severe = "Severe"
}

// MARK: - E. Router Load Result

struct RouterLoadResult: Codable, Identifiable {
    let id: UUID
    let timestamp: Date

    // Load test results
    let baselineLatency: Double      // ms with no load
    let loadedLatency: Double        // ms under load
    let latencyIncrease: Double      // ms increase
    let percentageIncrease: Double   // %

    // Throughput under load
    let baselineThroughput: Double   // Mbps
    let loadedThroughput: Double     // Mbps
    let throughputDrop: Double       // %

    // Connection stability
    let packetLoss: Double           // %
    let jitterIncrease: Double       // ms

    var isRouterOverloaded: Bool {
        percentageIncrease > 100 || throughputDrop > 50
    }

    var routerHealth: RouterHealth {
        if percentageIncrease < 20 && throughputDrop < 10 {
            return .excellent
        } else if percentageIncrease < 50 && throughputDrop < 25 {
            return .good
        } else if percentageIncrease < 100 && throughputDrop < 50 {
            return .fair
        } else {
            return .overloaded
        }
    }

    var diagnosis: String {
        if isRouterOverloaded {
            return "Router CPU overloaded - Consider upgrading router or reducing connected devices"
        } else if percentageIncrease > 50 {
            return "Router struggling under load - May need firmware update"
        } else {
            return "Router handling load well"
        }
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        baselineLatency: Double,
        loadedLatency: Double,
        latencyIncrease: Double,
        percentageIncrease: Double,
        baselineThroughput: Double,
        loadedThroughput: Double,
        throughputDrop: Double,
        packetLoss: Double,
        jitterIncrease: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.baselineLatency = baselineLatency
        self.loadedLatency = loadedLatency
        self.latencyIncrease = latencyIncrease
        self.percentageIncrease = percentageIncrease
        self.baselineThroughput = baselineThroughput
        self.loadedThroughput = loadedThroughput
        self.throughputDrop = throughputDrop
        self.packetLoss = packetLoss
        self.jitterIncrease = jitterIncrease
    }
}

enum RouterHealth: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case overloaded = "Overloaded"
}

// MARK: - Intelligent Diagnosis (AI-Interpreted)

struct IntelligentDiagnosis: Codable {
    let problemType: LegacyNetworkProblemType
    let userFriendlyExplanation: String
    let technicalExplanation: String
    let whatUserCanDo: [String]
    let severity: DiagnosisSeverity
}

enum LegacyNetworkProblemType: String, Codable {
    case none = "No Problem"
    case routerOverload = "Router Overload"
    case ispCongestion = "ISP Congestion"
    case greatFirewall = "Great Firewall"
    case vpnSlowExit = "VPN Slow Exit"
    case destinationServer = "Destination Server"
    case backboneCongestion = "Backbone Congestion"
}

enum DiagnosisSeverity: String, Codable {
    case good = "Good"
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
}

// MARK: - Packet Loss Analysis

struct PacketLossAnalysis: Codable {
    let packetsSent: Int
    let packetsReceived: Int
    let lossPercentage: Double

    var quality: LegacyConnectionQuality {
        if lossPercentage <= 2.0 {
            return .good
        } else if lossPercentage <= 10.0 {
            return .unstable
        } else {
            return .broken
        }
    }

    var userFriendlyExplanation: String {
        switch quality {
        case .good:
            return "0-2% packet loss (Good). Your connection is stable."
        case .unstable:
            return "3-10% packet loss (Unstable). You may experience lag in video calls and gaming."
        case .broken:
            return ">10% packet loss (Broken). Your connection is severely degraded."
        }
    }

    var recommendations: [String] {
        switch quality {
        case .good:
            return ["Your connection is stable!", "No action needed."]
        case .unstable:
            // FIXED: Remove WiFi signal advice - iOS cannot measure it
            return [
                "Restart your router",
                "Disconnect unused devices",
                "Check for bandwidth-heavy apps",
                "Try a wired connection if available"
            ]
        case .broken:
            return [
                "Critical connection issues detected",
                "Restart router immediately",
                "Check physical cables",
                "Contact ISP if problem persists",
                "Consider wired connection"
            ]
        }
    }
}

enum LegacyConnectionQuality: String, Codable {
    case good = "Good"
    case unstable = "Unstable"
    case broken = "Broken"
}

// MARK: - Jitter Stability Analysis

struct JitterStabilityAnalysis: Codable, Identifiable {
    let id: UUID
    let measurements: [JitterMeasurement]  // 10-20 ping samples
    let averageJitter: Double
    let maxJitter: Double
    let stability: StabilityLevel

    var userFriendlyExplanation: String {
        switch stability {
        case .excellent:
            return "Excellent stability (jitter: \(Int(averageJitter))ms). Perfect for video calls and gaming."
        case .good:
            return "Good stability (jitter: \(Int(averageJitter))ms). Suitable for most applications."
        case .fair:
            return "Fair stability (jitter: \(Int(averageJitter))ms). May cause issues in real-time apps."
        case .poor:
            return "Poor stability (jitter: \(Int(averageJitter))ms). Will cause lag in video calls."
        case .terrible:
            return "Terrible stability (jitter: \(Int(averageJitter))ms). Unusable for real-time communication."
        }
    }

    var recommendations: [String] {
        switch stability {
        case .excellent, .good:
            return ["Your connection is stable for video calls and gaming!"]
        case .fair:
            return [
                "Try switching to 5GHz WiFi",
                "Reduce distance to router",
                "Close bandwidth-heavy applications"
            ]
        case .poor, .terrible:
            return [
                "Switch to 5GHz WiFi band",
                "Use wired Ethernet connection",
                "Restart router",
                "Reduce connected devices",
                "Contact ISP about line quality"
            ]
        }
    }

    init(
        id: UUID = UUID(),
        measurements: [JitterMeasurement],
        averageJitter: Double,
        maxJitter: Double
    ) {
        self.id = id
        self.measurements = measurements
        self.averageJitter = averageJitter
        self.maxJitter = maxJitter

        // Calculate stability
        if averageJitter < 10 && maxJitter < 20 {
            self.stability = .excellent
        } else if averageJitter < 20 && maxJitter < 40 {
            self.stability = .good
        } else if averageJitter < 40 && maxJitter < 80 {
            self.stability = .fair
        } else if averageJitter < 80 && maxJitter < 150 {
            self.stability = .poor
        } else {
            self.stability = .terrible
        }
    }
}

struct JitterMeasurement: Codable, Identifiable {
    let id: UUID
    let sequenceNumber: Int
    let latency: Double  // ms
    let timestamp: Date

    init(id: UUID = UUID(), sequenceNumber: Int, latency: Double, timestamp: Date = Date()) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.latency = latency
        self.timestamp = timestamp
    }
}

enum StabilityLevel: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case terrible = "Terrible"
}

// MARK: - Device Load Analysis

struct DeviceLoadAnalysis: Codable {
    let estimatedDeviceCount: Int
    let routerCapacity: RouterCapacity
    let isOverloaded: Bool

    var userFriendlyExplanation: String {
        if isOverloaded {
            return "Your router is \(routerCapacity.rawValue) and overloaded with \(estimatedDeviceCount) devices. Consider upgrading to WiFi 6."
        } else {
            return "Your router can handle \(estimatedDeviceCount) devices comfortably."
        }
    }

    var recommendations: [String] {
        if isOverloaded {
            return [
                "Disconnect unused devices",
                "Upgrade to WiFi 6 router",
                "Use wired connections for stationary devices",
                "Enable QoS (Quality of Service)",
                "Consider mesh WiFi system"
            ]
        } else {
            return ["Your router capacity is adequate."]
        }
    }
}

enum RouterCapacity: String, Codable {
    case lowEnd = "low-end"
    case midRange = "mid-range"
    case highEnd = "high-end"
    case enterprise = "enterprise-grade"
}
