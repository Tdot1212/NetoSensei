---
name: testflight
description: Help with TestFlight deployment. Use when uploading to TestFlight or debugging distribution issues.
---

# TestFlight Deployment Skill

## Upload Process

### 1. Archive
```bash
xcodebuild archive \
  -scheme NetoSensei \
  -destination 'generic/platform=iOS' \
  -archivePath build/NetoSensei.xcarchive
```

### 2. Export IPA
```bash
xcodebuild -exportArchive \
  -archivePath build/NetoSensei.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

### 3. Upload via Xcode
- Open Xcode Organizer (Window > Organizer)
- Select archive
- Click "Distribute App"
- Choose "App Store Connect"
- Upload

### 4. Or Upload via CLI
```bash
xcrun altool --upload-app \
  -f build/export/NetoSensei.ipa \
  -t ios \
  -u "apple-id@email.com" \
  -p "@keychain:AC_PASSWORD"
```

## Common Issues

### "App not available" on TestFlight
- Old build expired (90 days max)
- Build still processing (wait 10-30 min)
- Build rejected for compliance
- Need to upload new build

### Build Processing
- Takes 10-30 minutes after upload
- Check App Store Connect for status
- Email notification when ready

### Version/Build Numbers
- Version (CFBundleShortVersionString): User-facing, e.g., "1.0.0"
- Build (CFBundleVersion): Must increment each upload, e.g., "42"

## Quick Check
```bash
# View current version
grep -A1 CFBundleShortVersionString NetoSensei/Info.plist

# View build number
grep -A1 CFBundleVersion NetoSensei/Info.plist
```
