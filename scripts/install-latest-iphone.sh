#!/bin/zsh
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
phone_build_root="$project_root/build/PhoneLatest"
mkdir -p "$phone_build_root"
print 'Building the latest local NetoSensei source for iPhone…'
xcodebuild -project "$project_root/NetoSensei.xcodeproj" -scheme NetoSensei -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath "$phone_build_root" -allowProvisioningUpdates build > "$phone_build_root/build.log" 2>&1 || {
  tail -60 "$phone_build_root/build.log"
  exit 1
}
phone_target="${1:-}"
if [[ -z "$phone_target" ]]; then
  xcrun devicectl list devices --json-output "$phone_build_root/devices.json" > /dev/null
  phone_target="$(python3 - "$phone_build_root/devices.json" <<'PY'
import json, sys
state=json.load(open(sys.argv[1]))
devices=[d for d in state.get('result',{}).get('devices',[]) if d.get('connectionProperties',{}).get('tunnelState')=='connected' and d.get('hardwareProperties',{}).get('platform')=='iOS']
if len(devices)!=1:
    print('Connect and unlock one paired iPhone, or pass its device identifier as the first argument.',file=sys.stderr)
    for d in devices:
        print(d.get('deviceProperties',{}).get('name','iPhone')+': '+d['identifier'],file=sys.stderr)
    sys.exit(1)
print(devices[0]['identifier'])
PY
)"
fi
print 'Installing development build. Keep the phone unlocked; Wi-Fi pairing or USB both work.'
xcrun devicectl device install app --device "$phone_target" "$phone_build_root/Build/Products/Debug-iphoneos/NetoSensei.app" --timeout 60
xcrun devicectl device process launch --device "$phone_target" com.toshiki.netosensei --timeout 20
print 'Installed and launched the latest local development build. Nothing was sent to the App Store.'
