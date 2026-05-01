---
name: ios-build
description: Build and test iOS project. Use when user wants to build, test, or archive the app.
---

# iOS Build Skill

When helping with iOS builds:

## Build Commands
```bash
# Clean build folder
xcodebuild clean -scheme NetoSensei

# Build for simulator
xcodebuild -scheme NetoSensei -destination 'platform=iOS Simulator,name=iPhone 15'

# Build for device (archive)
xcodebuild -scheme NetoSensei -destination 'generic/platform=iOS' archive -archivePath build/NetoSensei.xcarchive

# Run tests
xcodebuild test -scheme NetoSensei -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Common Issues
1. **Signing errors**: Check team ID and provisioning profiles
2. **Swift 6 warnings**: These are warnings, not errors - build will succeed
3. **Entitlements**: VPN features require Network Extension entitlement

## After Build
- Check for warnings in build log
- Verify no Swift concurrency issues
- Test on physical device via TestFlight
