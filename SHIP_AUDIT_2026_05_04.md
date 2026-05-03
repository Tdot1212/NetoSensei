# NetoSensei Ship-Readiness Audit — 2026-05-04

Read-only audit. No files modified.

---

## 1. Repo state

- **pwd**: `/Users/tosh/Documents/Developer/ios/NetoSensei`
- **Branch**: `main`
- **Remote**: `https://github.com/Tdot1212/NetoSensei.git` (origin, fetch + push)
- **Last commits** (only 2 in repo):
  - `8d61ff8` initial commit from M5
  - `7f1f70f` Initial Commit
- **Working tree**: dirty
  - `?? NetoSensei.xcodeproj/xcuserdata/tosh.xcuserdatad/` — untracked, should be gitignored
- **.gitignore**: **DOES NOT EXIST** — repo has no .gitignore at all

> Contradiction with my background context: prompt assumed prior security-tab merge / six-fix landings would show in commit history. Repo only has 2 commits and is essentially uncommitted since initial push. **All "recent fixes" in code exist locally but have never been recorded as commits.** No way to diff "what changed since last sprint" against git.

---

## 2. Xcode project config

| Setting | Debug | Release |
|---|---|---|
| Bundle ID | `com.toshiki.netosensei` | `com.toshiki.netosensei` |
| Marketing Version | `1.0` | `1.0` |
| Build Number (CURRENT_PROJECT_VERSION) | `19` | `19` |
| Deployment Target | iOS **18.5** | iOS **18.5** |
| Swift Version | **5.0** | **5.0** |
| Code Sign Style | Automatic | Automatic |
| Dev Team ID | `Y9WMMP3XCZ` | `Y9WMMP3XCZ` |
| `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` | **NOT SET** | **NOT SET** |
| Info.plist source | `Info.plist` (manual) | `Info.plist` (manual) |
| `GENERATE_INFOPLIST_FILE` | NO (NetoSensei target uses manual Info.plist) | NO |

- **Xcode version used**: `Xcode 26.4.1 (Build 17E202)` — Xcode 26 ✅
- **iOS SDK installed**: `26.4` (iphoneos + iphonesimulator) — iOS 26 SDK ✅
- **Build target SDK** (from build log): `iPhoneSimulator26.4.sdk`, target `arm64-apple-ios18.5-simulator` — built against iOS 26 SDK ✅
- **Targeted device family**: `1,2` (iPhone + iPad)

> Contradiction with my background context: `.claude/CLAUDE.md` claims "Language: Swift 6, Minimum iOS: iOS 14+". Reality: Swift 5.0 toolchain, iOS 18.5 deployment target. The Swift 6 ssid warning IS still flagged because the compiler is in upcoming-mode for that diagnostic, but the project is Swift 5 mode.

### Entitlements (`NetoSensei/NetoSensei.entitlements`)

| Entitlement | Enabled | Used by code? |
|---|---|---|
| `com.apple.developer.networking.wifi-info` | YES | ✅ Yes (`CNCopyCurrentNetworkInfo` in `NetworkMonitorService.swift:75`, `SmartVPNDetector.swift:1176`) |
| `com.apple.developer.networking.vpn.api` | **COMMENTED OUT** (XML comment block lines 7–12) | Code references `NEVPNManager` extensively, but read-only access does not require this entitlement; profile install is stubbed (`VPNEngine.disconnectVPN()` at line 219–220 just prints a message). |

No leftover/unused entitlements. The commented-out VPN api entitlement is fine for App Store as long as the app doesn't actually try to install VPN profiles (it doesn't).

### Info.plist key gaps (Section 6 also covers these)

- **Missing**: `ITSAppUsesNonExemptEncryption` (R10 fail) — App Store Connect will prompt at every submission and require legal review answers.
- **Missing**: `PrivacyInfo.xcprivacy` — required since May 2024.
- **Present but suspicious**: `NSAppTransportSecurity → NSExceptionDomains → github.com` allows insecure HTTP loads. No source code path actually loads `http://github.com`. Reviewer-rejection bait — remove.

---

## 3. Build health

