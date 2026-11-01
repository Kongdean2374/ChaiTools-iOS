#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -version
swift --version
xcodebuild -showsdks
xcodegen generate
xcodebuild -project ChaiTools.xcodeproj -scheme ChaiTools -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$PWD/build/DerivedData" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP="$PWD/build/DerivedData/Build/Products/Release-iphoneos/ChaiTools.app"
test -s "$APP/ChaiTools"
test -s "$APP/PlugIns/ChaiToolsKeyboard.appex/ChaiToolsKeyboard"
mkdir -p dist
STAGING=$(mktemp -d "$PWD/dist/staging.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/Payload"
/usr/bin/ditto "$APP" "$STAGING/Payload/ChaiTools.app"
(cd "$STAGING" && /usr/bin/zip -qry ChaiTools-unsigned.ipa Payload)
mv "$STAGING/ChaiTools-unsigned.ipa" dist/ChaiTools-unsigned.ipa
bash scripts/verify-ipa.sh dist/ChaiTools-unsigned.ipa
shasum -a 256 dist/ChaiTools-unsigned.ipa > dist/ChaiTools-unsigned.ipa.sha256
