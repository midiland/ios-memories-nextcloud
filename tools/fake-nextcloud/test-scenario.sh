#!/bin/bash
# Runs the iOS app on the "iPhone 16" test simulator against the fake Nextcloud (server.mjs).
# Never use it on the simulator that holds a real account: it replaces the signed-in account.
#
#   tools/fake-nextcloud/test-scenario.sh <scenario> [--fresh] [--build]
#
#   --fresh   uninstall the app first (no cached snapshot: tests the first launch)
#   --build   rebuild the Debug app before installing
#
# Scenarios: valid, unsigned, tampered, dsse, dsse-expired, dsse-tampered, dsse-old, none, wipe (see server.mjs).
#   wipe           a remote wipe is pending for the test app password (issue #15):
#                  the app erases its local data and returns to the login screen.
# Screenshots and the server log go to build16/fake-nextcloud/.
set -euo pipefail

SCENARIO=${1:?usage: test-scenario.sh <scenario> [--fresh] [--build]}
shift
FRESH=false BUILD=false
for arg in "$@"; do
  case $arg in
    --fresh) FRESH=true ;;
    --build) BUILD=true ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PORT=${PORT:-18090}
BUNDLE=fr.midiland.memories
OUT=$ROOT/build16/fake-nextcloud
APP=$ROOT/build16/Build/Products/Debug-iphonesimulator/Memories.app
DEVICE=${DEVICE:-$(xcrun simctl list devices available | grep -m1 -E '^ +iPhone 16 \(' | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}')}
mkdir -p "$OUT"

# 1. Fake server: start it if needed, then select the scenario.
if ! curl -sf "localhost:$PORT/__scenario/$SCENARIO" >/dev/null 2>&1; then
  echo "Starting the fake Nextcloud on port $PORT (log: $OUT/server.log)"
  PORT=$PORT nohup node "$ROOT/tools/fake-nextcloud/server.mjs" >"$OUT/server.log" 2>&1 &
  for _ in $(seq 20); do curl -sf "localhost:$PORT/__scenario/$SCENARIO" >/dev/null 2>&1 && break; sleep 0.25; done
fi
curl -sf "localhost:$PORT/__scenario/$SCENARIO"

# 2. App on the iPhone 16.
if $BUILD || [ ! -d "$APP" ]; then
  xcodebuild -project "$ROOT/MemoriesIOS/MemoriesIOS.xcodeproj" -scheme MemoriesIOS \
    -destination "id=$DEVICE" -derivedDataPath "$ROOT/build16" build -quiet
fi
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a "$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
if $FRESH; then xcrun simctl uninstall "$DEVICE" "$BUNDLE" 2>/dev/null || true; fi
xcrun simctl install "$DEVICE" "$APP"

# 3. Launch signed in to the fake server (debug sign-in, see DebugAutomation.seedCredentials).
SIMCTL_CHILD_MX_SERVER="http://localhost:$PORT" SIMCTL_CHILD_MX_LOGIN=tester SIMCTL_CHILD_MX_APP_PASSWORD=test \
  xcrun simctl launch "$DEVICE" "$BUNDLE" >/dev/null
sleep "${WAIT:-8}"
SUFFIX=""; if $FRESH; then SUFFIX="-fresh"; fi
SHOT="$OUT/$SCENARIO$SUFFIX.png"
xcrun simctl io "$DEVICE" screenshot "$SHOT" >/dev/null 2>&1
echo "Screenshot: $SHOT"
