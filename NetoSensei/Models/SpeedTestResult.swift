//
//  SpeedTestResult.swift
//  NetoSensei
//
//  Speed test results model
//

import Foundation

struct SpeedTestResult: Codable, Identifiable {
    var id: UUID
    var timestamp: Date

    // Download metrics
    var downloadSpeed: Double  // Mbps
    var downloadJitter: Double?  // ms

    // Upload metrics
    var uploadSpeed: Double  // Mbps
    var uploadJitter: Double?  // ms

    // Latency metrics
    var ping: Double  // ms
    var jitter: Double  // ms
    var packetLoss: Double  // percentage

    // Test details
    var serverUsed: String?
    var serverLocation: String?
    var testDuration: TimeInterval

    // Connection type at time of test
    var connectionType: String  // "WiFi", "Cellular", "Ethernet"
    var vpnActive: Bool
    var ipAddress: String?

    // Performance rating
    var quality: QualityRating

    enum QualityRating: String, Codable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        // VPN-aware quality rating
        static func from(downloadSpeed: Double, ping: Double, packetLoss: Double, vpnActive: Bool = false) -> QualityRating {
            // Packet loss is critical regardless of VPN
            if packetLoss > 5 { return .poor }

            if vpnActive {
                // VPN-adjusted thresholds — VPN always adds latency
                // These are realistic for international VPN connections
                if downloadSpeed >= 20 && ping < 500 && packetLoss < 2 {
                    return .excellent  // Great for VPN
                } else if downloadSpeed >= 10 && ping < 600 && packetLoss < 3 {
                    return .good  // Good for VPN
                } else if downloadSpeed >= 5 && ping < 800 {
                    return .fair  // Okay for VPN
                } else {
                    return .poor  // Slow even for VPN
                }
            } else {
                // Direct connection thresholds
                if ping > 100 { return .poor }

                if downloadSpeed >= 100 && ping < 30 && packetLoss < 1 { return .excellent }
                if downloadSpeed >= 25 && ping < 50 && packetLoss < 2 { return .good }
                if downloadSpeed >= 10 { return .fair }

                return .poor
            }
        }
    }

    // VPN-aware quality description
    var qualityDescription: String {
        if vpnActive {
            switch quality {
            case .excellent:
                return "Great for VPN"
            case .good:
                return "Good for VPN"
            case .fair:
                return "Okay for VPN"
            case .poor:
                return "Slow (even for VPN)"
            }
        } else {
            return quality.rawValue
        }
    }

    init(downloadSpeed: Double, uploadSpeed: Double, ping: Double, jitter: Double, packetLoss: Double,
         serverUsed: String? = nil, serverLocation: String? = nil, testDuration: TimeInterval,
         connectionType: String, vpnActive: Bool, ipAddress: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.ping = ping
        self.jitter = jitter
        self.packetLoss = packetLoss
        self.serverUsed = serverUsed
        self.serverLocation = serverLocation
        self.testDuration = testDuration
        self.connectionType = connectionType
        self.vpnActive = vpnActive
        self.ipAddress = ipAddress
        self.quality = QualityRating.from(downloadSpeed: downloadSpeed, ping: ping, packetLoss: packetLoss, vpnActive: vpnActive)
    }

    var summary: String {
        let download = String(format: "%.1f", downloadSpeed)
        let upload = String(format: "%.1f", uploadSpeed)
        let latency = String(format: "%.0f", ping)

        return "\(download) Mbps ↓ / \(upload) Mbps ↑ | \(latency)ms ping | \(quality.rawValue)"
    }

    var isStreamingCapable: Bool {
        // Can handle 4K streaming?
        downloadSpeed >= 25 && packetLoss < 2 && ping < 100
    }

    var recommendedVideoQuality: String {
        if downloadSpeed >= 25 { return "4K UHD" }
        if downloadSpeed >= 8 { return "Full HD (1080p)" }
        if downloadSpeed >= 3 { return "HD (720p)" }
        return "SD (480p)"
    }

    // MARK: - Streaming Capability Analysis

    /// Detailed streaming capability analysis
    var streamingCapability: StreamingCapability {
        StreamingCapability.analyze(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            latency: ping,
            jitter: jitter,
            packetLoss: packetLoss
        )
    }
}

