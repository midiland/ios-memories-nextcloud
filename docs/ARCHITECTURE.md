# Memories iOS - Architecture

This document describes the technical architecture of the Memories iOS app, including project structure, data flows, and key design decisions.

---

## 🗂️ Project Structure

The app is organized in a modular Swift package under `MemoriesIOS/Sources/`, with clear separation of concerns:

| Folder | Role | Key Components |
|--------|------|-----------------|
| `App/` | Entry point and composition root | `MemoriesApp` (@main), `RootView` (login ↔ WebView), `SessionTeardown`, `AppConstants`, `AppError`, `Log` |
| `Auth/` | Authentication and credentials | `Credentials`, `CredentialStore` (Keychain), `LoginFlowV2`, `SessionStore` (ObservableObject) |
| `Network/` | Nextcloud communication | `ServerURL` (URL normalization), `NextcloudClient` (describe, Login Flow v2, revocation), `AuthenticatedDownloader`, `URLRequest(url:authorizedFor:)`, `NextcloudModels`, `SemanticVersion` |
| `Offline/` | Signed manifest and snapshot management | `AssetManifest` (describe `?manifest=1`), `DSSEEnvelope` + `TUFTargets` (Memories 10 format), `ManifestVerifier` (Ed25519 via CryptoKit), `ManifestPin` + `ManifestPinStore` (rollback protection), `SnapshotStore` (Application Support/offline), `AppWebPath`, `CSSPathRewriter`, `AssetSyncer` (SHA-256 + TUF length, 8 parallel), `ShellPage`, `OfflineAppLoader` |
| `LocalServer/` | Local HTTP/1.1 server | `LocalHTTPServer` (127.0.0.1:62079), `LocalServerAccess` (port + `local-auth` secret), `HTTPConnection`, `HTTPTypes`, `LocalRouter`, `StaticFiles`, `UpstreamProxy` (streaming relay to Nextcloud) |
| `Web/` | WebView management | `WebViewModel` (owns WKWebView), `WebViewFactory`, `WebNavigationHandler`, `NavigationPolicy`, `BackNavigationRule`, `MemoriesWebView` (UIViewRepresentable), `DebugAutomation` |
| `Downloads/` | Photos library integration | `ZipArchive` (ZIP64 + stored/deflate), `ZipExtractor`, `MediaFile`, `CaptureDate` + `MediaMetadata` (EXIF/QuickTime), `DuplicateFinder` (`PhotoMatcher`), `PhotosSaver`, `PhotosAccessPrompt` |
| `Views/` | SwiftUI components | `LoginView`, `SafariView`, `WebContainerView` (themed background + toasts), `ErrorView`, `ToastView`, `BackButton`, `DownloadProgressView`, `SharePresenter` |
| `Photos/` | Device photos (PhotoKit, read-only) | `LocalTimeline` (actor for local timeline routes), `PhotoLibrary` (permissions, folders), `PhotoMatcher` (device ↔ server deduplication), `PhotoIDs`, `ServerDayClient`, `RemoteCopyStore`, `LocalImageRenderer`, `LocalPhotoSettings` |
| `OnThisDay/` | "On this day" memories | `OnThisDay` (selection), `MemoryCache` (App Group folder, shared with the widget), `MemoryRefresher` + `MemoryRefreshService`, `MemoryTimeline`, `MemoryDeepLink`, `MemoryDay` (see §9) |
| `NativeX/` | NativeX bridge implementation | `NativeXController`, `NativeXPhotoService`, `NativeXHost`, `NativeXLoopbackRouter`, `NativeXShareService`, `NativeXMethod`, `NativeXArguments`, `NativeXResponse`, `WeakScriptMessageProxy` |

The widget extension lives in `MemoriesIOS/Widget/` (`MemoriesWidget`, `NextMemoryIntent`, its own `Localizable.xcstrings`) and compiles a few shared files from `Sources/OnThisDay/`.

**Resources (outside `Sources/`)**
| File | Role |
|------|------|
| `Resources/nativex.js` | Injected at document start; defines `window.nativex`; `__NATIVEX_STATE__` replaced with JSON state |
| `Resources/shell-overrides.css` | CSS overrides for the shell page |
| `Resources/Localizable.xcstrings` | App strings (`sourceLanguage: en`, `fr` translations) |
| `Resources/InfoPlist.xcstrings` | Info.plist strings (`NSLocalNetworkUsageDescription`, app name) |
| `Resources/Assets.xcassets/AppIcon` | App icon (Android launcher logo, white on `#2b94f0`) |

---

## 🔄 Data Flow

The app follows a strict security model: **web files are never loaded directly from the server**. Instead, a local server serves verified snapshots.

