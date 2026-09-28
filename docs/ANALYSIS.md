# Analysis of the Memories Android app → iOS port

Analyzed reference: `reference/memories` (`--depth 1` clone of `pulsejet/memories`,
commit `20ffc54`, 2026-09-28, branch after `v9.1.0-alpha.2`).
Android code: `reference/memories/android/app/src/main/java/gallery/memories/`.

---

## 0. Main finding: it is no longer a simple "WebView → server" wrapper

The initial assumption ("a WebView that loads the UI from the server + `shouldInterceptRequest`")
matches **older** versions of the app. The current version is different:

- **No `shouldInterceptRequest`** anywhere in the code (checked with grep).
- The app embeds a **local Ktor/CIO HTTP server** on `http://127.0.0.1:62079`
  (`server/LocalHttpServer.kt`). The WebView **never** loads a page from the Nextcloud server:
  it loads everything from `127.0.0.1`.
- Memories' JS/CSS files are **downloaded and cached** (an "offline snapshot")
  from an **Ed25519-signed** manifest returned by `GET …/apps/memories/api/describe?manifest=1`
  (`data/remote/assets/*`, `ManifestVerifier.kt`).
- The HTML page is a **locally generated "shell"** (`server/shell/ShellPage.kt`) that mimics
  Nextcloud's PHP template (`_oc_webroot`, `_oc_capabilities`, CSS, l10n, nonce-based CSP).
- All other requests (Memories API, WebDAV, OCS…) are **proxied** to Nextcloud by
  the local server, which adds `Authorization: Basic` + `OCS-APIREQUEST: true`
  (`server/controllers/ProxyController.kt`). The JS is therefore always *same-origin*.
- The `/api/*` and `/image/*` routes on 127.0.0.1 are the **asynchronous NativeX bridge**
  (`bridge/ApiRouter.kt`); `/video/full/{id}` serves local videos with `Range` support.

Consequence: "authenticated the same way as Android" = *the native side injects the credentials
into every request*; the WebView itself never holds a Nextcloud session cookie.

---

## 1. WebView configuration

Files: `ui/web/WebViewSetup.kt`, `MainActivity.kt`, `ui/web/MemoriesWebViewClient.kt`,
`ui/web/MemoriesWebChromeClient.kt`, `ui/startup/AppStartupCoordinator.kt`.

| Setting | Value |
|---|---|
| JavaScript | enabled |
| DOM storage | enabled |
| Popups / multiple windows | disabled (`window.open` falls through to `shouldOverrideUrlLoading`) |
| Zoom | disabled |
| User-Agent | `MemoriesNative/<version> ` + default UA |
| Background | transparent (the native theme is painted behind it) |
| JS interface | `addJavascriptInterface(NativeX, "nativex")` → `window.nativex` |
| Debug | `setWebContentsDebuggingEnabled(true)` in debug builds |
| Cookie | HttpOnly cookie `local-auth=<per-process uuid>` set on `http://127.0.0.1/` **before** the first load; the local server rejects (403) any request without it |

### Loaded URLs (`AppStartupCoordinator`)
1. Not logged in → `http://127.0.0.1:62079/local/static/welcome.html` (page bundled in the APK).
2. Logged in + cached snapshot → `http://127.0.0.1:62079<webroot>/` (local shell),
   followed by an update check in the background.
3. Logged in without a snapshot → `…/local/static/waiting.html` (progress via `/api/assets/progress`),
   then the shell.
4. After a login → `…<webroot>/index.php/apps/memories/nxsetup` (native setup screen).

### Navigation (`MemoriesWebViewClient`)
- Only loopback pages stay in the WebView; any other link opens in the browser.
- A loopback path that matches a *proxied* path is "unwrapped" to the real server URL
  and opened externally (`LocalHttpServer.browserUrlFor`).
