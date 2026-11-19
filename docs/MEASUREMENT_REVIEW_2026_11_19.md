NetoSensei 1.0 (23) — verified development installation
19 November 2026 · Asia/Shanghai

Installed and launched the clean development app on Tosh’s iPhone BLACK
(iPhone 14 Pro Max, iOS 27.2). The installed version/build were read back from the
phone as 1.0 / 23, its process was observed running, and the temporary UI-test
runner was removed. Code signing passed. No App Store release or Git upload.
The existing Xcode project and local installer rebuild the current source.

RESULTS
- Final full iPhone suite: 202 distinct tests passed, zero failures/skips.
  Parameterized launch configurations produced 205 executions.
- Full simulator suite: 202 distinct tests passed, zero failures/skips.
- Latest simulator numerical regression suite: 186 tests passed, zero failures/skips.
- Real USB-connected iPhone radio-switch acceptance: passed. Separate Wi-Fi and
  cellular samples completed; Wi-Fi was restored. Corrected comparison messaging
  was verified on the actual device.
- Real assistant acceptance: passed. Discovery, recognition/undo, three baseline
  tests, three follow-up tests, comparison display and reset completed.
- Streaming, VPN Sites, History, Combined Security and Endpoint Speeds completed
  live on the phone. Changed screens were reviewed from captured screenshots.
- Saved history was read back from the actual app container; real speed values
  were present and unmeasured latency remained absent.
- Installer shell syntax and Git whitespace checks passed.

Observed samples are not guaranteed line capacity. The latest radio run recorded
111.3 Mbps down / 78.0 Mbps up on Wi-Fi, then 107.7 / 22.7 Mbps on cellular.
Latency was unavailable, so the app correctly withheld an overall winner.
The assistant recorded medians of 114.7 -> 121.2 Mbps (+5.7%). Its ranges overlapped;
the app correctly said normal variation may explain the difference.

FIXES
Actual DNS-wire benchmarking replaces HTTP timings attributed to DNS providers.
Certificate metadata and trust evaluation replace guessed fields and proxy-based
trust exceptions. Upload counts sent body bytes; compressed/text download bodies
cannot inflate throughput. Unknown stability hours, privacy protection, CGNAT,
signal data and unsupported router controls are not presented as verified facts.
Site-response errors, DoT query validation, combined security warning handling,
certificate count partitioning and kill-switch guidance were corrected.
Device history isolation, return alerts, user labels and gateway categorization
were corrected. Wi-Fi/cellular comparison explanations now distinguish missing
measurements from genuine connection failure. Shared median arithmetic fixes even
sample counts. Duplicate Wi-Fi/VPN scoring was removed; 41 obsolete Swift files
remain archived outside the app target.

SCOPE AND EVIDENCE
Application line coverage in the final phone suite: 41.68%.
Compiler-instrumented functions entered: 2,550 / 6,076.
These include SwiftUI closures, accessors and synthesized code. An entered function
is not necessarily fully branch-tested; an unentered function is a remaining
execution gap. This report does not claim exhaustive certification of every
function, physical network condition, router model or external service.

Automatic router settings/device blocking are not implemented. General nearby
Wi-Fi scanning, other-app bandwidth and end-to-end VPN/browser leak protection
remain unavailable/unverified where evidence is absent. Optional AI advice is not
a measurement source. These are explicit capability boundaries, not simulated
successful results. See the detailed accuracy review and per-function inventory.

Evidence files
- NetoSensei Build 23 Verification.json: test summaries, installation observations,
  bundle digest and exact application source hashes.
- NetoSensei Accuracy Review.txt: feature acceptance cases and boundaries.
- NetoSensei Function Coverage.json / NetoSensei Coverage Gaps.txt: final phone
  suite execution inventory.
- NetoSensei Verified Before After.png / NetoSensei Verified WiFi Cellular.png:
  actual iPhone screenshots, without fabricated values.

This report supersedes the build 22 validation report.

NetoSensei 1.0 (23) — feature acceptance evidence
19 November 2026

MEASUREMENT AND DATA CHECKS

Throughput
PASS: Decimal byte/second-to-Mbps arithmetic, known-byte controlled transfers,
short-body and rejected-status handling, monotonic duration handling, cancellation,
concurrent-run rejection, and path-change invalidation. HTTP compression and text
responses are rejected for throughput. Upload uses transmitted-body progress;
a successful status alone cannot establish that the requested body was sent.
Real local HTTP socket tests cover a complete upload and a premature success reply.
Actual Wi-Fi and cellular transfers also completed on the iPhone.

Latency and loss
PASS: Failed probes remain unavailable; UDP association produces no RTT. Median
and dispersion calculations are tested. Even-sized gateway sample sets average both middle values, using the same median helper as the main speed engine. TCP handshake and HTTPS response timings
are separate quantities. TCP/HTTP attempt failures are not represented as IP
packet loss. Proxy-intercepted delay measurements remain absent.

DNS
PASS: Actual DNS messages go to each selected resolver, with transaction/question
validation, bounded parsing, UDP timeout, malformed/unrelated-packet rejection,
and TCP fallback after truncation. Loopback UDP/TCP servers exercise the transport.
System DNS uses bounded OS resolution and is not ranked against direct queries.
Unanswered queries never fall back to a different resolver under the original
provider's name. Ranking excludes incomplete results; a tie yields no unique winner.
DoH validation requires matching DNS contents and the correct HTTP media type.
Live DNS Information and DNS Benchmark screens completed on the phone.

