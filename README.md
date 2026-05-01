# NetSense - Intelligent Network Diagnostic App for iOS

Version: 1.0 (MVP)

## Overview

NetSense is an intelligent network diagnostic assistant for iOS that identifies the exact cause of slow internet, buffering, or failed connections. The app pinpoints issues caused by Wi-Fi, Router, ISP, VPN, DNS, streaming providers, and CDN routing.

## Features

### ✅ Implemented (MVP)

1. **Real-Time Network Dashboard**
   - Wi-Fi status with signal strength (RSSI)
   - Router reachability and latency
   - Internet connectivity status
   - DNS performance monitoring
   - VPN status and health
   - Traffic-light indicators (Green/Yellow/Red)

2. **Intelligent Diagnostic Engine**
   - Comprehensive connectivity tests
   - VPN health checks
   - Network congestion detection
   - Root cause analysis with decision tree logic
   - Human-friendly explanations

3. **Streaming Diagnostic Mode**
   - Platform-specific tests (Netflix, YouTube, TikTok, etc.)
   - CDN latency and throughput testing
   - VPN impact analysis
   - ISP congestion detection
   - Video quality estimation

4. **One-Tap Fix System**
   - Automated problem detection
   - Single recommended action
   - Quick-fix buttons for common issues
   - System settings integration

5. **VPN Auto-Recovery Engine**
   - Tunnel health monitoring
   - Packet loss detection
   - Latency monitoring
   - Auto-reconnection (when permissions allow)
   - Manual recovery guidance

6. **Speed Test**
   - Download/Upload speed measurement
   - Ping, jitter, and packet loss testing
   - Video quality recommendations
   - Historical tracking

7. **IP Geolocation**
   - Public IP display
   - Location detection
   - ISP information
   - ASN lookup
   - Security flags (Proxy/VPN/CGNAT detection)

8. **History & Analytics**
   - Speed test history
   - Diagnostic results logging
   - Export functionality (CSV)
   - Statistics and trends

## Project Structure

```
NetoSensei/
├── Models/
│   ├── NetworkStatus.swift
│   ├── DiagnosticResult.swift
│   ├── StreamingDiagnosticResult.swift
│   ├── SpeedTestResult.swift
│   └── GeoIPInfo.swift
│
├── Services/
│   ├── NetworkMonitorService.swift
│   ├── DiagnosticEngine.swift
│   ├── StreamingDiagnosticService.swift
│   ├── VPNEngine.swift
│   ├── SpeedTestEngine.swift
│   ├── GeoIPService.swift
│   └── HistoryManager.swift
│
├── Views/
│   ├── DashboardView.swift
│   ├── DiagnosticView.swift
│   ├── StreamingDiagnosticView.swift
│   ├── SpeedTestView.swift
│   └── IPInfoView.swift
│
├── NetoSenseiApp.swift
└── ContentView.swift
```

## Requirements

- **Platform**: iOS 17.0+ / iPadOS 17.0+
- **Language**: Swift 5.0+
- **Framework**: SwiftUI
- **Xcode**: 15.0+

### System Frameworks

- Network Framework
- URLSession
- Combine
- NetworkExtension (for VPN management)
- SystemConfiguration
- CoreLocation (optional, for Wi-Fi SSID)

## Setup Instructions

### 1. Xcode Configuration

1. Open `NetoSensei.xcodeproj` in Xcode
2. Select the NetoSensei target
3. Go to "Signing & Capabilities"

### 2. Required Capabilities

Add the following capabilities:

#### Access WiFi Information
- Required to read Wi-Fi SSID and network info
- Go to Signing & Capabilities → + Capability → "Access WiFi Information"

#### Network Extensions (Optional)
- Only needed if you want full VPN control
- Requires Apple Developer Program membership
- Add: "Network Extensions" capability
- Note: This requires approval from Apple

#### Background Modes (Optional)
- For continuous network monitoring
- Enable "Background fetch" and "Background processing"

### 3. Info.plist Configuration