### Debug (iPhone 17 simulator, iOS 26 SDK)
- **Result**: ✅ BUILD SUCCEEDED
- **Warnings count (raw, includes duplicates from multi-pass compile)**: 35
- **Unique warnings**: 7

### Release (iPhone 17 simulator, iOS 26 SDK)
- **Result**: ✅ BUILD SUCCEEDED
- **Warnings count**: 8
- **Unique warnings**: 7

### Full warning list (deduplicated, both configs)

| File:Line | Category | Message |
|---|---|---|
| `NetoSensei/Services/NetworkMonitorService.swift:313:51` | **Swift 6 concurrency** | reference to captured var 'ssid' in concurrently-executing code; this is an error in the Swift 6 language mode |
| `NetoSensei/Services/ConnectionComparator.swift:745:43` | iOS 16 deprecation | `serviceSubscriberCellularProviders` was deprecated in iOS 16.0: Deprecated with no replacement |
| `NetoSensei/Services/ConnectionComparator.swift:747:43` | iOS 16 deprecation | `carrierName` was deprecated in iOS 16.0: Deprecated; returns '--' at some point in the future |
| `NetoSensei/Views/AIChatView.swift:413:18` | iOS 17 deprecation | `onChange(of:perform:)` was deprecated in iOS 17.0 |
| `NetoSensei/Views/AIChatView.swift:416:18` | iOS 17 deprecation | `onChange(of:perform:)` was deprecated in iOS 17.0 |
| `NetoSensei/Views/AISettingsView.swift:36:22` | iOS 17 deprecation | `onChange(of:perform:)` was deprecated in iOS 17.0 |
| `NetoSensei/Views/AISettingsView.swift:53:26` | iOS 17 deprecation | `onChange(of:perform:)` was deprecated in iOS 17.0 |

- **iOS 26-specific deprecations**: none observed.
- **Swift 6 concurrency warnings**: 1 (the ssid capture, item 3 of pending cleanup — still present).
- **Errors**: 0 in both configs.

> **R14 (Debug+Release both build clean)** is technically a partial pass — both succeed but neither is *warning-free*. None of the warnings break submission; they're all known-harmless deprecation/Swift 6 advisories.

---

## 4. App icon

PNG files in `NetoSensei/Assets.xcassets/AppIcon.appiconset/` (18 total):

```
icon-1024.png            icon-29@3x.png         icon-60@3x.png
icon-20.png              icon-40.png            icon-76.png
icon-20@2x-ipad.png      icon-40@2x-ipad.png    icon-76@2x.png
icon-20@2x.png           icon-40@2x.png         icon-83.5@2x.png
icon-20@3x.png           icon-40@3x.png
icon-29.png              icon-60@2x.png
icon-29@2x-ipad.png
icon-29@2x.png
```

`sips -g all icon-1024.png`:
```
pixelWidth: 1024
pixelHeight: 1024
samplesPerPixel: 3
hasAlpha: no    ← ✅ App Store requirement
space: RGB
```

Contents.json references match files present (manually verified — every "filename" listed in the JSON exists on disk; no orphans). ✅

---

## 5. R1–R20 ship-readiness