TLS and certificates
PASS: Structured DER parsing supplies actual serials, validity fields, key types
and sizes. Cryptographic verification establishes self-signing; issuer text alone
does not establish trust. System trust checks hostname and chain. Tests cover an
untrusted fixture root, an explicitly anchored per-test chain, and a wrong host.
A failed trust evaluation remains a failure with or without VPN/proxy names.
Untrusted TLS is not accepted to collect a positive result. Version/cipher/handshake
come from one URLSession connection's metrics; redirects are not followed.
Live Quick Check/TLS screens completed. Analyze now dismisses the keyboard.

Discovery and device history
PASS: IPv4 masks are validated; candidate addresses stay within the actual subnet
and a bounded local /24 slice. /31, /32, invalid masks, malformed NetBIOS/SSDP input,
case-insensitive SSDP headers, and real TCP-listener detection are covered.
Cancelled/path-changed scans do not update presence history as completed scans.
Networks are separated in history; anonymous scans do not inherit familiar labels.
Gateways are categorized by their observed route role, never automatically trusted.
Custom names, notes, type assignments, familiar labels, return alerts, settings,
delete/clear operations and persistence are exercised in isolated stores.
The phone completed a real partial LAN scan and recognition/undo workflow.

Stability and privacy
PASS: Unobserved hours are unknown, not green. Continuous uptime is unavailable
because app suspension leaves gaps. Average latency uses observations rather than
only spike events. Signal readings reject invalid values and clear stale current
readings. Egress metadata is not treated as GPS, proven residential identity,
CGNAT topology, or proof of VPN coverage. Unknown privacy checks do not become
confirmed leaks or proof of protection. Duplicate Wi-Fi/VPN scores that could
start at 100 without evidence were removed from the reachable screens.

History and consolidation
PASS: Missing measurements stay absent in aggregates, charts and CSV fields.
Current slow values survive legacy-sentinel migration. Atomic/revision-ordered
storage, corrupt-data backup, migration failure preservation and startup merge
are tested. Detailed Checks reuses the primary tools; independent endpoint checks
replace invented traceroute hops. The Wi-Fi observations card now reads shared
history instead of producing its own score/store. Obsolete implementations are
preserved outside the app target in ArchivedDiagnostics.

REAL IPHONE ACCEPTANCE

Wi-Fi/cellular
PASS: USB connection confirmed; Wi-Fi enabled -> disabled -> enabled was observed
in Settings. Separate throughput samples were measured while retaining the earlier
path's sample. The original Wi-Fi setting was restored. One observed run measured
111.3 Mbps Wi-Fi and 107.7 Mbps cellular. These are momentary application-throughput
samples, not a calibrated capacity guarantee or an overall winner when other
required measurements are absent. The misleading generic connection-error heading
was replaced with the actual comparison reason.

Wi-Fi Assistant
PASS: Real local discovery, recognition and undo, three baseline transfers, three
follow-up transfers, comparison display and reset completed. Observed medians were
114.7 -> 121.2 Mbps (+5.7%); ranges overlapped. The app correctly attributed no cause
and made no guaranteed speed-improvement claim. No router settings were changed.

ACCEPTANCE BOUNDARIES

The completed checks establish the listed behavior in controlled cases and on this
phone/network. They are not an exhaustive certification of every compiler-generated
function, network condition, router model or external service. The per-function
execution inventory separately identifies code this test run did not enter.

No router administration adapters are implemented. Automatic router settings,
restarts and device blocking are unsupported, rather than simulated. Neighbor
Wi-Fi channels, other-app bandwidth, general RF signal/link-rate telemetry, browser
WebRTC behavior and end-to-end VPN leak protection cannot be established by the
current native tests and remain unavailable/unverified. Local discovery is partial;
IP addresses and advertised names do not authenticate ownership. Optional AI advice
is not a measurement source; live third-party AI-provider calls were not certified.
No credentials, router settings, App Store release or Git publication were changed.

EXTENDED VISIBLE-TOOL ACCEPTANCE

PASS: The main Speed tab ran an actual transfer, Streaming rendered bandwidth
estimates with unmeasured playback/realtime fields, VPN Sites completed HTTP
response checks, History rendered the saved observations, Combined Security
completed its parallel checks, and Endpoint Speeds ran real samples over the
active route. The saved app-data JSON was read back from the phone and contained
the real speed-test values with absent latency, rather than an invented zero.

Additional corrections: HTTP errors remain visible in site results and failed
requests have no response-latency value. The former throttle tool now compares
endpoint goodput on either route, including VPN, without asserting an ISP policy.
No fastest-sample number is invented when all samples fail. DoT requires a matching
DNS reply with TCP framing over a trusted TLS connection, not merely an open TLS
port; failed probes establish neither blocking nor plaintext fallback. Combined
Security no longer treats multiple warnings as proof of an unsafe network or a
native IPv6 interface as a measured bypass. Certificate-count categories are
mutually exclusive. Kill-switch guidance no longer treats On-Demand or a failed
page load as proof of protection; current provider instructions and controlled
routing evidence are required.