The following keys are already included in `Info.plist`:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>NetSense needs access to your local network to diagnose Wi-Fi and router connectivity issues.</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>NetSense needs location access to identify your Wi-Fi network name (SSID) for diagnostic purposes.</string>
```

**Important**: For production, replace `NSAllowsArbitraryLoads` with specific domain exceptions for speed test servers.

### 4. Entitlements

The app requires the following entitlements:

#### com.apple.developer.networking.wifi-info
- Allows reading Wi-Fi information (SSID, BSSID)
- Automatically added when you enable "Access WiFi Information" capability

#### com.apple.developer.networking.networkextension (Optional)
- Required for VPN control features
- Requires approval from Apple
- Submit request at: https://developer.apple.com/contact/request/networking-entitlement/

## Building the App

### Debug Build

```bash
cd /Users/toshyagishita/Desktop/NetoSensei
xcodebuild -scheme NetoSensei -configuration Debug
```

### Run on Simulator

```bash
xcodebuild -scheme NetoSensei -destination 'platform=iOS Simulator,name=iPhone 15' test
```

### Run on Device

1. Connect your iOS device
2. Select your device in Xcode
3. Click Run (⌘R)

**Note**: Real device testing is recommended for accurate Wi-Fi and network measurements.

## Known Limitations

### iOS Restrictions

1. **Wi-Fi RSSI**: iOS restricts direct access to Wi-Fi signal strength. The app provides estimates.
   - **Workaround**: Use NEHotspotNetwork API with proper entitlements
   - Requires location permission

2. **VPN Control**: Cannot programmatically control VPN without specific entitlements
   - App provides guidance for manual fixes
   - Full control requires Network Extension entitlement + Apple approval

3. **DNS Modification**: Cannot change system DNS settings programmatically
   - App guides user to System Settings

4. **Router Control**: Cannot restart router remotely
   - App provides instructions for manual restart

5. **Device Count on Network**: Cannot accurately count devices on Wi-Fi
   - App provides estimates based on network behavior

### API Limitations

1. **GeoIP Services**: Using free APIs with rate limits
   - Consider implementing caching
   - For production, use paid APIs (ipapi.com, ipinfo.io)

2. **Speed Test**: Simplified implementation
   - For production, integrate with Ookla, Fast.com, or similar services

3. **CDN Testing**: Basic ping-based testing
   - Full CDN routing analysis requires partnerships with streaming providers

## Testing Checklist

- [ ] Dashboard displays real-time network status
- [ ] Wi-Fi signal indicator updates
- [ ] Router ping test works
- [ ] Internet connectivity detection accurate
- [ ] DNS latency measurement functional
- [ ] VPN status detection works
- [ ] Diagnostic engine identifies issues correctly
- [ ] One-Tap Fix buttons navigate to correct settings
- [ ] Streaming diagnostic tests CDN endpoints
- [ ] Speed test measures download/upload accurately
- [ ] IP geolocation displays correct information
- [ ] History logging persists between app launches
- [ ] All permissions requested appropriately

## Production Considerations

### Before App Store Release

1. **Privacy Policy**: Create comprehensive privacy policy
   - Explain network data collection
   - Clarify IP geolocation usage
   - Detail data retention policies

2. **API Keys**: Secure API keys for GeoIP services
   - Use environment variables
   - Implement API key rotation

3. **Rate Limiting**: Implement rate limiting for:
   - GeoIP lookups
   - Speed tests
   - Diagnostic runs

4. **Error Handling**: Add comprehensive error handling
   - Network timeouts
   - API failures
   - Permission denials

5. **Analytics**: Add analytics for:
   - Feature usage
   - Common issues detected
   - Fix success rates

6. **Localization**: Support multiple languages
   - UI text
   - Error messages
   - Diagnostic explanations

7. **Accessibility**: Ensure VoiceOver support
   - Label all UI elements
   - Provide haptic feedback
   - Support Dynamic Type

### Monetization (Optional)

**Free Tier**:
- Basic diagnostic
- Speed test (3 per day)
- Dashboard monitoring

**Pro Tier** ($4.99/month or $29.99/year):
- Unlimited speed tests
- Streaming diagnostics
- VPN auto-recovery
- Advanced analytics
- History export
- Priority support

## Troubleshooting

### Build Errors

**Error**: "Wi-Fi information entitlement required"
- **Solution**: Add "Access WiFi Information" capability in Xcode

**Error**: "Network Extension entitlement missing"
- **Solution**: This is optional. Remove VPN control features or apply for entitlement from Apple

**Error**: "Location permission not granted"
- **Solution**: Request permission in app, or remove Wi-Fi SSID features

### Runtime Issues

**Issue**: Wi-Fi SSID shows "Not connected" even when connected
- **Cause**: Missing location permission or entitlement
- **Solution**: Grant location permission and ensure "Access WiFi Information" capability is enabled

**Issue**: Speed test shows 0 Mbps
- **Cause**: Network security or firewall blocking test servers
- **Solution**: Check App Transport Security settings in Info.plist

**Issue**: GeoIP shows "0.0.0.0"
- **Cause**: API rate limit or network issue
- **Solution**: Implement caching and retry logic

## Support

For issues or questions:
- Open an issue on GitHub
- Email: support@netsense.app (placeholder)

## License

Copyright © 2025 NetSense. All rights reserved.

## Credits

- **Developer**: T Dot
- **Framework**: SwiftUI
- **APIs Used**:
  - ipapi.co (GeoIP)
  - ip-api.com (GeoIP fallback)
  - ipinfo.io (GeoIP fallback)
  - Cloudflare (Speed test)

---

**Version**: 1.0 MVP
**Last Updated**: December 15, 2025