// MARK: - Streaming Capability Model

struct StreamingCapability {
    let maxVideoQuality: VideoQuality
    let supportedPlatforms: [StreamingPlatformCapability]
    let videoCallQuality: VideoCallQuality
    let gamingCapability: GamingCapability
    let overallRating: OverallStreamingRating
    let limitingFactor: LimitingFactor?
    let recommendations: [String]

    enum VideoQuality: String, Comparable {
        case uhd4K = "4K UHD"
        case fullHD = "1080p Full HD"
        case hd720 = "720p HD"
        case sd480 = "480p SD"
        case sd360 = "360p Low"
        case audioOnly = "Audio Only"

        var minDownloadMbps: Double {
            switch self {
            case .uhd4K: return 25.0
            case .fullHD: return 8.0
            case .hd720: return 5.0
            case .sd480: return 3.0
            case .sd360: return 1.5
            case .audioOnly: return 0.5
            }
        }

        static func < (lhs: VideoQuality, rhs: VideoQuality) -> Bool {
            lhs.minDownloadMbps < rhs.minDownloadMbps
        }
    }

    struct StreamingPlatformCapability {
        let platform: String
        let maxQuality: VideoQuality
        let expectedBuffering: BufferingLevel
        let notes: String?

        enum BufferingLevel: String {
            case none = "No buffering expected"
            case rare = "Rare buffering"
            case occasional = "Occasional buffering"
            case frequent = "Frequent buffering"
        }
    }

    enum VideoCallQuality: String {
        case excellent = "HD video calls with screen sharing"
        case good = "HD video calls"
        case fair = "SD video calls"
        case poor = "Audio only recommended"
        case unusable = "Video calls not recommended"
    }

    enum GamingCapability: String {
        case competitive = "Competitive gaming ready"
        case casual = "Casual gaming"
        case limited = "Single player only"
        case notRecommended = "Gaming not recommended"
    }

    enum OverallStreamingRating: String {
        case excellent = "Excellent"
        case good = "Good"
        case adequate = "Adequate"
        case limited = "Limited"
        case poor = "Poor"
    }

    enum LimitingFactor: String {
        case bandwidth = "Download speed"
        case latency = "High latency"
        case jitter = "Unstable connection (jitter)"
        case packetLoss = "Packet loss"
        case upload = "Upload speed (affects video calls)"
        case none = "No issues"
    }

    // MARK: - Analysis Factory

