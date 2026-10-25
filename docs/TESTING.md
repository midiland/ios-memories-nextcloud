# Memories iOS - Testing Guide

This document describes how to test the Memories iOS app, including unit tests, debugging tools, and test scenarios.

---

## 🧪 Unit Tests

### Location
- **Path**: `MemoriesIOS/Tests/`
- **Structure**: One folder per source folder (mirrors `MemoriesIOS/Sources/`)
- **Shared data**: `Support/Fixtures.swift`

### Running Tests
```bash
# Run all unit tests on iPhone 16 simulator
xcodebuild -project MemoriesIOS/MemoriesIOS.xcodeproj -scheme MemoriesIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### Guidelines
- **Focus**: Pure logic only (no network, no web view)
- **Add tests**: With every change to pure logic
- **Special case**: `CredentialStoreTests` uses its own Keychain service and **never touches the real account**

### Test Rules
- **Bug fix**: add a regression test that fails without the fix.
- **New logic**: cover the nominal case and edge cases (empty input, invalid format, unrelated input left unchanged).
- **Naming**: `MemoriesIOS/Tests/<Folder>/<Name>Tests.swift` for `MemoriesIOS/Sources/<Folder>/<Name>.swift`, methods `test<Behavior>`.
- **Assertions**: compare whole values (e.g. the full URL), not only some of their parts.
- **Isolation**: `setUp()` runs before each test; never rely on state left by another test.
- **Ship with the fix**: tests go in the same commit as the code (the pre-push hook rejects separate `test:` commits).

### Pre-commit Test Check (optional)
`scripts/pre-commit-test-check.sh` checks staged files under `MemoriesIOS/Sources/`: it fails when one has no test file, and warns when its test file exists but is not staged.
```bash
ln -sf ../../scripts/pre-commit-test-check.sh .git/hooks/pre-commit
```
Use `git commit --no-verify` for code that is not unit-testable (SwiftUI views, platform glue).

---

## 📝 Logging (Debug Builds)

### View Logs
```bash
xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "fr.midiland.memories"'
```
- Output: One line per local server request (`GET /path → status`) + offline-mode events

---

## 🎮 Automated Navigation (Debug Builds Only)

The app supports automated navigation via launch arguments for testing and debugging.

### Basic Commands
```bash
# Open a route and go back after 5 seconds
xcrun simctl launch "iPhone 17 Pro" fr.midiland.memories -MXRoute /thisday -MXBackAfter 5
```

### Available Arguments
| Argument | Description | Example |
|----------|-------------|---------|
| `-MXRoute <path>` | Navigate to a route via `_m.router.push` | `-MXRoute /thisday` |
| `-MXBackAfter <seconds>` | Press back button after delay | `-MXBackAfter 5` |
| `-MXEval "<js>"` | Execute JavaScript and log result | `-MXEval "document.title"` |
| `-MXEvalEvery <seconds> "<js>"` | Repeat JS execution every N seconds | `-MXEvalEvery 2 "location.href"` |
| `-MXClick <selector>` | Click first matching element | `-MXClick .cluster` |

### Notes
- **Memories 10 (Vue 3)**: No longer exposes `_m.router` → use `-MXEval` with DOM clicks instead
  ```bash
  # Example: Open first cluster
  -MXEval "document.querySelectorAll('.p-outer .img-outer')[0].dispatchEvent(new PointerEvent('pointerdown', {pointerType: 'mouse', button: 0, bubbles: true}))"
  ```
- **Combining arguments**: Chain multiple flags for complex workflows
  ```bash
  # Open route, click element, then go back
  -MXRoute /albums -MXClick .album-tile -MXBackAfter 3
  ```

### Simulator for Testing
- **Use dedicated simulators** for screenshots and testing:
  - "iPhone 17 Pro Max" (6.9")
  - "iPad Pro 13-inch (M5)" (13")
- **Never use** the user's "iPhone 17 Pro" for automated testing
- **Override status bar** for screenshots:
  ```bash
  xcrun simctl status_bar <udid> override --time 9:41 ...
  ```

---

## 📱 Device Photos on Simulator

### Granting Photos Access
```bash
# Grant photos access (writes TCC but PhotoKit still reports notDetermined)
xcrun simctl privacy booted grant photos fr.midiland.memories
```
- **Note**: The prompt still requires a **user tap** to fully grant access

### Adding Test Photos
```bash
# Add photos from a directory
xcrun simctl addmedia booted /path/to/photos

