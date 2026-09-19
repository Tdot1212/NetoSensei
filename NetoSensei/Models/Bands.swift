//
//  Bands.swift
//  NetoSensei
//
//  Diagnosis v2 — ONE vocabulary (design §D).
//
//  A single five-band scale and a single table of per-metric edges. Every
//  word, colour and threshold that describes a measurement maps through this
//  file. The twenty separate "Excellent" scales inventoried in the design doc
//  (§1.6) are retired as their surfaces migrate to the verdict.
//
//  Decision (Phase 5b, resolved): the top band keeps the word "Excellent" —
//  one scale, one meaning, everywhere.
//
//  Edges are adopted from NetworkColors (already five-band and documented) with
//  one addition: internet delay VIA A VPN has its own edge set, because a
//  healthy international tunnel runs 100–400 ms and grading it on the direct
//  scale produced "Poor" for a working VPN (design §1.2).
//

import Foundation
import SwiftUI

enum Band: Int, Codable, Sendable, Comparable, CaseIterable {
    case critical = 0
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4

    static func < (lhs: Band, rhs: Band) -> Bool { lhs.rawValue < rhs.rawValue }

    var word: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .orange
        case .critical: return .red
        }
    }
}

/// The one table of band edges. Lower is better for every metric except
/// score, uptime and speed. Each function documents its edges; unit tests pin
/// them so a surface cannot drift to its own scale again.
enum MetricBands {

    /// 0–100 score. ≥80 / ≥60 / ≥40 / ≥20 / else.
    static func score(_ value: Int) -> Band {
        switch value {
        case 80...: return .excellent
        case 60...: return .good
        case 40...: return .fair
        case 20...: return .poor
        default: return .critical
        }
    }

    /// Router (gateway) delay, ms. <10 / <30 / <50 / <100 / ≥100.
    static func gatewayDelay(ms: Double) -> Band {
        switch ms {
        case ..<10: return .excellent
        case ..<30: return .good
        case ..<50: return .fair
        case ..<100: return .poor
        default: return .critical
        }
    }

    /// Internet delay, ms.
    /// Direct: <30 / <60 / <150 / <300 / ≥300.
    /// Via VPN: <100 / <250 / <400 / <800 / ≥800 — a tunnel to another
    /// continent adds 100–400 ms when it is working exactly as designed.
    static func internetDelay(ms: Double, viaVPN: Bool) -> Band {
        if viaVPN {
            switch ms {
            case ..<100: return .excellent
            case ..<250: return .good
            case ..<400: return .fair
            case ..<800: return .poor
            default: return .critical
            }
        }
        switch ms {
        case ..<30: return .excellent
        case ..<60: return .good
        case ..<150: return .fair
        case ..<300: return .poor
        default: return .critical
        }
    }

    /// VPN overhead = internet delay − router delay, ms. <30 / <75 / <150 / <250 / ≥250.
    static func vpnOverhead(ms: Double) -> Band {
        switch ms {
        case ..<30: return .excellent
        case ..<75: return .good
        case ..<150: return .fair
        case ..<250: return .poor
        default: return .critical
        }
    }

    /// Address lookup (DNS) delay, ms. <30 / <75 / <150 / <300 / ≥300.
    static func dnsDelay(ms: Double) -> Band {
        switch ms {
        case ..<30: return .excellent
        case ..<75: return .good
        case ..<150: return .fair
        case ..<300: return .poor
        default: return .critical
        }
    }

    /// Dropped data, percent. <0.5 / <1 / <3 / <10 / ≥10.
    static func packetLoss(percent: Double) -> Band {
        switch percent {
        case ..<0.5: return .excellent
        case ..<1: return .good
        case ..<3: return .fair
        case ..<10: return .poor
        default: return .critical
        }
    }

    /// Unsteady delay (jitter), ms. <5 / <15 / <30 / <50 / ≥50.
    static func jitter(ms: Double) -> Band {
        switch ms {
        case ..<5: return .excellent
        case ..<15: return .good
        case ..<30: return .fair
        case ..<50: return .poor
        default: return .critical
        }
    }

    /// Download speed, Mbps. ≥50 / ≥25 / ≥10 / ≥5 / else.
    static func downloadSpeed(mbps: Double) -> Band {
        switch mbps {
        case 50...: return .excellent
        case 25...: return .good
        case 10...: return .fair
        case 5...: return .poor
        default: return .critical
        }
    }
}
