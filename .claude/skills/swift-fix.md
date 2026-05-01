---
name: swift-fix
description: Fix Swift concurrency and crash issues. Use when debugging crashes or Swift 6 warnings.
---

# Swift Fix Skill

## Common Crash Causes in iOS Apps

### 1. MainActor.assumeIsolated in init()
**Problem**: Crashes during app startup
**Fix**: Remove from init(), access services directly where needed
```swift
// BAD - crashes
private init() {
    networkMonitor = MainActor.assumeIsolated { NetworkMonitorService.shared }
}

// GOOD - safe
private init() {
    // Empty init
}
// Access NetworkMonitorService.shared directly in methods
```

### 2. NSLock in async contexts (Swift 6)
**Problem**: Swift 6 error - locks not safe in async
**Fix**: Use simple boolean flag or actor
```swift
// BAD
private let lock = NSLock()

// GOOD
private var isFetching = false
```

### 3. NEVPNManager without entitlements
**Problem**: Crashes on device, works in simulator
**Fix**: Use optional binding, wrap in try/catch

### 4. CNCopyCurrentNetworkInfo without location permission
**Problem**: Returns nil or crashes
**Fix**: Check CLLocationManager authorization first

### 5. NWPathMonitor lifecycle
**Problem**: Cannot restart after cancel()
**Fix**: Create new instance instead of restarting

## Debugging Tips
- Add CrashLogger to track last activity
- Check console for "APP CRASHED PREVIOUSLY" message
- Test on physical device, not just simulator