| Rule | Status | Evidence |
|---|---|---|
| R1 no hardcoded secrets | ✅ | API keys read from Keychain via `AIKeyManager`. Format hints (`"sk-..."`) only — `AIKeyManager.swift:71-73, 207-211` |
| R2 strings localized | ❌ | 0 uses of `NSLocalizedString` / `String(localized:)` / `LocalizedStringKey`. No `Localizable.strings` or `.xcstrings` file. All UI is hard-coded English. |
| R3 empty states | ⚠️ | Some views have empty states (`AIChatView.noKeyView` at line 101, `CombinedSecurityCheckView.placeholderRow` line 747). Many list views (`DataBrokerListView`, `DeviceHistoryView`, `NetworkHistoryView`) have no explicit empty state for first-launch zero-data scenarios. |
| R4 do-catch on Decodable | ⚠️ | Mixed. 25+ uses of `try? JSONDecoder().decode` (silent failure) — fine for cache reads. `AIChatService.swift:434, 467` and `GeoIPService.swift:153, 236, 297` use proper `do/try/catch`. `SpeedTestEngine.swift:287` and `AdvancedDiagnosticService.swift:454-458` decode with force unwraps. Acceptable but inconsistent. |
| R5 Settings rows wired | ⚠️ | Only an **AI Settings** view exists (`AISettingsView.swift`). No general app Settings, no About screen, no Privacy/Terms links. |
| R6 no print() outside DEBUG | ❌ | **247 `print()` calls** outside of any `#if DEBUG` guard (no `#if DEBUG` blocks exist anywhere in the source). Examples: `NetoSenseiApp.swift:88` ("⚠️ APP CRASHED PREVIOUSLY!"), `SecurityEngine.swift:241,252`, `VPNIntelligenceView.swift:1132,1167`, dozens more. All ship in Release builds. |
| R7 no force unwraps | ❌ | Multiple confirmed force unwraps: `SecurityEngine.swift:169` (`pointer.baseAddress!`), `TracerouteService.swift:263` (`ptr.baseAddress!`), `SpeedTestEngine.swift:287` (`collectedSpeeds.last!`/`first!`), `AdvancedDiagnosticService.swift:454-458` (`speedWithoutVPN!`, `speedWithVPN!`, `latencyWithVPN!`, `latencyWithoutVPN!`), `SecurityScanService.swift:265` (`networkMonitor.currentStatus.localIP!`), `DNSBenchmarkService.swift:470` (`$0.latencyMs!`), `CaptivePortalDetector.swift:66` and `PrivacyShieldService.swift:654` (`URL(...)!`). |
| R8 privacy/terms exist | ❌ | No PrivacyPolicyView, no TermsView, no in-app links to either. App Review will block. |
| R9 reverse-DNS bundle ID | ✅ | `com.toshiki.netosensei` |
| R10 ITSAppUsesNonExemptEncryption=NO | ❌ | Key not present in `Info.plist`. App uses HTTPS to AI vendors and standard TLS — qualifies for the "uses only standard exemptions" answer, but the key must be set. |
| R11 icon 1024 no alpha | ✅ | sips confirmed `hasAlpha: no` |
| R12 permission strings user-friendly | ✅ | `NSLocalNetworkUsageDescription` and `NSLocationWhenInUseUsageDescription` are written in plain user English (`Info.plist:51,67`). |
| R13 .gitignore covers iOS standards | ❌ | **No `.gitignore` exists.** `xcuserdata/` is currently untracked but unprotected; `DerivedData`, `*.xcarchive`, `build/`, `.DS_Store`, etc. are all uncovered. |
| R14 Debug+Release both build clean | ⚠️ | Both build, but with 7 unique warnings (see §3). |
| R15 GitHub secret scanning | — | Repo URL: `https://github.com/Tdot1212/NetoSensei.git` — verify externally. |
| R16 secret files gitignored | ❌ | No `.gitignore`, so any secret files would be committable. The app correctly uses Keychain for runtime secrets, so there are *no* secret files to gitignore today, but the safety net doesn't exist. |
| R17 Secrets.local.swift gitignored / .example committed | N/A | Project does not use a `Secrets.local.swift` convention. Keys are entered at runtime via `AISettingsView` and stored in Keychain. |
| R18 APIKeyManager DEBUG-wrapped fallback | N/A | No APIKeyManager fallback exists — keys come exclusively from Keychain via user input. Cleaner than the rule contemplates. |
| R19 Keychain WhenUnlockedThisDeviceOnly | ❌ | `AIKeyManager.swift:128` uses `kSecAttrAccessibleAfterFirstUnlock`, **not** `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. AfterFirstUnlock allows iCloud backup transfer of items between devices and persists across restarts before unlock — wrong for AI provider credentials. |
| R20 SwiftData NSFileProtectionComplete | N/A | App does not use SwiftData (zero `@Model`/`ModelContainer` references). All persistence is `UserDefaults` + JSON files. No file-protection class explicitly set on JSON writes. |

---

## 6. App Store-specific gates

### iOS 26 SDK build confirmed?
✅ **YES.** Build log shows `-isysroot ...iPhoneSimulator26.4.sdk`. SDK 26.4 is iOS 26.

### Xcode 26 used?
✅ **YES.** `Xcode 26.4.1 / Build 17E202`.

> Both deadline-blockers are clear. The submission will not be auto-rejected for SDK reason.

### PrivacyInfo.xcprivacy
❌ **NOT PRESENT.** No `PrivacyInfo.xcprivacy` anywhere in the project.

This was made mandatory in May 2024 if the app or any third-party SDK uses any of the "required-reason API" categories. NetoSensei uses several:

| Required-reason API category | Code path |
|---|---|
| `NSPrivacyAccessedAPICategoryUserDefaults` | 152 `UserDefaults` references in 20 files |
| `NSPrivacyAccessedAPICategorySystemBootTime` | (search if any service reads `mach_absolute_time` / boot uptime — likely yes given diagnostics nature, but not directly verified in this audit) |
| `NSPrivacyAccessedAPICategoryDiskSpace` | not observed in this audit |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | not observed in this audit |
| `NSPrivacyAccessedAPICategoryActiveKeyboard` | not observed in this audit |

Apple's automated check at upload time will hard-reject without `PrivacyInfo.xcprivacy` if `UserDefaults` is used (it is, heavily). **Submission blocker.**

Tracking domains: none — app does not embed analytics SDKs.

### App Tracking Transparency / IDFA
✅ Not used. Zero references to `AppTrackingTransparency`, `ATTrackingManager`, `IDFA`, `advertisingIdentifier`. No ATT prompt needed.

### NSLocalNetworkUsageDescription
✅ Declared (`Info.plist:51-52`):

> "NetoSensei scans your local network to discover connected devices and diagnose network issues."

Reasonable, user-friendly. Reviewer should accept. Companion `NSBonjourServices` array (lines 53–66) is correctly populated for the discovery types the app actually uses (AirPlay, RAOP, printer/IPP, SMB, AFP, HTTP, SSH, Chromecast, Spotify Connect, HAP).

### UIBackgroundModes
✅ **NOT DECLARED.** No `UIBackgroundModes` key in Info.plist. Good — there's a `BackgroundTaskManager.swift` in the source tree, but with no declared background modes the system will refuse to keep the app alive in the background, so whatever it tries to do is no-op'd. Either fully wire it (and declare modes + justification) or delete the file. Currently unused-but-harmless.

### NSAppTransportSecurity exception domains
- `captive.apple.com` — used by `CaptivePortalDetector.swift:66`, `NetworkBehaviorScanner.swift:66`, `PrivacyShieldService.swift:654`. Legit (captive portal probes are HTTP by design).
- `neverssl.com` — used by `NetworkBehaviorScanner.swift:110, 175, 286` for HTTP-vs-HTTPS comparison. Legit.
- `example.com` — used in `NetworkBehaviorScanner.swift:111`. Reasonable.
- **`github.com`** — declared but never used. Looks like leftover/copy-paste. **Remove before submission** (reviewers query unexplained ATS exceptions).

### Privacy nutrition label inputs (App Privacy in App Store Connect)

Data collection points enumerated:

1. **AI provider HTTP calls (per-request, only if user supplies their own key)**
   - `https://api.openai.com/v1/chat/completions`
   - `https://api.anthropic.com/v1/messages`
   - `https://api.deepseek.com/v1/chat/completions`
   - `https://generativelanguage.googleapis.com/v1beta/models/...`
   - `https://api.groq.com/openai/v1/chat/completions`
   - Payload: user-typed chat messages plus a `AIPreflightCollector` snapshot of network state (IP, ISP, geo, latency, etc.). **This is BYO-key but the data still leaves the device — must be disclosed.**
