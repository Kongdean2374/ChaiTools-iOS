#!/bin/bash
set -euo pipefail
IPA="${1:-dist/ChaiTools-unsigned.ipa}"
test -s "$IPA"
unzip -t "$IPA"
VERIFY_DIR=$(mktemp -d)
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$IPA" -d "$VERIFY_DIR"
APP="$VERIFY_DIR/Payload/ChaiTools.app"
EXT="$APP/PlugIns/ChaiToolsKeyboard.appex"
for binary in "$APP/ChaiTools" "$EXT/ChaiToolsKeyboard"; do
  test -s "$binary"
  file "$binary"
  file "$binary" | grep -q 'Mach-O.*arm64'
  xcrun vtool -show-build "$binary" | grep -Eq 'platform IOS$'
  if codesign -dv "$binary" 2>/dev/null; then
    echo 'Unexpected signed executable' >&2
    exit 1
  fi
done
python3 - "$APP" "$EXT" <<'PY'
import pathlib, plistlib, sys
app, ext = (pathlib.Path(x) for x in sys.argv[1:])
a = plistlib.loads((app/'Info.plist').read_bytes())
e = plistlib.loads((ext/'Info.plist').read_bytes())
assert a['CFBundleIdentifier'] == 'cc.chaihome.ChaiTools'
assert e['CFBundleIdentifier'] == a['CFBundleIdentifier'] + '.Keyboard'
assert a['CFBundleVersion'] == e['CFBundleVersion']
assert a['CFBundleShortVersionString'] == e['CFBundleShortVersionString']
assert (app/'Assets.car').is_file(), 'Missing compiled icon/brand assets'
assert a.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName') == 'AppIcon', 'Missing primary app icon'
assert e['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.keyboard-service'
assert e['NSExtension']['NSExtensionAttributes']['RequestsOpenAccess'] is True
assert a['SharedAppGroup'] == e['SharedAppGroup']
print('Verified: unsigned iOS arm64 App + keyboard extension, matching version and shared identifiers.')
PY
