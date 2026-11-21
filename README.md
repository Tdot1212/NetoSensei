# NetoSensei

An iOS Wi-Fi and network diagnostic app. Current local development build: **1.0 (28)**.

NetoSensei reports observed measurements, unavailable checks and interpretations
separately. A speed test measures application throughput through the current
internet/VPN path; it does not measure Wi-Fi PHY link rate or prove an ISP fault.

## Current tools

- Connection, gateway TCP response, DNS lookup and internet response monitoring.
- Download/upload speed tests against qualified endpoints, with absent metrics
  represented as unavailable rather than failure sentinels.
- Wi-Fi Assistant: partial device discovery, session-only recognition, and three
  before/three after throughput and idle-delay comparisons under compatible conditions.
  The repair guide covers lag, downloads, and identifying unfamiliar devices.
  Device names include reported hostnames and service names where available.
- Diagnose shows local connection details immediately and runs connection,
  DNS, TLS, VPN, endpoint and throughput checks from one screen. Completed
  sections appear while the rest of the run continues. Throughput tests run
  in sequence so they do not compete with each other.
- Endpoint Checks compares independent responses. It is not an IP-hop traceroute.
- TLS/certificate inspection, DNS benchmarks, local port inspection and history.
- The Wi-Fi Assistant can use DeepSeek to prioritize an existing repair step from
  the selected concern and a limited set of measurements. It sends only when
  requested, uses the app’s Keychain credential, and omits network names, device
  names and addresses. The repair guide is available without a key.
- The separate AI chat can discuss diagnostic snapshots and has no router controls.

## Limits that affect interpretation

Public iOS APIs do not provide general nearby Wi-Fi scanning or other-app traffic
inspection. Current-network Wi-Fi information is entitlement/permission dependent;
`NEHotspotNetwork.fetchCurrent` does not populate signal strength.

Local discovery is partial and cannot prove device ownership. A responding IP or
advertised name is not an authenticated device identity. The optional UniFi connector can read connected clients. Device blocking and
router settings changes are performed in the router’s own controls. Wi-Fi credentials may differ from administrator credentials.

TCP/HTTP attempt failure is not IP packet loss. DNS/VPN/browser leak protection
remains unverified when the app lacks the necessary route or browser evidence.
Ratings and estimated video quality are interpretations, not physical measurements.
No speed improvement or universal router compatibility is guaranteed.

Legacy diagnostic implementations are preserved in `ArchivedDiagnostics/`, outside
the Xcode app target. They must not be restored without accuracy review and tests.

## Run on an iPhone without publishing

Open `NetoSensei.xcodeproj` in Xcode, select the NetoSensei scheme and your paired,
unlocked iPhone, then Product > Run. USB or Xcode wireless pairing both work.
Developer Mode must be enabled on the phone. Existing automatic signing is used.

For a repeatable local build/install/launch:

```sh
./scripts/install-latest-iphone.sh
```

Pass a device identifier as the first argument when multiple phones are connected.
The script builds current local source and installs a development app. It does not
archive, upload to App Store Connect, or publish an App Store release.

## Verification

```sh
xcodebuild -project NetoSensei.xcodeproj -scheme NetoSensei \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -enableCodeCoverage YES -resultBundlePath build/Verification.xcresult test
```

Unit tests include controlled URLProtocol transports and clocks for known byte/
second calculations. These fixtures run only through explicitly injected test
instances; the shared app instance uses real system services and URLSession.
Fixtures do not establish physical network accuracy.

Export per-function execution evidence with:

```sh
xcrun xccov view --report --json build/Verification.xcresult > build/coverage.json
python3 scripts/report-function-coverage.py build/coverage.json build/coverage-report
```

Coverage includes synthesized functions, accessors and closures. Executing a
function does not prove all branches or hardware/network conditions are correct.
See `docs/MEASUREMENT_REVIEW_2026_11_19.md` for the current validation evidence and
remaining gaps. Real RF/bandwidth accuracy requires controlled network references.