2. **GeoIP lookups**: `api.ipify.org`, `ipinfo.io`, `ip-api.com`, `ipapi.co`, `ipwho.is` — sends device public IP to all of them.
3. **Network probes**: `captive.apple.com`, `neverssl.com`, `example.com`, `cloudflare-dns.com`, `1.1.1.1`, `8.8.8.8` — outbound connections only (no PII).
4. **Local persistence (not collection)**: chat sessions, scan history, device history, VPN snapshots, opt-out progress — all `UserDefaults` / JSON in app sandbox.

For App Privacy:
- **Data linked to user**: none (no account, no analytics).
- **Data shared with third parties**: only the AI vendor the user selects, only when the user invokes chat. Disclose as "User Content → Linked to user" + "Diagnostics → Linked to user" with purpose "App Functionality".
- **Tracking**: NO.

---

## 7. Pending cleanup verification

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | CoreLocation main-thread warning | **Still present** | `NetoSenseiApp.swift:57` calls `CLLocationManager.locationServicesEnabled()` from the `locationManagerDidChangeAuthorization` delegate (which runs on the main thread). The fix moved this out of `init()` (line 28 comment confirms) but the call still trips the warning when invoked. Move to a background queue or cache `manager.authorizationStatus` only. |
| 2 | cloudflare-dns.com as DNS hijack probe | **Still present** | `NetworkStatus.swift:655, 689`: `domesticTarget: ... "cloudflare-dns.com"`. Also `VPNEngine.swift:129, 137` ping `cloudflare-dns.com`. Stale — used as a probe target (not as a DoH endpoint). Replace with a non-DNS-loaded brand (e.g. `apple.com`). |
| 3 | Swift 6 ssid capture in NetworkMonitorService | **Still present** | `NetworkMonitorService.swift:313:51` — exactly the warning the build emitted. Surrounding code (lines 295–330) captures `var ssid` and reads it inside an `await MainActor.run { ... }` closure; needs to be a `let` snapshot. |
| 4 | VPN false-disconnect on IP lookup timeout | **Still present** | `SmartVPNDetector.swift:491-514` (`getVerifiedPublicIP`): when all 3 IP lookups time out, returns `(nil, [], false)`. That `nil` propagates to `publicIP` at `SmartVPNDetector.swift:444`, and downstream consumers infer "VPN disconnected" from missing IP. Highest-impact item: pollutes the stability/reliability history every time the user is on a slow link. Fix: cache the last good IP and only flip to "disconnected" after N consecutive lookup failures. |
| 5 | proxyFakeRanges duplicated | **Still present (3 files, 4 declarations)** | `Engines/SecurityEngine.swift:62`, `Engines/DNSSecurityScanner.swift:203`, `Services/PrivacyShieldService.swift:697 AND 852` (declared twice in the same file). Identical literal `["198.18.", "198.19.", "100.100.", "10.10.10.", "28.0.0."]`. |
| 6 | Proxy app needles duplicated | **Still present (3 files)** | `Services/TLSAnalyzer.swift:426-432` (`knownProxyCAs`, 11 entries), `Services/CertificateInspector.swift:184-194` (`proxyAppNeedles`, 10 entries), `Services/KillSwitchAdvisor.swift:62+` (`proxyAppSignatures`). All three lists overlap heavily but have drifted (TLSAnalyzer has 11 needles, CertificateInspector has 10 — already out of sync). |
| 7 | TLSAnalyzer.extractIssuer fallback to subject CN | **Still present** | `Services/TLSAnalyzer.swift:660-674`: if no public-CA brand string matches, returns `fallback`, which is the cert summary string (the subject) per call site at line 633. Behavior unchanged. |