- `data:`, `blob:`, `javascript:` as top-level navigations: blocked.
- Network / HTTP errors on the main frame → toast.
- SSL error: `proceed()` only if the user ticked "trust all certificates".
- `WebChromeClient`: grants all permissions, file chooser for uploads,
  transparent video poster.

---

## 2. Nextcloud login

Files: `assets/welcome.html`, `auth/AccountManager.kt`, `data/remote/http/*`,
`data/local/secure/SecureCredentialStore.kt`.

**Yes, it is Login Flow v2.** Sequence:

1. `welcome.html` normalizes the entered URL: adds `https://` if missing, `/`, `index.php/`
   then `apps/memories/` → e.g. `https://cloud.example.com/index.php/apps/memories/`.
2. The JS calls the bridge: `GET /api/login/{doubly encoded url}?trustAll=0|1`.
3. Native: `GET <url>api/describe?manifest=1` → checks for 200 + the manifest signature,
   reads `baseUrl` and `loginFlowUrl` (= `/index.php/login/v2`). Starts the asset sync.
4. `POST loginFlowUrl` → `{ poll: { token, endpoint }, login }`.
5. Opens `login` in the **system browser** (`Intent.ACTION_VIEW`), shows `waiting.html?login=1`.
6. Polling thread: `POST poll.endpoint` with `token=…` every **3 s** for **10 min**
   (the comment says 30 min, the code does 10). 200 → `{ server, loginName, appPassword }`.
   A "generation" counter invalidates stale polls (retry/logout).
7. Storage: `SharedPreferences` with the URL, `trustAll`, plaintext username + **encrypted token**
   (AES/CBC, key in the Android Keystore).
8. On startup: `checkCredentialsAndVersion()` → `GET api/describe`; 401 or `uid == null`
   → logout; version < `9.0.0-rc.1` → warning.

**Credential usage**: `Authorization: Basic base64(loginName:appPassword)` header on
every proxied request. In addition, a persistent `SessionCookieJar` sends back the `oc*` cookies
it received: the internal docs measure ~1 s/request with Basic alone vs ~0.06 s with a session (×17).

**Logout**: `nativex.logout()` (called by the JS after `GET /logout`) → clears credentials and
cookies, reloads `welcome.html`.

---

## 3. Methods exposed via `addJavascriptInterface` (`NativeX.kt`)

All `@JavascriptInterface` methods are **synchronous on the JS side** (the JS thread blocks
until they return). The "Return value used" column indicates whether the JS actually needs the value.

| # | Kotlin signature | Return value used by the JS? | Behavior |
|---|---|---|---|
| 1 | `isNative(): Boolean` | yes (but only the existence of `window.nativex` is checked) | `true` |
| 2 | `setThemeColor(color: String?, isDark: Boolean)` | no | system bar color; remembered once per login |
| 3 | `playTouchSound()` | no | click sound |
| 4 | `toast(message: String, long: Boolean = false)` | no | native toast |
| 5 | `logout()` | no | clears credentials, back to welcome |
| 6 | `reload()` | no | reloads the default URL |
| 7 | `downloadFromUrl(url: String?, filename: String?, title: String?)` | no | background download + notification |
| 8 | `setShareBlobs(objects: String?)` | no, **but must take effect before** the `GET /api/share/blobs` that immediately follows | JSON `[{auid, href}]` |
| 9 | `playVideo(auid: String, fileid: Long, urlsArray: String)` | no | alias for `playVideo2(…, false)` |
| 10 | `playVideo2(auid: String, fileid: Long, urlsArray: String, loop: Boolean = false)` | no | native ExoPlayer overlay; local file if the AUID is indexed, otherwise the 1st URL |
| 11 | `destroyVideo(fileid: Long)` | no | closes the player if the `fileid` matches |
| 12 | `configSetLocalFolders(json: String?)` | no | local folders shown in the timeline |
| 13 | `configGetLocalFolders(): String` | **YES, synchronous** | JSON `[{id, name, enabled}]` |
| 14 | `configHasMediaPermission(): Boolean` | **YES, synchronous** | user opt-in AND OS permission |
| 15 | `getSyncStatus(): Int` | **YES, synchronous** (declared in `api.ts`) | number of indexed files, `-1` if not syncing |
| 16 | `setHasRemote(auids: String, buids: String, value: Boolean)` | no | marks local files as present on the server |

