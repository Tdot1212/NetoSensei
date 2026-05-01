# NetoSensei iOS Project

## Overview
Network diagnostic and security analysis iOS app built with SwiftUI.

## Tech Stack
- **Language**: Swift 6
- **UI Framework**: SwiftUI
- **Minimum iOS**: iOS 14+
- **Architecture**: MVVM with singleton services

## Project Structure
```
NetoSensei/
├── NetoSenseiApp.swift      # App entry point, service initialization
├── Services/                 # Singleton services
│   ├── NetworkMonitorService.swift   # NWPathMonitor, network status
│   ├── DiagnosticEngine.swift        # Network diagnostics
│   ├── StreamingDiagnosticService.swift  # CDN/streaming tests
│   ├── GeoIPService.swift            # Public IP geolocation
│   ├── VPNEngine.swift               # VPN detection/management
│   ├── SpeedTestEngine.swift         # Download/upload speed tests
│   ├── SecurityScanService.swift     # Security scanning
│   └── AdvancedDiagnosticService.swift
├── ViewModels/              # MVVM view models
├── Views/                   # SwiftUI views
├── Models/                  # Data models (Codable structs)
├── Engines/                 # Specialized scanning engines
└── Helpers/                 # Extensions, constants
```

## Key Patterns
- **Singletons**: Services use `.shared` pattern
- **Async/Await**: All network operations use Swift concurrency
- **MainActor**: UI updates isolated to main thread
- **ObservableObject**: Services publish state changes

## Important Considerations
- **Location Permission**: Required for WiFi SSID access (iOS 13+)
- **VPN Entitlements**: NEVPNManager requires Network Extension entitlement
- **Swift 6 Concurrency**: Avoid `MainActor.assumeIsolated` in init()
- **Physical Device**: Some APIs behave differently on simulator vs device

## Build Commands
```bash
# Build for device
xcodebuild -scheme NetoSensei -destination 'generic/platform=iOS'

# Run tests
xcodebuild test -scheme NetoSensei -destination 'platform=iOS Simulator,name=iPhone 15'

# Archive for release
xcodebuild archive -scheme NetoSensei -archivePath build/NetoSensei.xcarchive
```

## Common Issues
1. **Crashes on device but not simulator**: Check entitlements and location permissions
2. **WiFi SSID not showing**: Needs location permission granted
3. **VPN detection fails**: NEVPNManager requires proper entitlements
4. **Swift 6 warnings**: Use `@MainActor` class annotation, avoid NSLock in async
