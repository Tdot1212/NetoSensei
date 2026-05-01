# NetSense Configuration Guide

## Required Xcode Configuration

Since the project uses auto-generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`), you need to configure permissions through Xcode's build settings.

### 1. Add Info.plist Keys

Go to your target → Build Settings → Info.plist Values, or add them in the Info tab:

#### Network Usage Description
```
Key: NSLocalNetworkUsageDescription
Value: NetSense needs access to your local network to diagnose Wi-Fi and router connectivity issues.
```

#### Location Usage Description (for Wi-Fi SSID)
```
Key: NSLocationWhenInUseUsageDescription
Value: NetSense needs location access to identify your Wi-Fi network name (SSID) for diagnostic purposes.
```

### 2. Add Required Capabilities

1. Select your target in Xcode
2. Go to "Signing & Capabilities"
3. Click "+ Capability"
4. Add the following:

#### Access WiFi Information
- This capability is required to read Wi-Fi network information (SSID, BSSID)
- Automatically adds the entitlement: `com.apple.developer.networking.wifi-info`

#### Network Extensions (Optional - For VPN Control)
- Only needed if you want programmatic VPN control
- Requires Apple Developer Program membership
- Requires special approval from Apple
- To request: https://developer.apple.com/contact/request/networking-entitlement/

### 3. App Transport Security (For Speed Tests)

You need to allow network connections to speed test servers.

**Option A: For Development (Easy)**
Add to your target's Info settings:
```
App Transport Security Settings
  └─ Allow Arbitrary Loads = YES
```

**Option B: For Production (Recommended)**
Specify exact domains:
```
App Transport Security Settings
  └─ Exception Domains
      ├─ speed.cloudflare.com
      │   └─ NSExceptionAllowsInsecureHTTPLoads = YES
      ├─ ipapi.co
      │   └─ NSExceptionAllowsInsecureHTTPLoads = YES
      └─ ip-api.com
          └─ NSExceptionAllowsInsecureHTTPLoads = YES
```

### 4. Optional: Background Modes

If you want continuous network monitoring in the background:

1. Add "Background Modes" capability
2. Enable:
   - Background fetch
   - Background processing

### Step-by-Step in Xcode:

#### Adding Info.plist Keys via Info Tab:

1. Select your target → Info tab
2. Hover over any key and click "+"
3. Add each key with its description

#### Adding Info.plist Keys via Build Settings:

1. Select your target → Build Settings
2. Search for "Info.plist"
3. Find "Packaging" section
4. Add custom keys under "Info.plist Values"

Alternatively, you can add them programmatically:

```swift
// In your main app file or a configuration file
// Note: This doesn't actually set Info.plist values at runtime
// You must configure these in Xcode build settings
```

## Testing Permissions

### Location Permission (for Wi-Fi SSID)

When the app first tries to access Wi-Fi information, iOS will show a permission dialog. Make sure to:

1. Request permission at appropriate time
2. Handle denial gracefully
3. Provide fallback functionality

### Local Network Permission

iOS automatically prompts when your app tries to access local network. This happens when:
- Pinging gateway
- Scanning local network
- Accessing router information

## Entitlements File

Your project should have a `NetoSensei.entitlements` file with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.networking.wifi-info</key>
    <true/>

    <!-- Optional: For VPN control -->
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>packet-tunnel-provider</string>
        <string>app-proxy-provider</string>
    </array>
</dict>
</plist>
```

This file is automatically created when you add capabilities in Xcode.

## Verification Checklist

After configuration, verify:

- [ ] Build succeeds without errors
- [ ] Location permission dialog appears when accessing Wi-Fi SSID
- [ ] Local network permission dialog appears when pinging gateway
- [ ] Wi-Fi information is accessible (when permission granted)
- [ ] Speed tests can connect to servers
- [ ] GeoIP lookups work
- [ ] VPN status can be read

## Troubleshooting

### "Wi-Fi information not available"
- Check if "Access WiFi Information" capability is added
- Check if location permission is granted
- Try on real device (simulator has limitations)

### "Cannot connect to speed test server"
- Check App Transport Security settings
- Verify internet connection
- Check firewall settings

### "Build failed: Entitlement error"
- Remove Network Extensions capability if you don't have approval
- Ensure signing certificate is valid
- Check provisioning profile includes required capabilities

## Production Deployment

Before submitting to App Store:

1. Replace "Allow Arbitrary Loads" with specific domain exceptions
2. Implement proper error handling for permission denials
3. Add privacy policy URL in App Store Connect
4. Test on multiple devices and iOS versions
5. Verify all network operations work on cellular and WiFi
6. Test with and without VPN connections
7. Verify behavior when permissions are denied

## API Rate Limits

Be aware of rate limits for free APIs:

- **ip-api.com**: 45 requests/minute
- **ipapi.co**: 1,000 requests/day (free tier)
- **ipinfo.io**: 50,000 requests/month (free tier)

Implement caching and rate limiting in production!