The JS also checks `typeof nativex?.playVideo2 === 'function'`: every function must
**actually exist** on the object (no naive "catch-all" proxy).

### Asynchronous HTTP bridge (`/api/*`, `/image/*`, `/video/*` on 127.0.0.1) — `ApiRouter.kt`

GET only (+ OPTIONS), CORS headers `*`, errors → 500 `{}`.

| Route | Purpose |
|---|---|
| `/api/login/{url}` `?trustAll` | starts the login (§2) |
| `/api/days` | days containing local photos (`IDay[]`) |
| `/api/days/{dayId}` | local photos for one day (`IPhoto[]`) |
| `/api/image/info/{fileId}` | metadata (`IImageInfo`) |
| `/api/image/delete/{auid,…}` `?dry` | local deletion (system dialog) |
| `/image/preview/{fileId}` `?x&y` | JPEG thumbnail (7-day cache) |
| `/image/full/{auid}` `?size` | full-size JPEG image |
| `/video/full/{fileId}` | local video stream, supports `Range` |
| `/api/upload/local` `?auid&filename` | native WebDAV upload of a local file |
| `/api/share/url/{url}` | share sheet for a URL |
| `/api/share/blobs` | downloads the blobs set by `setShareBlobs`, then shares them |
| `/api/config/allow_media/{0|1}` | requests media permission + full sync |
| `/api/assets/progress` | asset download progress |

### Native → JS
`evaluateJavascript("window._nc_event_bus?.emit('<event>', <data>)")` with, notably,
`nativex:db:updated` and `memories:timeline:soft-refresh` (local index changed), deferred while the app
is paused (`ui/web/JsEventBus.kt`).

---

## 4. Request interception

There is **no** `shouldInterceptRequest`. Its role is played by the local server
(`server/ServerRouter.kt`), in this order:

1. Missing `local-auth` cookie → 403.
2. `/video/full/\d+` → local video (Range).
3. `/api/*`, `/image/*` → NativeX bridge (works even when not logged in).
4. `/local/static/*` → bundled files (welcome, waiting, override CSS).
5. `/local/assets/js|css/*` → snapshot files; any other `/local/*` → 404.
6. `/favicon.ico` → local 404.
7. `<webroot>/(index.php/)apps/memories/js/*` via GET → served from the snapshot.
8. Entry point (`/`, `<webroot>/`) or app route accepting `text/html` → **local shell**.
9. Any other document navigation → 404 (remote HTML is never rendered as a local page).
10. Otherwise → **proxy** to Nextcloud (all verbs, including PROPFIND/REPORT/SEARCH),
    `Location` rewriting, network down → 504 (the frontend interprets it as "offline").

---

## 5. Frontend side (`reference/memories/src/native/`)

- **Detection**: `src/native/api.ts` → `export const nativex = globalThis.nativex`;
  `has()` = `!!nativex`. Evaluated **at module load time**: `window.nativex` must exist
  **before** the bundle runs (→ `WKUserScript` at `.atDocumentStart`).
- **Bridge URL**: `BASE_URL = location.hostname === '127.0.0.1' ? location.origin : 'http://127.0.0.1'`.
  ⇒ the asynchronous bridge is **hard-coded to 127.0.0.1**.
- `initialize()` (called by `main.ts`): disables the "unsupported browser" alert,
  `initShellSync()` (language/locale/bundled l10n), listens to the system theme.
- Service worker disabled when `has()`.