All 7 pending items remain. None have been addressed in code yet.

---

## 8. Final verdict

### A. Can NetoSensei be submitted to App Store today?

**❌ NO.**

Blocking items, in priority order with rough hours-of-work estimates:

| # | Blocker | Why it blocks | Est. |
|---|---|---|---|
| 1 | No `PrivacyInfo.xcprivacy` | Apple's upload validator hard-rejects on `UserDefaults` usage without a declared reason since May 2024. | 2–3 h (write + verify) |
| 2 | No Privacy Policy page or URL | App Review consistently rejects apps that send user content to remote APIs without a linked privacy policy. AI chat sends user diagnostic snapshots to OpenAI/Anthropic/etc. | 2–3 h (write policy, host on GitHub Pages, link in Settings) |
| 3 | No Settings/About screen with privacy & terms links | R5 + R8. Reviewer expects links in-app, not just AppStoreConnect URL. | 2–3 h |
| 4 | `ITSAppUsesNonExemptEncryption` not set in Info.plist | Soft-block — Connect prompts on every submission, slows TestFlight. | 5 min |
| 5 | Wrong Keychain accessibility class | Not auto-rejected, but a security audit/MASA review will flag. Fix is one constant change. | 15 min |
| 6 | `github.com` ATS exception domain unused | Reviewer asks "why is HTTP allowed for github.com?" — easier to delete than to defend. | 5 min |
| 7 | App is fundamentally undocumented re: data flow to AI vendors | Without disclosure of what's sent to which third party, App Privacy answers will be wrong → Reviewer rejection. | 1 h (write disclosure copy that matches §6 enumeration) |
| 8 | No `.gitignore` (R13) | Not Apple-blocking, but a junior dev will commit DerivedData / xcuserdata if not fixed before scaling. | 5 min |
| 9 | 247 unguarded `print()` statements (R6) | Not Apple-blocking, but leaks user network state to the device system log in Release. Privacy concern more than submission concern. | 1–2 h (wrap in `#if DEBUG` or replace with `os.Logger`) |

