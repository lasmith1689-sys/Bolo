#!/bin/bash
# Installs the Simulator build, launches it plainly and checks it is still running after 15 s,
# then opens every screen through the -BoloScreen launch argument (canned demo progress, never the
# real progress file), captures screenshots, and fails if the app crashes anywhere.
#   smoke-test.sh <simulator-udid> <path/to/Bolo.app> [output-dir]
set -uo pipefail
UDID="$1"
APP="$2"
OUT="${3:-screenshots}"
mkdir -p "$OUT"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")
failures=0

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"

alive() {
  # Read the whole list first: `| grep -q` exits early, launchctl dies of SIGPIPE, and with
  # pipefail that reads as "not running" even when the app is.
  local services
  services=$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null)
  [[ "$services" == *"UIKitApplication:$BUNDLE"* ]]
}

# 1. A plain first launch, exactly as a new install would start.
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
sleep 15
if alive; then
  echo "Bolo is still running 15 s after a plain launch"
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/00-first-launch.png" >/dev/null 2>&1
else
  echo "::error title=Smoke test::Bolo is not running 15 s after launch"
  failures=$((failures + 1))
fi

# 2. Every screen.
capture() {
  local file="$1" screen="$2" wait="$3"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" -BoloScreen "$screen" >/dev/null
  sleep "$wait"
  if alive; then
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$file.png" >/dev/null 2>&1
    echo "captured $file"
  else
    echo "::error title=Smoke test::Bolo is not running on screen '$screen'"
    failures=$((failures + 1))
  fi
}

n=1
for screen in home teach gloss recognise recall listen assemble miss summary settings; do
  capture "$(printf '%02d' $n)-$screen" "$screen" 6
  n=$((n + 1))
done

if [ "$failures" -gt 0 ]; then
  find ~/Library/Logs/DiagnosticReports -name "Bolo*" -mmin -20 -print -exec head -80 {} \; 2>/dev/null
  exit 1
fi
echo "::notice title=Smoke test::Bolo launched and stayed up for 15 s, and opened all 10 screens without crashing"

echo "::group::App log (errors and faults)"
xcrun simctl spawn "$UDID" log show --last 5m --style compact \
  --predicate "process == \"Bolo\" AND (messageType == error OR messageType == fault)" 2>/dev/null | tail -n 60 || true
echo "::endgroup::"