| JS function | File | NativeX call |
|---|---|---|
| `setTheme()` | `basic.ts` (App, FirstStart, Viewer, Setup) | `setThemeColor` |
| `playTouchSound()` | `basic.ts` (MobileNav, Cluster, Viewer, SelectionManager) | `playTouchSound` |
| `logout()` | `basic.ts` (Settings) | `GET /logout` then `nativex.logout()` |
| `getLocalFolders / setLocalFolders` | `config.ts` (Settings, Setup) | `configGetLocalFolders` (sync) / `configSetLocalFolders` |
| `configHasMediaPermission()` | `config.ts` (Setup) | sync |
| `configAllowMedia()` | `config.ts` | `fetch NAPI.CONFIG_ALLOW_MEDIA` |
| `getLocalDays / getLocalDay / processFreshServerDay` | `days.ts` (Timeline) | `NAPI.DAYS`, `NAPI.DAY`, `setHasRemote` |
| `deleteLocalPhotos` | `days.ts` (dav/base.ts) | `NAPI.IMAGE_DELETE` |
| Local image URLs | `services/utils/helpers.ts` | `NAPI.IMAGE_PREVIEW/FULL/INFO` |
| `playVideo / destroyVideo / getLocalVideoUrl` | `video.ts` (PsVideo) | `playVideo2`/`playVideo`, `destroyVideo`, `NAPI.VIDEO_FULL` |
| `downloadFromUrl` | `share.ts` (dav/download.ts) | `downloadFromUrl` |
| `shareUrl` | `share.ts` (NodeShareModal, AlbumCollaborators) | `NAPI.SHARE_URL` |
| `shareBlobs` | `share.ts` (ShareModal) | `setShareBlobs` then `NAPI.SHARE_BLOBS` |
| Local upload | `UploadModal.vue` | `NAPI.UPLOAD_LOCAL` |

---

## 6. Proposed Android → iOS mapping

| Android | Proposed iOS |
|---|---|
| `WebView` + settings | `WKWebView` in a `UIViewRepresentable`, shared `WKWebViewConfiguration`, `customUserAgent = "MemoriesNative/<v> …"`, `isInspectable = true` in Debug (iOS 16.4+) |
| `addJavascriptInterface(…,"nativex")` | `WKUserScript` (`.atDocumentStart`, main frame) that defines `window.nativex` in JS; each method calls `webkit.messageHandlers.nativex.postMessage({method, args})` |
| Sync methods (`configGetLocalFolders`, `configHasMediaPermission`, `getSyncStatus`, `isNative`) | Values **cached on the JS side**: injected at document-start, then refreshed via `evaluateJavaScript` when they change. Possible fallback: the `prompt()` trick + `WKUIDelegate.runJavaScriptTextInputPanel` (truly blocking) |
| Ktor server on 127.0.0.1 (bridge + proxy + shell) | Option A: `WKURLSchemeHandler` on a custom `memories-app://` scheme; Option B: small local HTTP server (`Network.framework`/`NWListener`) on 127.0.0.1 + `NSAllowsLocalNetworking` (see §7) |
| `local-auth` cookie | `WKHTTPCookieStore.setCookie` before the first `load` (option B); unnecessary with option A |
| `SecureCredentialStore` (Keystore) | **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) |
| `SessionCookieJar` | `HTTPCookieStorage` of a dedicated `URLSession` (persistent by default) |
| Login Flow v2 + system browser | `ASWebAuthenticationSession` (or `SFSafariViewController`) + async/await `URLSession` polling |
| `trustAll` (self-signed certificates) | `URLSessionDelegate` (serverTrust challenge) + `WKNavigationDelegate.didReceive challenge` — avoid/postpone (explicit option) |
| `welcome.html` / `waiting.html` | Native **SwiftUI** screens |
| `setThemeColor` | background color + `preferredColorScheme` / status bar style |
| `playTouchSound` | `UIDevice.current.playInputClick()` (requires `UIInputViewAudioFeedback`) or `UIImpactFeedbackGenerator` |
| `toast` | temporary SwiftUI overlay |
| `logout` / `reload` | callbacks to the SwiftUI `SessionStore` |
| `downloadFromUrl` | `URLSession` download → `UIActivityViewController` / save to Photos (`PHPhotoLibrary`) |
| `setShareBlobs` + `/api/share/blobs`, `/api/share/url` | `UIActivityViewController` |
| `playVideo2` / `destroyVideo` (ExoPlayer) | `AVPlayerViewController` or an overlaid `AVPlayerLayer`; or let the HTML `<video>` play (WebKit plays HLS natively) |
| MediaStore (`/api/days`, `/image/*`, `/video/full`) | **PhotoKit**: `PHAsset.fetchAssets`, `PHImageManager` (thumbnails/full size), `PHAssetResource` / `requestAVAsset` (video) |
| Room (local index) | SQLite (GRDB) or SwiftData/Core Data — index mapping `PHAsset.localIdentifier` ↔ numeric id ↔ AUID/BUID |
| `/api/image/delete` (system dialog) | `PHAssetChangeRequest.deleteAssets` (iOS shows its own confirmation) |
| `/api/upload/local` | `URLSession` WebDAV upload (`PUT remote.php/dav/files/<uid>/…`) from a file exported from the `PHAsset` |
| `nativex:db:updated` via `evaluateJavascript` | `PHPhotoLibraryChangeObserver` → `webView.evaluateJavaScript("window._nc_event_bus?.emit(…)")` |
| Media permissions | `PHPhotoLibrary.requestAuthorization(for: .readWrite)` (+ limited access) |
| File chooser (`onShowFileChooser`) | handled natively by WKWebView (`<input type=file>`) |
| Android back button | swipe gesture (`allowsBackForwardNavigationGestures`) |