# Or drag and drop photos into the simulator
```

### Verifying Saved Downloads
- Photos library is read-only at:
  ```bash
  # Inspect Photos.sqlite (read-only)
  sqlite3 data/Media/PhotoData/Photos.sqlite \
    "SELECT ZADDITIONALASSETATTRIBUTES.ZORIGINALFILENAME, ZGENERICALBUM.ZTITLE FROM ZADDITIONALASSETATTRIBUTES JOIN ZASSET ON ZADDITIONALASSETATTRIBUTES.ZASSET = ZASSET.Z_PK JOIN ZGENERICALBUM ON ZASSET.ZGENERICALBUM = ZGENERICALBUM.Z_PK;"
  ```

### Limitations
- `log stream` stops when app is reinstalled → restart it
- Do not relaunch the app while user is using it in simulator

---

## 🏗️ Fake Nextcloud Server (for Manifest Testing)

### Overview
A **fake Nextcloud server** in Node.js for testing manifest signing and verification.
- **Location**: `tools/fake-nextcloud/`
- **Port**: 18090
- **Manifest**: Signed with development key (Debug builds only)

### Starting the Server
```bash
cd tools/fake-nextcloud
node server.mjs
```

### Running Test Scenarios
```bash
# Syntax
./test-scenario.sh <scenario> [--fresh] [--build]

# Examples
./test-scenario.sh valid            # Valid Memories 9 manifest
./test-scenario.sh unsigned         # Unsigned manifest (should fail)
./test-scenario.sh tampered         # Tampered manifest (should fail)
./test-scenario.sh dsse             # Valid Memories 10 DSSE manifest
./test-scenario.sh dsse-expired     # Expired DSSE manifest
./test-scenario.sh dsse-tampered    # Tampered DSSE manifest
./test-scenario.sh dsse-old         # Older TUF version
./test-scenario.sh none             # No Memories app
./test-scenario.sh wipe             # Remote wipe pending (issue #15)
```

### Scenario Behaviors
| Scenario | Expected Result | Notes |
|----------|-----------------|-------|
| `valid` (Memories 9) | Fake page loads | ✅ |
| `unsigned` | Error screen | ❌ No JS files requested |
| `tampered` | Error screen | ⚠️ JS files **are** requested (tampering detected after load) |
| `dsse` (Memories 10) | Fake page loads | ✅ |
| `dsse-expired` | Error screen | ❌ |
| `dsse-tampered` | Error screen | ⚠️ JS files **are** requested |
| `dsse-old` | Fake page loads | ✅ Older TUF version accepted |
| `none` | Error screen | ❌ |
| `wipe` | Login screen with wipe message | 🧹 App erases local data and confirms the wipe (issue #15) |

### Remote Wipe Scenario (Issue #15)
```bash
# First launch normally, then request a wipe:
./test-scenario.sh valid --fresh    # Sign in and load the app
WAIT=4 ./test-scenario.sh wipe      # Wipe is detected: data erased, back to login
```
The app calls `POST /index.php/core/wipe/check`, erases all local data, calls
`POST /index.php/core/wipe/success`, and shows "This device was remotely wiped from Nextcloud."
on the login screen.

### Advanced Testing
```bash
# Test update scenarios (WAIT=4 after --fresh run)
./test-scenario.sh valid --fresh    # First run: loads valid
WAIT=4 ./test-scenario.sh unsigned  # Second run: keeps previous + shows banner

# Server upgrade test (v9 → v10)
./test-scenario.sh valid --fresh    # v9 valid
WAIT=4 ./test-scenario.sh dsse      # Upgrade to v10: updates to dsse page
```

### Verifying Behavior
- Check `server.log` for requested JS files
- Expected: No JS files requested for `unsigned`, `dsse-expired`, etc.
- Exception: `*tampered` scenarios **do** request JS files (detection happens after load)

---

## 🐳 Real Nextcloud in Docker

For testing with a real Nextcloud instance when Docker is available.

### Starting Nextcloud
```bash
# Start Nextcloud 34 with SQLite
docker run -d --name mx-nc-test -p 18091:80 \
  -e SQLITE_DATABASE=nc \
  -e NEXTCLOUD_ADMIN_USER=tester \
  -e NEXTCLOUD_ADMIN_PASSWORD=yourpassword \
  -e NEXTCLOUD_TRUSTED_DOMAINS=localhost \
  nextcloud:34-apache