### 1. Login Flow
```
URL input → GET /apps/memories/api/describe
  ↓ (Memories installed? version ≥ 9.0.0-rc.1?)
POST /index.php/login/v2
  ↓ (opens SFSafariViewController)
Polling every 3s for 10min → loginName + appPassword
  ↓
Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
```

### 2. Local Mode (Default)
The `127.0.0.1:62079` server serves:
- A local `ShellPage` (HTML shell)
- JS/CSS from a **snapshot** downloaded from `/apps/memories/api/describe?manifest=1`
  - Memories 9: Base64 `jsManifest` + `jsManifestSig` (Ed25519)
  - Memories 10: DSSE envelope (`application/vnd.tuf+json`, TUF targets with `expires` and `version`)
- All other requests are **relayed to Nextcloud** via `UpstreamProxy`:
  - Basic auth with app password
  - `OCS-APIREQUEST` header
  - Session cookies in `HTTPCookieStorage.shared`
  - Streaming with backpressure
  - Network failure → 504 ("offline" for frontend)

**Snapshot behavior:**
- Snapshot present → page shown immediately; update checked in background
  - New snapshot → reload + toast
  - Missing → progress screen, then page
- Access protected by HttpOnly `local-auth` cookie (per-launch secret) + `Host` check
- Background: listener closed on suspend, rebound on same port when active
- If iOS kills WebContent process → reload waits for listener; local connection error retried once (`LocalReloadRule`)
- Entry page: loaded directly at `<webroot>/index.php/apps/memories/` (avoids frontend redirect)
- Server CSS files use relative paths → rewritten on the fly (`CSSPathRewriter`)

### 3. Security: No Remote Loading
**Core principle**: The server is **untrusted for code loading** (same as Android).

Error screens instead of loading from server:
| Error | Trigger | Screen |
|-------|---------|--------|
| `AppError.noSignedManifest` | Missing/unparseable/unverified manifest |
| `AppError.webFilesCorrupted` | File does not match SHA-256 |
| `AppError.localServerUnavailable` | Local server cannot start |

**Update checks:**
- Failed update check → keeps cached snapshot
  - Silently when offline
  - With persistent banner (`UnverifiedUpdateBanner`, closable until next launch) when server files don't verify

### 4. NativeX Bridge (`window.nativex`)
The bridge enables native mode on the frontend:
- Hides Nextcloud header
- Shows mobile header and bottom navigation
- Makes page transparent and sends theme color (`setThemeColor`)
- Paints color behind WebView and in safe areas

**Request routing:**
- `http://127.0.0.1/api/…` calls (fetch and XHR, any port) are diverted in JS to `nativexAsync` handler (`WKScriptMessageHandlerWithReply`)
- Other loopback paths (e.g., HLS segments) reach the local server
- Sharing (`/api/share/url`, `/api/share/blobs`) → iOS share sheet
- Device photos routes → see below

### 5. Device Photos (Local Mode Only, Opt-In)
**Setup flow:**
```
Settings > Device Folders > "Run initial device setup" (/nxsetup)
  ↓ (opened automatically once per install via DeviceSetupRule)
/api/config/allow_media/1 (iOS prompt)
  ↓
/api/days (device-only photo counts)
/api/days/{id} (photos)
/api/image/info/{id} (metadata)
```

**Image serving:**
- Thumbnails/full images on local server:
  - `/image/preview/{fileid}`
  - `/image/full/{auid}`
- Loaded by `<img>` and image worker (not JS bridge)

**Deduplication:**
- For each day, server photos of `day ± 1` are fetched
- `PhotoMatcher` drops device photos that already exist on Nextcloud:
  - Same `auid`/`buid`
  - OR same capture second (or wall clock read as UTC) + aspect ratio (1:1)
- Covers HEIC → JPEG conversion and renaming by Nextcloud app
- Library changes → `nativex:db:updated` + `memories:timeline:soft-refresh`

**File IDs:**
- `fileid` = stable hash of `localIdentifier` in `[2^52, 2^53)`
- File size from `PHAssetResource`'s undocumented `fileSize` key

### 6. Session Management
- Relay sends Basic auth on every request → expired sessions renewed transparently
- Authenticated `describe` (startup or background check) returning 401 or `uid == null` → credentials erased, back to login
- A 401 first triggers a remote-wipe check (see §8): a token marked for wipe is rejected
  with 401 exactly like a revoked password, so the wipe must be detected before the
  Keychain is cleared

### 7. Logout
**Triggers:**
- Settings > Account in web UI (`nativex.logout`)
- Error screen

**Actions:**
- Revoke app password: `DELETE /ocs/v2.php/core/apppassword`
- Clear Keychain + WebView data + relay cookies + local server config
- Snapshots remain on disk

### 8. Remote Wipe (Issue #15)
Supports Nextcloud's remote wipe (Settings → Security → Devices & sessions → "Wipe device").