---

## 7. Challenges and decisions to make

### 7.1 Synchronous calls are impossible with `WKScriptMessageHandler`
`postMessage` is asynchronous; `WKScriptMessageHandlerWithReply` returns a **Promise**, not a
value. Yet `configGetLocalFolders()`, `configHasMediaPermission()`, `getSyncStatus()` are read
synchronously (`JSON.parse(nativex.configGetLocalFolders())`).
→ **Chosen solution**: the JS object keeps a cache (`window.nativex._state`) filled at
document-start by the native side and updated via `evaluateJavaScript` on every change; the
setters update the JS cache immediately **and** notify the native side.
→ Fallback: a synchronous `prompt()` intercepted by `WKUIDelegate` (works, but it's a hack).

### 7.2 http/https interception is impossible with `WKURLSchemeHandler`
`WKURLSchemeHandler` cannot register `http`/`https` (runtime exception). Yet the frontend
calls the bridge on **`http://127.0.0.1…`** (hard-coded in `api.ts`).
Options:
- **A. Custom scheme** (`memories-app://app/…`) serving the shell + assets and proxying the API via
  `URLSession`. Everything is same-origin, no open port. **But** `NAPI.*` points to
  `http://127.0.0.1` (since `hostname !== '127.0.0.1'`) → requires either a frontend patch
  (use `location.origin` in native mode — an upstream PR to propose), or option B for the bridge.
  Other limitations: no service worker, `Range` must be implemented manually for `<video>`,
  POST request bodies sometimes arrive in `httpBodyStream` and must be read, cookies on custom schemes are unreliable.
- **B. Local HTTP server** on 127.0.0.1 (NWListener / a library such as FlyingFox/Swifter), like Android.
  Works with the frontend **unmodified**. Requires `NSAppTransportSecurity >
  NSAllowsLocalNetworking = YES`, a secret (cookie) like Android, and the server is suspended
  in the background (must be restarted when returning to the foreground).
- **C. Load the remote server directly** (`https://server/index.php/apps/memories/`),
  authenticated by a session cookie. The simplest, but the `http://127.0.0.1` bridge becomes
  a cross-origin http request from an https page (mixed content; WebKit treats loopback
  as "potentially trustworthy", to be verified) + CORS, and offline mode is lost.

### 7.3 PHAsset vs file paths
- Android identifies media by a **`Long` MediaStore ID** (used as `fileid` and in
  `/image/preview/{id}`, `/video/full/{id}`, which require `\d+`). iOS has `localIdentifier`
  (a string like `UUID/L0/001`) → a **mapping table** numeric id ↔ identifier is needed.
- **AUID** = `md5("<epoch><size>")`, **BUID** = `md5("<fileName>" + "iuid=<EXIF ImageUniqueID>" | "size=<size>")`.
  They must be **identical to the ones computed by the server** to deduplicate local/remote.
  On iOS: the size and original name come from `PHAssetResource` (`originalFilename`, private
  `fileSize` key via KVC — undocumented); EXIF requires reading the data (expensive, iCloud).
- Photos **in iCloud** (not downloaded): `PHImageManager` must allow network access;
  latency and cost must be handled.
- No "folders" on iOS: `LocalFolders` become **albums** (`PHAssetCollection`).
- HEIC: `/image/full` must return JPEG → conversion.
- Deletion: iOS shows its own alert (no native `dry` mode).

### 7.4 Other points
- **Manifest signature** (offline option A/B): Ed25519 → `CryptoKit.Curve25519.Signing.PublicKey`
  (available on iOS 13+), public keys to be taken from `ManifestVerifier.kt`.
- **Login Flow v2 and `ASWebAuthenticationSession`**: flow v2 does not redirect to a callback
  scheme; the session is closed manually once polling succeeds (or use
  `SFSafariViewController`, more natural here).
- **Basic auth performance** (×17 slower without a session): keep session cookies on the
  `URLSession` side.
- **Video playback**: WebKit plays HLS natively; `playVideo2` can be left unimplemented
  at first (the frontend falls back to the web player if the function doesn't exist).
- **Background**: no continuous sync like on Android; use `BGTaskScheduler`
  later.
- **App Store**: an app that downloads and runs remote JS is accepted for a web
  wrapper (guidelines 4.7 / 2.5.2 to keep an eye on); the minimal native UI (login) helps.

---

## 8. MVP proposal (step 1)

Since the NativeX bridge is not part of the MVP, I propose:

1. **MVP = option C (load the server directly)**: after Login Flow v2, a `URLSession`
   does `GET …/apps/memories/api/describe` with Basic auth → Nextcloud returns the session
   cookies (`oc…`, `nc_session_id`, `nc_sameSiteCookie*`), which we **copy into
   `WKHTTPCookieStore`**; the WebView then loads `…/index.php/apps/memories/` and the page
   is rendered authenticated by the server. The first `load` also sends the
   `Authorization` header as a fallback. If the session expires (redirect to `/login`), the
   bootstrap is redone automatically.
   "Memories installed" check: `api/describe` → 404 = not installed; network error =
   server unreachable; minimum version `9.0.0-rc.1`.
2. **NativeX step (next)**: move to option **B (local server on 127.0.0.1)**, which
   faithfully reproduces Android and avoids patching the frontend; the MVP's network/auth code
   (`NextcloudClient`, `CredentialStore`) will be reused as-is by the proxy.

Planned structure (`MemoriesIOS/`):
```
Sources/
  App/            MemoriesApp.swift, RootView.swift
  Auth/           LoginFlowV2.swift, CredentialStore.swift (Keychain), SessionStore.swift
  Network/        NextcloudClient.swift, ServerURL.swift, AppError.swift
  Views/          LoginView.swift, WebContainerView.swift, ErrorView.swift
  Web/            MemoriesWebView.swift (UIViewRepresentable), WebViewCoordinator.swift, CookieBridge.swift
  NativeX/        NativeXBridge.swift (protocol), NativeXMethod.swift, nativex.js (empty for now)
```