**Total minimum work to unblock submission: ~10–14 hours** spread across items 1–7.

### B. Reviewer-rejection risks (beyond the blockers above)

- **AI Settings is a single nested screen**; reviewer may ask "where do I get an API key?" — `AIKeyManager` does provide signupURL strings, but they're only shown if the user tabs into AI Assist, which requires keys, which then shows `noKeyView`. The flow works; reviewer just needs to be guided in App Review Notes to "open AI Assist tab → tap Add Key → select any provider → tap signup link". Provide demo-account guidance in App Review Notes or risk Guideline 2.1.
- **Hidden 5-tap debug panel** at `DashboardView.swift:113-134` opens `NetworkDebugView`. Reviewers occasionally trigger this and reject it as undisclosed engineering UI. Either fully label it ("Diagnostics → Debug Info") or wrap behind `#if DEBUG`.
- **`NSAppTransportSecurity` exception for `github.com`** — unused, will draw a question.
- **Six tabs**: Home, Diagnose, Speed, Security, AI Assist, History. Borderline — Apple allows up to 5 in a TabView before More-overflow kicks in. iPhone will auto-collapse one into "More" tab, which is OK but ugly. Consider 5.
- **`UIBackgroundModes` not declared, but `BackgroundTaskManager.swift` exists** — if reviewer profiles binary and finds background-related symbol, no harm. Just remove the file or use it.

### C. Functional gaps before shipping

- **No general Settings view, About screen, or onboarding** — first-launch experience drops user straight into Dashboard with no explanation of what NetoSensei does.
- **`VPNEngine.disconnectVPN()` (line 219) is a stub** that prints and returns. Anything in the UI that calls it (e.g. `DiagnosticView.swift:715, 797`) silently fails. Either implement or hide the button.
- **No empty states** for `DataBrokerListView`, `DeviceHistoryView`, `NetworkHistoryView`, `VPNSnapshotView` first-run scenarios.
- **No in-app help/tooltips** for technical screens (TLS Analyzer, Port Scan, Traceroute) — reviewer may ask "what is this for?".
- **Localization**: 0 localized strings. App will ship English-only — fine, but flag in App Store Connect language list.
- **Test target empty**: `NetoSenseiTests` and `NetoSenseiUITests` exist but no real tests written (per pbxproj inspection — only stub files committed). Not Apple-blocking but a smell.

### D. Bloat to consider removing

- 15 markdown design docs at repo root (`STEP1_COMPLETE.md` … `STEP7_COMPLETE.md`, `BUILD_SUMMARY.md`, `CRITICAL_FIXES_*.md`, `PROJECT_COMPLETE.md`, `ADDITIONAL_CRITICAL_FIXES.md`, `CONFIGURATION.md`). Move to `docs/` or delete — reviewers see the repo if open-source, and these files give the impression of an unfinished prototype.
- **`NetoSensei/Utils/`** is empty.
- **`BackgroundTaskManager.swift`** with no declared background modes — dead.
- **Three diagnostic surfaces** (`DiagnoseTabView`, `AdvancedDiagnosticView`, `NewAdvancedDiagnosticView`, `StreamingDiagnosticView`) — at least one is redundant. `NewAdvancedDiagnosticView.swift` exists alongside `AdvancedDiagnosticView.swift`; keeping both means users see two "Advanced Diagnostics" entry points and pick wrong.
- **`NetworkDebugView`** behind 5-tap easter egg — either ship it as a real Settings entry or `#if DEBUG` it.
- **`build/` directory in repo root** — leftover xcodebuild artifact. Add to .gitignore once one exists.
- **CrashLogger** (`NetoSenseiApp.swift:71+`) prints "APP CRASHED PREVIOUSLY!" to console with `print()` — replace with `os.Logger` if kept.
- 6 tabs → 5 tabs by collapsing `Diagnose` + `Speed` (both are diagnostic flows) or moving `History` into a sub-screen of Home.