**Protocol** (Nextcloud `core/Controller/WipeController.php`):
- `POST /index.php/core/wipe/check` with `token=<app password>` (form param, no Basic auth —
  the endpoint is `#[PublicPage]` and the token is the credential)
  - `200 {"wipe": true}` → a wipe is pending
  - `404` → no wipe pending
- `POST /index.php/core/wipe/success` with the same `token` → confirms the wipe
- Rate limit: 10 requests / 5 minutes / IP (`#[AnonRateLimit]`)

**Detection points** (one cheap POST each, well within the rate limit):
1. App startup (`WebViewModel.start` → `SessionStore.checkForRemoteWipe`)
2. Return to foreground (`WebViewModel.appDidBecomeActive` → same). Proactive checks are
   throttled to one per minute (the server allows 10 requests / 5 minutes / IP).
3. On a 401 from `describe` (`SessionStore.sessionRevoked`): the wipe is checked **before**
   the Keychain is cleared, because a wiped token is rejected with 401 and the token is
   needed to call `wipe/check`. `sessionRevoked` is idempotent (`load()` and the background
   refresh can both report the 401).
4. Next launch, for a pending entry (see *Pending wipe*).

Only one wipe runs at a time (`isWiping`): at startup the proactive check and the 401 handler
can both detect the same wipe.

**Flow when a wipe is detected** (`SessionStore.performRemoteWipe`):
1. The credentials are saved in `PendingWipeStore` **before** anything is erased (the purge
   deletes the Keychain credentials: if the app died in between, the confirmation would be lost).