```

### Setting Up Memories
```bash
# Extract Memories release tarball into custom_apps
docker exec mx-nc-test mkdir -p /var/www/html/custom_apps
# Copy memories.tar.bz2 into container
# Then enable the app
docker exec mx-nc-test su -s /bin/sh www-data -c "php occ app:enable memories"
```
- Apps in `custom_apps/` are served under `/custom_apps/`, like Nextcloud AIO

### Signing In
```bash
# Sign in the iPhone 16 simulator
SIMCTL_CHILD_MX_SERVER=http://localhost:18091 \
SIMCTL_CHILD_MX_LOGIN=tester \
SIMCTL_CHILD_MX_APP_PASSWORD=yourpassword \
xcrun simctl launch "iPhone 16" fr.midiland.memories
```
- Get app password from: `GET /ocs/v2.php/core/getapppassword` with Basic auth

---

## 🔧 Local Server Testing (Outside Simulator)

The local server can be compiled and tested independently on macOS.

### Compilable Modules
These modules can be compiled with `swiftc` on macOS:
- `LocalServer/`
- `Offline/` (except `SnapshotStore` which requires iOS)
- `Network/` (except parts requiring iOS)
- `Auth/Credentials`
- `App/Log`

### Test Setup
- **Harness**: Custom test harness
- **Fake Nextcloud**: Python-based fake server
- **Testing**: Use `curl` to send requests

---

## 📜 Manifest Formats

The app supports two manifest formats for verifying web assets:

### Memories 9 Format
- **`jsManifest`**: Base64-encoded string
- **`jsManifestSig`**: Ed25519 signature
- **Verification**: Signature checked against hardcoded public key

### Memories 10 Format (DSSE)
- **Format**: DSSE envelope (`application/vnd.tuf+json`)
- **Content**: TUF targets with `expires` and `version` fields
- **Signature**: One signature over DSSE pre-auth encoding
- **Verification**: `DSSEManifestTests` verifies real envelope from 10.0.0 release

### Format Detection
- Recognized by the **shape of `jsManifest`** (not by unsigned `version` field)
- Once DSSE manifest accepted for an account, Memories 9 manifests refused (`ManifestPin`)
- Pin cleared on logout

### Signature Verification
- Manifest signed with default seed of `webpack.manifest-sign-plugin.ts`:
  - **Debug builds**: Must accept
  - **Release builds**: Must reject
- Covered by `ManifestVerifierTests`

---

## 🧬 Bridge JS Testing

### Test Suite
- **Location**: `NativeXScriptTests`
- **Engine**: JavaScriptCore
- **Setup**: Runs real `nativex.js` with fake page (`webkit.messageHandlers`, `fetch`, `XMLHttpRequest`)

### Test Coverage
- Verifies which URLs reach the bridge:
  - ✅ `127.0.0.1/api/…` → reaches bridge
  - ❌ HLS playlists/segments → must reach network
  - ❌ Other loopback paths → must reach network

### Live Inspection
- Use Safari > Develop > Simulator to inspect WebView

---

## 🔄 Listener Lifecycle Testing

### Test Setup
- **`LocalHTTPServerTests`**: Uses real socket on free port
- **Port**: `LocalHTTPServer(preferredPort: 0)` (OS assigns free port)

### Test Cases
- **Suspend → Restart**: Must keep the **same port**
- **Multiple requests**: Verify concurrent handling
- **Error recovery**: Verify 504 responses for offline scenarios

---

## 📌 Quick Reference

| Task | Command | Notes |
|------|---------|-------|
| Run unit tests | `xcodebuild ... test` | iPhone 16 simulator |
| View logs | `log stream --predicate 'subsystem == "fr.midiland.memories"'` | Debug builds |
| Automated nav | `-MXRoute /path -MXBackAfter 5` | Debug builds |
| Fake Nextcloud | `./test-scenario.sh valid` | Port 18090 |
| Docker Nextcloud | `docker run -p 18091:80 nextcloud:34-apache` | Manual setup |
| Grant photos | `simctl privacy booted grant photos` | Requires user tap |
| Add test photos | `simctl addmedia booted /path` | Drag & drop also works |

---

## 🔗 Related Documentation
- [Architecture Overview](../ARCHITECTURE.md) - Technical architecture and data flows
- [Development Setup](../DEVELOPMENT.md) - Build commands and project configuration
- [Contributing Guidelines](../CONTRIBUTING.md) - Language policy and contribution rules