### E. Minimum work to ship — ordered task list

Each task = 1–2 day unit unless noted.

1. **Day 1** — Add `PrivacyInfo.xcprivacy` (declare UserDefaults + any other required-reason APIs the audit flagged). Add `ITSAppUsesNonExemptEncryption=NO`. Remove unused `github.com` ATS exception. Fix Keychain accessibility class to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Add `.gitignore`. (~4–5 h actual work, day buffer for verification.)
2. **Day 2** — Write Privacy Policy + Terms of Service (or commission), host on GitHub Pages or similar. Add Settings screen with About, Version, Privacy Policy link, Terms link, AI Settings entry, app description, support email.
3. **Day 3** — Wrap all 247 `print()` statements (or replace with `os.Logger` and gate to .debug level). Fix the 7 build warnings (Swift 6 ssid capture, ConnectionComparator deprecations via fallback, modernize 4 onChange call-sites). Fix CoreLocation main-thread warning. Fix VPN false-disconnect on IP lookup timeout (cache last good IP).
4. **Day 4** — Deduplicate `proxyFakeRanges`, proxy app needles, and CA-fallback logic into a single `ProxySignatures.swift` helper. Replace `cloudflare-dns.com` probes with a non-DoH brand. Either implement `VPNEngine.disconnectVPN()` properly or remove the buttons that call it.
5. **Day 5** — Add empty states to list views. Add first-launch onboarding (3 cards: what NetoSensei does, what data leaves the device when AI is used, where to enter API keys). Decide on tab consolidation (5 vs 6).
6. **Day 6** — End-to-end device test (TestFlight internal): Dashboard, all 6 tabs, AI chat round-trip with each provider, scan flows, history persistence across restart.
7. **Day 7** — Buffer day. Submission to App Store Connect, fill App Privacy nutrition label, write App Review Notes including "if testing AI Assist, use [redacted demo key] or follow signup links in-app".

**Total calendar estimate: 7 days solo, assuming no surprises.** Realistic with meetings/interruptions: 10 days.

### F. Contradictions with background context

1. **Filesystem location**: prompt assumed `/Users/tosh/Documents/Developer/ios/NetoSensei/`. Confirmed correct.
2. **Recent state — "Security tab merged into Run Full Security Check, six bug fixes landed"**: `CombinedSecurityCheckView.swift` exists (790 lines), so the merge happened in code. But **no commits** in git history reflect this work — the entire post-initial-commit body of work is uncommitted-since-an-old-tarball-import. Fixes exist locally; their git history does not.
3. **CLAUDE.md claims Swift 6 / iOS 14+**: project actually configured for Swift 5.0 / iOS 18.5. The Swift 6 ssid warning is from the upcoming-feature flag, not from being in Swift 6 mode.
4. **"Six bug fixes from previous prompt landed"**: code reflects them (`isProxyMITMCert`, proxy-aware DNS in WiFi safety, `extractIssuer`, etc. are all present). But cleanup item 1 (CoreLocation main-thread) is only *partly* fixed — moved out of `init()`, still called on main from delegate.
5. **"Pending cleanup items"**: all 7 still present in the codebase as of this audit.
6. **Background context did not flag**: missing PrivacyInfo.xcprivacy, missing ITSAppUsesNonExemptEncryption, no Privacy Policy in-app, no `.gitignore`, no localization, wrong Keychain accessibility class, 247 unwrapped prints. These are larger issues than any of the 7 listed cleanup items.

---

*End of report.*
