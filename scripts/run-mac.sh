#!/bin/zsh
# Build the app for the Mac (Mac Catalyst) and run it, signed locally: no Apple team, no
# provisioning profile, no iCloud. See Config/LocalMac.entitlements for what that build can't do.
#
#   scripts/run-mac.sh            build and open
#   scripts/run-mac.sh --no-open  build only
set -euo pipefail
cd "$(dirname "$0")/.."

derived="${DERIVED_DATA:-build/DerivedDataMac}"
xcodebuild build -scheme FujiCookbook -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$derived" DEVELOPMENT_TEAM= CODE_SIGNING_ALLOWED=NO -quiet

app="$derived/Build/Products/Debug-maccatalyst/FujiCookbook.app"
group=$(/usr/libexec/PlistBuddy -c "Print :FCAppGroupIdentifier" "$app/Contents/Info.plist")
entitlements=$(mktemp -t fujicookbook-entitlements)
sed "s/\$(APP_GROUP_IDENTIFIER)/$group/" Config/LocalMac.entitlements > "$entitlements"

codesign --force --sign - --entitlements "$entitlements" "$app"
rm -f "$entitlements"

echo "Built $app"
[[ "${1:-}" == "--no-open" ]] || open "$app"
