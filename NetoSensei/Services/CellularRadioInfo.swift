//
//  CellularRadioInfo.swift
//  NetoSensei
//
//  Commit 9 — cellular is a first-class connection.
//
//  WHAT iOS PERMITS (iOS 26.5 SDK, verified against the headers):
//   • Radio access technology (5G NR / LTE / 3G / 2G): AVAILABLE.
//     `CTTelephonyNetworkInfo.serviceCurrentRadioAccessTechnology` (iOS 12+)
//     keyed by `dataServiceIdentifier` (iOS 13+). Neither is deprecated.
//   • Carrier name: `serviceSubscriberCellularProviders` / `CTCarrier` are
//     deprecated since iOS 16 "with no replacement" and return "--". Not read.
//   • Signal strength / bars / dBm: NOT AVAILABLE to apps (private API).
//     Never displayed, never inferred. The (i) note on the card says so.
//
//  The previous reader (ConnectionComparator) ran once at singleton init and
//  gated the radio lookup on the deprecated carrier dictionary — if that came
//  back nil the radio was never read, and it never refreshed when the radio
//  changed. This reader keys on the data service, re-reads on
//  CTServiceRadioAccessTechnologyDidChangeNotification, and never guesses:
//  an unknown radio is nil and the card says just "Connected".
//

import Foundation
import CoreTelephony
import Combine

@MainActor
final class CellularRadioInfo: ObservableObject {
    static let shared = CellularRadioInfo()

    /// Plain generation label ("5G", "LTE", "3G", "2G") or nil when iOS reports
    /// none (no SIM, no cellular data service, simulator, or an unknown value).
    @Published private(set) var generation: String?
    /// The raw CoreTelephony constant, for logs and the (i) detail.
    @Published private(set) var rawTechnology: String?

    private let reader = RadioReader()
    private var observer: NSObjectProtocol?

    private init() {
        Task { [weak self] in await self?.refresh() }
        observer = NotificationCenter.default.addObserver(
            forName: .CTServiceRadioAccessTechnologyDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
    }

    /// Re-read the current radio for the service that carries data.
    private func refresh() async {
        let raw = await reader.currentRawTechnology()
        guard raw != rawTechnology else { return }
        rawTechnology = raw
        generation = Self.generationLabel(forRawTechnology: raw)
    }

    // CoreTelephony getters can make synchronous IPC calls. Keep both
    // creation and reads off the main actor.
    private actor RadioReader {
        #if !targetEnvironment(simulator)
        private lazy var info = CTTelephonyNetworkInfo()
        #endif

        func currentRawTechnology() -> String? {
            #if targetEnvironment(simulator)
            return nil
            #else
            guard let techs = info.serviceCurrentRadioAccessTechnology, !techs.isEmpty else { return nil }
            if let id = info.dataServiceIdentifier, let technology = techs[id] { return technology }
            return techs.count == 1 ? techs.values.first : nil
            #endif
        }
    }

    /// Pure mapping (unit-tested). Only the generations iOS actually reports;
    /// anything else is nil, never a default.
    nonisolated static func generationLabel(forRawTechnology raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA:
            return "5G"
        case CTRadioAccessTechnologyLTE:
            return "LTE"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x:
            return "2G"
        default:
            return nil
        }
    }

    /// The honest limit, stated once, reused by the card's (i) detail and the
    /// tower-congestion pattern's confidence text.
    nonisolated static let signalStrengthLimitation =
        "iOS doesn't let apps read cellular signal strength, so no bars are shown. The delay, speed and address-lookup numbers are real measurements over this connection."
}