    static func analyze(downloadSpeed: Double, uploadSpeed: Double, latency: Double, jitter: Double, packetLoss: Double) -> StreamingCapability {
        // Determine max video quality based on download speed
        let maxQuality: VideoQuality
        if downloadSpeed >= 25 && packetLoss < 1 && jitter < 30 {
            maxQuality = .uhd4K
        } else if downloadSpeed >= 8 && packetLoss < 2 && jitter < 50 {
            maxQuality = .fullHD
        } else if downloadSpeed >= 5 && packetLoss < 3 {
            maxQuality = .hd720
        } else if downloadSpeed >= 3 {
            maxQuality = .sd480
        } else if downloadSpeed >= 1.5 {
            maxQuality = .sd360
        } else {
            maxQuality = .audioOnly
        }

        // Determine limiting factor
        let limitingFactor: LimitingFactor?
        if packetLoss > 2 {
            limitingFactor = .packetLoss
        } else if jitter > 50 {
            limitingFactor = .jitter
        } else if latency > 150 {
            limitingFactor = .latency
        } else if downloadSpeed < 5 {
            limitingFactor = .bandwidth
        } else if uploadSpeed < 2 {
            limitingFactor = .upload
        } else {
            limitingFactor = nil
        }

        // Platform-specific capabilities
        let platforms = [
            StreamingPlatformCapability(
                platform: "Netflix",
                maxQuality: downloadSpeed >= 15 ? .uhd4K : (downloadSpeed >= 5 ? .fullHD : .hd720),
                expectedBuffering: packetLoss < 1 ? .none : (packetLoss < 3 ? .rare : .occasional),
                notes: downloadSpeed >= 25 ? "Dolby Vision/HDR supported" : nil
            ),
            StreamingPlatformCapability(
                platform: "YouTube",
                maxQuality: downloadSpeed >= 20 ? .uhd4K : (downloadSpeed >= 5 ? .fullHD : .hd720),
                expectedBuffering: jitter < 30 ? .none : .rare,
                notes: downloadSpeed >= 40 ? "60fps 4K supported" : nil
            ),
            StreamingPlatformCapability(
                platform: "TikTok/Douyin",
                maxQuality: downloadSpeed >= 8 ? .fullHD : .hd720,
                expectedBuffering: latency < 100 ? .none : .rare,
                notes: nil
            ),
            StreamingPlatformCapability(
                platform: "Bilibili",
                maxQuality: downloadSpeed >= 10 ? .uhd4K : .fullHD,
                expectedBuffering: jitter < 50 ? .none : .occasional,
                notes: downloadSpeed >= 15 ? "HEVC streaming supported" : nil
            ),
            StreamingPlatformCapability(
                platform: "Twitch",
                maxQuality: downloadSpeed >= 6 ? .fullHD : .hd720,
                expectedBuffering: latency < 80 ? .none : .rare,
                notes: latency < 50 ? "Low latency mode available" : nil
            )
        ]

        // Video call quality
        let videoCallQuality: VideoCallQuality
        if uploadSpeed >= 3 && downloadSpeed >= 3 && latency < 50 && jitter < 20 {
            videoCallQuality = .excellent
        } else if uploadSpeed >= 1.5 && downloadSpeed >= 1.5 && latency < 100 {
            videoCallQuality = .good
        } else if uploadSpeed >= 0.5 && downloadSpeed >= 0.5 && latency < 200 {
            videoCallQuality = .fair
        } else if latency < 300 {
            videoCallQuality = .poor
        } else {
            videoCallQuality = .unusable
        }

        // Gaming capability
        let gamingCapability: GamingCapability
        if latency < 30 && jitter < 10 && packetLoss < 0.5 {
            gamingCapability = .competitive
        } else if latency < 80 && jitter < 30 && packetLoss < 2 {
            gamingCapability = .casual
        } else if latency < 150 {
            gamingCapability = .limited
        } else {
            gamingCapability = .notRecommended
        }

        // Overall rating
        let overallRating: OverallStreamingRating
        if maxQuality >= .uhd4K && videoCallQuality == .excellent && gamingCapability == .competitive {
            overallRating = .excellent
        } else if maxQuality >= .fullHD && videoCallQuality != .poor {
            overallRating = .good
        } else if maxQuality >= .hd720 {
            overallRating = .adequate
        } else if maxQuality >= .sd480 {
            overallRating = .limited
        } else {
            overallRating = .poor
        }

        // Recommendations
        var recommendations: [String] = []
        if let factor = limitingFactor {
            switch factor {
            case .bandwidth:
                recommendations.append("Your download speed limits video quality. Consider upgrading your internet plan.")
            case .latency:
                recommendations.append("High latency may cause buffering. Try connecting to a closer server or check VPN settings.")
            case .jitter:
                recommendations.append("Unstable connection may cause stuttering. Close background apps using network.")
            case .packetLoss:
                recommendations.append("Packet loss detected. This can cause video freezing. Check WiFi signal strength.")
            case .upload:
                recommendations.append("Low upload speed affects video call quality. Avoid large uploads during calls.")
            case .none:
                break
            }
        }

        if maxQuality == .uhd4K {
            recommendations.append("Your connection supports 4K streaming on all major platforms.")
        }

        return StreamingCapability(
            maxVideoQuality: maxQuality,
            supportedPlatforms: platforms,
            videoCallQuality: videoCallQuality,
            gamingCapability: gamingCapability,
            overallRating: overallRating,
            limitingFactor: limitingFactor,
            recommendations: recommendations
        )
    }

    /// Human-readable summary
    var summary: String {
        "Max quality: \(maxVideoQuality.rawValue) | Video calls: \(videoCallQuality.rawValue) | Gaming: \(gamingCapability.rawValue)"
    }
}
