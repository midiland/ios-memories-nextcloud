# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## Unreleased

### Fixed
- **Zoom**: Pinch-to-zoom no longer scales the whole app UI (photo grid, top bar and bottom navigation); the interface now always stays at its normal scale. (Issue #12)

---

## 1.0.0-rc.11

### Fixed
- **Sharing**: Public links for albums and photos now use the Nextcloud server address instead of the local address (127.0.0.1), so they work for anyone they are shared with. (Issue #7)
- **Setup**: The "Set up automatic upload" button now opens the Nextcloud app on the App Store instead of the Android app on Google Play. (Issue #8)
- **Device photos**: The "Upload Local" action is no longer shown when selecting photos stored only on the device, since uploading from the app is not supported yet. (Issue #9)

---

## 1.0.0-rc.10

### Changed
- **Album downloads**: Downloading an album now recreates it in Photos under the same name, without duplicating photos that already exist in the library.

### Fixed
- **Album sharing**: The "Share album" dialog now correctly shows the collaborator search field and public link options, and can be reopened after closing.
- **New album with collaborators**: The "Add collaborators" button now properly opens the full dialog when creating a new album.

---

## 1.0.0-rc.09

### Fixed
- **Downloads**: Downloading a photo or video no longer fails with "HTTP 403" error.
- **Save to Photos**: Downloaded photos and videos now go straight to the Photos app. On first use, the app explains why it needs full access to the photo library.

---

## 1.0.0-rc.08

### Added
- **Nextcloud 10 support**: The app now works with Nextcloud version 10.

---

## 1.0.0-rc.07

### Added
- First version of the app for testing. All features are to be tested. If you encounter any issues, please open an issue on [https://github.com/midiland/ios-memories-nextcloud](https://github.com/midiland/ios-memories-nextcloud).