2. The UI goes back to the login screen (message "This device was remotely wiped from
   Nextcloud."), so the web view and its background tasks stop writing to the disk.
3. `DataWiper.run()` erases all local data:
   - `Application Support/offline/` (web snapshots)
   - `Application Support/photos/` (RemoteCopyStore)
   - `temporaryDirectory/` and `Caches/`
   - `URLCache.shared`
   - the app's whole `UserDefaults` persistent domain (any key, present or future)
   - WebView data (`WKWebsiteDataStore`, on the main actor: WebKit crashes when first used
     from another thread), cookies (`HTTPCookieStorage`)
   - Keychain credentials
4. `POST /core/wipe/success` confirms the wipe. `200` and `404` (token already gone) both
   count as confirmed; network errors, `429` and `5xx` do not.
5. `DataWiper.run()` runs a second time (idempotent) to sweep anything a task still in flight
   wrote meanwhile, then the usual session teardown runs.

**Pending wipe** (`PendingWipeStore`, separate Keychain entry): kept when the confirmation
failed, or when a 401 arrived and the wipe check itself failed (network error: the session
still ends, the user is not stuck). On the next launch `SessionStore.resolvePendingWipe`
checks again: wipe requested → purge + confirm; no wipe (plain revocation) → the entry is
deleted. The entry is also deleted after a successful confirmation.

**Limits**: the check only runs while the app is open (no background task): a device that is
offline, or never reopened, is not wiped until the app is launched with network access.

**Not erased**: photos already saved to the iOS Photos library (the app has no right to
erase the user's photo library silently).

---

### 9. "On this day" Widget

A home screen widget (small and medium, unlocked home screen only: no lock screen families) shows
photos taken on this date in past years, in the style of Apple Photos.

- **The widget never sees the credentials and does no networking.** The app prepares the memories
  and the widget only reads them from a folder shared through the App Group
  `group.fr.midiland.memories` (`MemoryCache`: `onthisday/index.json` + thumbnails).
- **Preparation** (`MemoryRefresher`): mirrors the Memories frontend (`dav/onthisday.ts`): one
  `POST api/days` with the day ids around today's date in the last 40 years, grouping by
  anniversary, a seeded pick per year (same photos all day), thumbnails from `api/image/preview`.
  Today and the next 4 days are prepared, so a skipped background refresh stays invisible.
- **Triggers** (`MemoryRefreshService`): app in the foreground (when the cache is incomplete, at
  most every 15 min) and a `BGAppRefreshTask` (`fr.midiland.memories.refresh-memories`, ~12 h,
  actual time chosen by iOS). Nothing is downloaded unless one of our widgets is on a screen.
- **Rotation**: the widget timeline changes photo every 30 min (`MemoryTimeline`).
- **Privacy**: the cache is excluded from backups and erased on logout, revoked credentials and
  remote wipe. Without the App Group entitlement (ad hoc simulator builds) the widget stays empty.

## 🎯 Key Design Decisions

### Platform & Compatibility
- **iOS 16 minimum**: Uses `ObservableObject` (not `@Observable`, which requires iOS 17)
- **Swift 5 language mode**: Full compatibility with iOS 16+

### Local Server vs Alternatives
- **Why local HTTP server on 127.0.0.1?** (vs `WKURLSchemeHandler`)
  - Frontend calls bridge on hard-coded `http://127.0.0.1` (`src/native/api.ts`)
  - `WKURLSchemeHandler` cannot intercept http/https
  - Loopback origin is a **secure context** where media playback works
- **Why not remote mode?**
  - Remote mode (session + `nx_auth` cookies, page loaded from server with NativeX) was removed after maintainer review (pulsejet/memories#998)
  - **Security**: Unsigned code with NativeX is not allowed

### User-Agent & Native Mode
- **User-Agent suffix**: `Version/x.y Mobile/15E148 Safari/604.1 MemoriesNative/1.15 MemoriesIOS/<v>`
  - `Safari/…` avoids Nextcloud's "unsupported browser" page
  - `MemoriesNative/<v>` enables native mode on server (`Util::callerIsNative`)
  - `<v>` must be ≥ `BinExt::NX_VER_MIN` (1.1), otherwise server shows "app too old" page
  - Aligned with Android (1.15)
- **Rule**: `MemoriesNative` and `window.nativex` must **always** be enabled together

### Bridge Implementation
- **127.0.0.1 bridge handled in JS**: `fetch`/`XMLHttpRequest` interception, text responses only
- Does **not** cover `<img>` and workers → device photo images served by local server

### Deduplication Strategy
- **Why metadata, not content hashes?**
  - Server exposes no file hash
  - JPEG conversion is not reproducible byte-for-byte
- **Matching rules**:
  - `auid`/`buid` match
  - OR same capture second + aspect ratio (1:1)

### Navigation
- **Native back button** (`BackNavigationRule`, `BackButton`):
  - In native mode, frontend hides navigation bar outside main tabs
  - Relies on Android's back button for: On this day, Favorites, Videos, Archive, Map, Folders, Search, People/Places/Tags
  - iOS implementation: floating button at bottom left, shown when `canGoBack`
  - Shown outside main tabs (`/`, `/explore`, `/albums`) and without URL fragment (viewer, dialogs)
  - Left-edge swipe does the same
- **Consistency**: `nativex.js` hides web back arrows of cluster headers (matched by `.arrow-left-icon`)

### Minimal `window.OC`
- **Problem**: `AlbumCollaborators.vue` reads `window.OC.config[…]` without optional chaining → empties album share dialogs
- **Solution**: `ShellPage.ocGlobal` provides empty `window.OC` object
- **Future**: Remove once servers ship upstream fix (pulsejet/memories#1748)

### Upload Button
- **Hidden**: `nativex.js` hides mobile header's upload button (`.upload-menu`, `UploadMenuItem.vue`)
- **Reason**: Upload not implemented on iOS yet
- **Exception**: "Upload files" action in Folders view is **not** hidden

### Media Features
- **`playVideo`/`playVideo2`/`destroyVideo` not exposed**: Frontend keeps web player
- **`playTouchSound`**: Mapped to haptic feedback
- **`getPlatform`**: Returns `'ios'` so the frontend picks the App Store link on the setup page (upstream issue pulsejet/memories#1750). `NavigationPolicy` still swaps the hardcoded Play Store link for servers that predate it
- **`downloadFromUrl`**: Download, then:
  - Photos → **Photos app** (originals + album)
  - Videos → **Photos app**
  - Other files → **share sheet**
  - Album ZIP → extracted to Photos, album recreated, no duplicates

### Photos Library
- **Full access required**: Asked after explanation (`PhotosAccessPrompt`)
- **Deduplication**: Same rules as timeline (`PhotoMatcher.Result.matchedServer`)
- **Albums**: Named after Memories album (`title` argument); existing album reused; device copies added too
- **Live Photos**: Saved as two separate items (HEIC + MOV pairs) for now

### Network & Security
- **SFSafariViewController**: Used for Login Flow v2 (no callback scheme)
- **Keychain**: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, single account
- **ATS**: `NSAllowsLocalNetworking` only (http for `.local` servers; IP addresses exempt from ATS)
- **Self-signed certificates**: Not supported yet (Android option not ported)

### UI/UX
- **Status bar**: Style follows system theme, not `isDark` (limitation when forced Nextcloud theme differs from iOS theme)

---

## 📚 See Also
- [Development Setup](../docs/DEVELOPMENT.md) - Build commands and project configuration
- [Testing Guide](../docs/TESTING.md) - Unit tests, fake Nextcloud, Docker setup
- [Releasing](../docs/RELEASING.md) - Versioning and release process
- [Contributing](../docs/CONTRIBUTING.md) - Language policy and guidelines
- [Android Analysis](../ANALYSIS.md) - Deep dive into the Android app
