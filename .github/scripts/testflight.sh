#!/bin/bash
# Builds Bolo for the App Store and, when App Store Connect credentials are configured, uploads it
# to TestFlight. See TESTFLIGHT.md.
#
# No Mac, certificates or provisioning profiles are needed. Like Xcode Cloud, the archive is
# ad-hoc signed, and Xcode signs it for distribution during export with a cloud-managed
# certificate, using the App Store Connect API key.
#
# Environment:
#   BUILD_NUMBER                  required, e.g. "12.1" (must grow with every upload)
#   APPLE_TEAM_ID, ASC_KEY_ID,    optional; without all four the script stops after a dry-run
#   ASC_ISSUER_ID, ASC_KEY_P8     archive. ASC_KEY_P8 is the text of the AuthKey_XXXX.p8 file.
set -euo pipefail

OUT="${RUNNER_TEMP:-/tmp}/testflight"
ARCHIVE="$OUT/Bolo.xcarchive"
BUNDLE_ID="com.lasmith1689.Bolo"
rm -rf "$OUT"
mkdir -p "$OUT"

if [ ! -d Bolo.xcodeproj ]; then
  command -v xcodegen >/dev/null || brew install xcodegen >/dev/null
  xcodegen generate --quiet
fi

echo "▶ Archiving Bolo $BUNDLE_ID, build $BUILD_NUMBER"
if ! xcodebuild archive \
    -project Bolo.xcodeproj \
    -scheme Bolo \
    -configuration Release \
    -destination generic/platform=iOS \
    -archivePath "$ARCHIVE" \
    -skipPackagePluginValidation \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    PROVISIONING_PROFILE_SPECIFIER= \
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" > "$OUT/archive.log" 2>&1; then
  python3 .github/scripts/annotate_errors.py "$OUT/archive.log" "App Store build"
  echo "::error::The App Store build failed. See the log above."
  exit 1
fi
grep -E "warning:" "$OUT/archive.log" | sort -u | head -20 || true

# The export keeps whatever entitlements the archive carries, so check them now. Bolo uses no
# capabilities (no App Groups, iCloud, push...), so anything beyond the signing basics is a mistake.
app="$ARCHIVE/Products/Applications/Bolo.app"
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)
entitlements_json=$(printf '%s' "$entitlements" | plutil -convert json -o - - 2>/dev/null || echo "{}")
echo "Entitlements of Bolo.app: $entitlements_json"
unexpected=$(printf '%s' "$entitlements_json" | python3 -c '
import json, sys
allowed = {"application-identifier", "com.apple.developer.team-identifier", "get-task-allow", "keychain-access-groups"}
try:
    keys = set(json.load(sys.stdin))
except Exception:
    keys = set()
print(" ".join(sorted(keys - allowed)))')
if [ -n "$unexpected" ]; then
  echo "::error::Bolo.app carries entitlements it should not need: $unexpected"
  exit 1
fi

info=$(plutil -p "$app/Info.plist")
echo "$info" | grep -E '"CFBundleIdentifier"|"CFBundleShortVersionString"|"CFBundleVersion"|"CFBundleDisplayName"|ITSAppUsesNonExemptEncryption|UIDeviceFamily|MinimumOSVersion' || true
if ! echo "$info" | grep -q "\"CFBundleIdentifier\" => \"$BUNDLE_ID\""; then
  echo "::error::The archive's bundle ID is not $BUNDLE_ID."
  exit 1
fi
icon=$(find "$app" -maxdepth 1 -name 'AppIcon*.png' | head -1)
if [ -z "$icon" ] && [ ! -f "$app/Assets.car" ]; then
  echo "::error::The archive has no app icon."
  exit 1
fi
fonts=$(find "$app" -maxdepth 1 -name '*.ttf' | wc -l | tr -d ' ')
clips=$(find "$app/Audio" -name '*.m4a' 2>/dev/null | wc -l | tr -d ' ')
echo "Bundled fonts: $fonts, recorded clips: $clips"

if [ -z "${APPLE_TEAM_ID:-}" ] || [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ -z "${ASC_KEY_P8:-}" ]; then
  echo "::notice title=App Store build::Archive OK ($BUNDLE_ID, build $BUILD_NUMBER, entitlements: none beyond signing, $fonts fonts, $clips clips). Nothing was uploaded: add the App Store Connect secrets (see TESTFLIGHT.md) to send builds to TestFlight."
  exit 0
fi

key="$OUT/AuthKey_$ASC_KEY_ID.p8"
# Accept the .p8 text however it was pasted: Windows line endings, or without the BEGIN/END lines.
p8=$(printf '%s' "$ASC_KEY_P8" | tr -d '\r')
if [[ "$p8" != *"BEGIN PRIVATE KEY"* ]]; then
  p8=$(printf -- '-----BEGIN PRIVATE KEY-----\n%s\n-----END PRIVATE KEY-----' "$(printf '%s' "$p8" | tr -d ' \n' | fold -w 64)")
fi
(umask 077 && printf '%s\n' "$p8" > "$key")
unset p8
trap 'rm -f "$key"' EXIT

cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$APPLE_TEAM_ID</string>
	<key>testFlightInternalTestingOnly</key>
	<true/>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

echo "▶ Signing and uploading to App Store Connect"
if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/export" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$key" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$OUT/export.log" 2>&1; then
  tail -n 60 "$OUT/export.log"
  log=$(cat "$OUT/export.log")
  hint="See TESTFLIGHT.md."
  case "$log" in
    *"No suitable application records"*|*"Cannot determine the Apple ID from Bundle ID"*)
      hint="App Store Connect has no app with bundle ID $BUNDLE_ID. Create it (TESTFLIGHT.md)." ;;
    *"NOT_AUTHORIZED"*|*"not authorized"*|*"credentials are missing or invalid"*|*"loud signing permission"*|*"does not have permission"*|*"invalid key"*|*"Invalid key"*)
      hint="Check the API key: it needs the Admin role, and ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 must all come from that key (TESTFLIGHT.md)." ;;
    *"bundle version must be higher"*)
      hint="That build number was already used. Run the workflow again to get a new one." ;;
  esac
  echo "::error::Upload to TestFlight failed. $hint"
  exit 1
fi
grep -iE "upload|success|export" "$OUT/export.log" | tail -n 5 || true
echo "::notice::Uploaded Bolo build $BUILD_NUMBER. It shows up in TestFlight once Apple finishes processing it, usually within 5 to 30 minutes."
