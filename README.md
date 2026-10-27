# Memories for iOS

An unofficial native iOS client for [Memories](https://github.com/pulsejet/memories), the photo
management app for Nextcloud. It is a port of the official
[Android app](https://github.com/pulsejet/memories/tree/master/android): a native shell around the
Memories web interface, with a "NativeX" bridge that gives the web app native features.

> This project is not affiliated with the Memories or Nextcloud projects.

## Try the beta

The app is available as a public beta on TestFlight: **[join the beta](https://testflight.apple.com/join/GZvYN5cE)**
(iOS 16 or later, Memories 9.0.0-rc.1 or later on your Nextcloud server, see [Requirements](#requirements)).

Found a bug or have an idea? Please [open an issue](https://github.com/midiland/ios-memories-nextcloud/issues) with your iOS version, device,
Memories and Nextcloud versions, and the steps to reproduce.

## Features

### Implemented on iOS

- **Nextcloud sign-in** with [Login Flow v2](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html)
  in an in-app Safari sheet; the app password is stored in the iOS Keychain and revoked on logout.
- **App-like interface**: the Memories web UI runs in native mode (no Nextcloud header, mobile
  navigation bar, theme color applied to the status bar and safe areas).
- **Native back navigation**: a floating back button and the left-edge swipe on the screens where the
  web UI relies on a system back button (On this day, Favorites, Videos, Archive, Map, Folders, Search,
  People/Places/Tags…).
- **Instant startup and offline shell**: the Memories web assets are downloaded once, verified
  (Ed25519-signed manifest, SHA-256 per file, protection against replaying older signed versions) and served from the device; the app opens immediately,
  even without network access, and updates itself in the background when the server is upgraded
  (an update that cannot be verified is not installed: the app keeps the previous version and says so).
- **No unsigned code**: the web interface is never loaded directly from the server. Without a validly
  signed manifest (server too old, broken or newer than the app supports), the app shows an error
  screen instead — like the Android app, the server is not trusted to serve executable code.
- **Automatic session recovery**: expired sessions are renewed transparently; revoked credentials bring
  the user back to the login screen.
- **Device photos in the timeline** (opt-in, read-only): photos of the iPhone (whole library or selected
  albums) that are not on Nextcloud yet appear next to the server ones, with a "device" badge. Photos
  already uploaded are not shown twice, even when the Nextcloud app converted them to JPEG or renamed them.
- **Downloads saved to Photos**: downloaded photos and videos go straight to the photo library; an album
  download is extracted and recreated as an album in Photos, skipping the photos you already have (full
  photo library access, explained before iOS asks for it).
- **Remote wipe**: Nextcloud's "Wipe device" (Settings → Security → Devices & sessions) is honored: the app
  erases its local data (snapshots, caches, WebView data, Keychain credentials), confirms the wipe to the
  server and returns to the login screen. Photos already saved to the iOS Photos library are left untouched.
- **Swipe-to-select**: long-press a photo, then swipe across several photos to select them in one gesture,
  like the iOS Photos app (swiping over selected photos deselects them; near the screen edge it auto-scrolls).
- **Download progress**: album downloads show a persistent banner (downloading, extracting, saving to Photos)
  with progress, counters and a cancel button; the app stays usable meanwhile.
- **Full-screen photo viewer**: a zoomed photo fills the whole screen, behind the Dynamic Island and home
  indicator; pinch-to-zoom scales the photo, never the whole interface.
- **"On this day" widget**: a home screen widget (small and medium) shows your photos from past years on
  the current date, in the style of Apple Photos. The photo changes every 30 minutes; on iOS 17 a button
  shows the next one, a cross removes a photo from the widget (after a confirmation), and tapping a photo
  opens it in the app. The widget never sees your credentials: the app prepares the memories and the
  widget only reads them.
- **Native integrations**: iOS share sheet for photos and links (and for downloaded files that are not
  photos or videos), native toasts and haptic feedback.
- **English and French** user interface (follows the iOS language setting).

### Not implemented yet on iOS

- Device **videos** in the timeline (device photos only).
- Device photos in the **widget** (Nextcloud photos only).
- **Deleting** device photos and **uploading** them to Nextcloud from the app. The upload button of the
  mobile header is hidden until then; automatic upload is left to the official Nextcloud iOS app.
- Native **video player**: videos play in the web player.
- **Self-signed certificates** ("trust all certificates" option).

### Comparison with the Android app

| Feature | Android | iOS |
|---|:---:|:---:|
| Login Flow v2 | ✅ system browser | ✅ in-app Safari sheet |
| Secure credential storage | ✅ Android Keystore | ✅ Keychain |
| Self-signed certificates ("trust all") | ✅ | ❌ |
| Offline shell from a signed asset snapshot | ✅ | ✅ |
| Fallback to the remote web interface | — | — |
| Native mode UI (mobile navigation, theme color) | ✅ | ✅ |
| Back navigation | ✅ system back button | ✅ floating button + swipe |
| Share photos, albums and links | ✅ | ✅ share sheet |
| Download files | ✅ background download + notification | ✅ download, then Photos (or share sheet) |
| Album download | ✅ ZIP extracted to Downloads | ✅ ZIP extracted to Photos, album recreated, no duplicates |
| Touch feedback | ✅ click sound | ✅ haptics |
| Native video player | ✅ ExoPlayer | ❌ web player |
| Device photos in the timeline | ✅ MediaStore | ✅ PhotoKit (read-only) |
| Device videos in the timeline | ✅ | ❌ |
| "On this day" home screen widget | ❌ | ✅ |
| Device folder selection and setup screen | ✅ folders | ✅ library + albums |
| Deduplication with server photos | ✅ auid/buid | ✅ auid/buid + capture date/dimensions |
| Upload device photos from the app | ✅ | ❌ (button hidden) |
| Delete device photos from the app | ✅ | ❌ |

## Requirements

- iOS 16 or later.
- A Nextcloud server with the Memories app **9.0.0-rc.1 or later** (Memories 9 and 10 are supported): the
  offline shell loads the web assets listed in a signed manifest (`/apps/memories/api/describe?manifest=1`;
  a DSSE envelope over TUF targets since Memories 10). The web interface is
  never loaded directly from the server, so servers without a valid signed manifest (too old, broken,
  or newer than the app supports) cannot be used.

## Building

Tools: Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd MemoriesIOS
xcodegen generate          # regenerate MemoriesIOS.xcodeproj from project.yml
open MemoriesIOS.xcodeproj # then run the "MemoriesIOS" scheme
```

Command-line build for the simulator:

```sh
xcodebuild -project MemoriesIOS/MemoriesIOS.xcodeproj -scheme MemoriesIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Unit tests (`MemoriesIOS/Tests/`):

```sh
xcodebuild -project MemoriesIOS/MemoriesIOS.xcodeproj -scheme MemoriesIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

`project.yml` is the source of truth; regenerate the Xcode project after adding or removing files.
To run on a device, select your development team under *Signing & Capabilities*.

## For Developers

Full documentation is available in the [`/docs`](./docs/) directory:

| Guide | Description |
|-------|-------------|
| [Development Setup](./docs/DEVELOPMENT.md) | Build commands, project configuration, and tool setup |
| [Architecture](./docs/ARCHITECTURE.md) | Technical architecture, data flows, and design decisions |
| [Testing Guide](./docs/TESTING.md) | Unit tests, debugging tools, fake Nextcloud, Docker setup |
| [Releasing](./docs/RELEASING.md) | Versioning scheme, release process, and build numbers |
| [Contributing](./docs/CONTRIBUTING.md) | Language policy, localization, and Git guidelines |
| [Roadmap](./docs/ROADMAP.md) | Planned features and next steps |
| [Android Analysis](./docs/ANALYSIS.md) | Deep dive into the Android app |

For AI assistants: See [`CLAUDE.md`](./CLAUDE.md) for optimized context.

## How it works

```
┌──────────────── iOS app ─────────────────┐
│  SwiftUI screens (login, errors)         │
│  WKWebView ── window.nativex (NativeX) ──┼── share sheet, toasts, theme…
│      │                                   │
│      ▼  http://127.0.0.1:62079           │
│  Local HTTP server                       │
│   ├─ local HTML shell + cached JS/CSS    │
│   └─ streaming relay ────────────────────┼──► Nextcloud (Basic auth, app password)
└──────────────────────────────────────────┘
```

1. **Login** — the server URL is validated with `api/describe`, then Login Flow v2 returns a login
   name and an app password.
2. **Snapshot** — the JS/CSS listed in the signed manifest are downloaded to Application Support.
3. **Local server** — a small HTTP/1.1 server (Network.framework) on the loopback interface serves an
   HTML shell and the snapshot, and relays every API call to Nextcloud with the credentials. The page
   is therefore same-origin, works offline, and never holds the password. Requests must carry a
   per-launch HttpOnly cookie, so other apps on the device cannot use the server.
4. **NativeX bridge** — a user script defines `window.nativex` before the web app starts, which
   switches Memories to its native mode; calls are forwarded to Swift through WebKit message handlers.

The web files are only ever loaded from a verified snapshot: if the server provides no validly
signed manifest, a downloaded file does not match it, or the local server cannot start, the app
shows an error screen instead of running code served by Nextcloud.

A detailed analysis of the Android app and of the frontend's native API is available in
[`docs/ANALYSIS.md`](docs/ANALYSIS.md).

## Project structure

```
MemoriesIOS/
├── project.yml            XcodeGen spec
├── Resources/             nativex.js, shell CSS, String Catalogs (en, fr)
├── Widget/                "On this day" home screen widget (WidgetKit extension)
├── Tests/                 unit tests (MemoriesIOSTests)
└── Sources/
    ├── App/               entry point and wiring, constants, errors, logging
    ├── Auth/              Keychain, Login Flow v2, session state
    ├── Network/           Nextcloud client, server URL, downloads
    ├── Offline/           signed manifest, snapshot storage and sync, HTML shell
    ├── LocalServer/       loopback HTTP server, router, upstream relay
    ├── Web/               WKWebView setup, navigation policy, back button rule
    ├── NativeX/           window.nativex bridge implementation
    ├── OnThisDay/         "On this day" memories: selection, cache shared with the widget, refresh
    └── Views/             SwiftUI screens
```

## Localization

User-facing strings are written in English in the code and translated in
`MemoriesIOS/Resources/Localizable.xcstrings` and `InfoPlist.xcstrings`. To add a language, add its
translations to both catalogs. The Memories web interface itself follows the language configured in
Nextcloud.

## Debugging

- Logs (Debug builds), one line per local server request:
  `xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "fr.midiland.memories"'`
- Inspect the web view with Safari › Develop › *Simulator*.

## Contributing

Issues and pull requests are welcome. Please write code, comments, documentation and commit messages
in English, and add a French translation for every new user-facing string. See [`CLAUDE.md`](CLAUDE.md)
for the conventions and design decisions.

## License

Licensed under the [Apache License, Version 2.0](LICENSE). See [`NOTICE`](NOTICE) for attributions.

Parts of this app are ported from the Memories Android app, also licensed under the Apache License 2.0.
Memories itself (server and web interface) is licensed under AGPL-3.0; its web interface is downloaded
from your Nextcloud server at runtime and is not included in this repository.

## Acknowledgements

- [Memories](https://github.com/pulsejet/memories) by Varun Patil and contributors, and its Android app,
  which this project follows closely.
- [Nextcloud](https://nextcloud.com).
