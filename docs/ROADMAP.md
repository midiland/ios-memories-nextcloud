# Memories iOS - Roadmap

This document outlines the planned features and improvements for Memories iOS.

---

## 🚀 Next Steps (High Priority)

### Device Photos - Phase 2
The app currently supports **device photos** in the timeline (read-only). Phase 2 will add:

| Feature | Status | Priority | Notes |
|---------|--------|----------|-------|
| Local videos | ❌ Not implemented | **High** | Show device videos in timeline |
| Video playback | ❌ Not implemented | **High** | Native or web player for device videos |
| Photo deletion | ❌ Not implemented | **High** | Delete device photos from app |
| Photo upload | ❌ Not implemented | **High** | Upload device photos to Nextcloud |

**Implementation notes:**
- Local videos: Route `/video/full/{id}` with `Range` support
- Deletion: `/api/image/delete` → `PHAssetChangeRequest`
- Upload: `/api/upload/local`

---

## 🎯 Other Candidates (Medium Priority)

| Feature | Description | Priority |
|---------|-------------|----------|
| Live Photo pairs | Save HEIC+MOV pairs as single Live Photo in Photos app | Medium |
| Self-signed certificates | "Trust all certificates" option (like Android) | Medium |
| Launch screen | Custom launch screen | Low |
| Video thumbnails | Generate thumbnails for videos in timeline | Medium |
| Background sync | Auto-sync device photos in background | Medium |

---

## 📅 Long-Term Goals

| Feature | Description |
|---------|-------------|
| Full upload workflow | Complete upload UI with progress, retries, etc. |
| Offline upload queue | Queue photos for upload when offline |
| Advanced deduplication | Improve matching algorithm for edge cases |
| iPad optimization | Better iPad UI/UX |
| Widget support | iOS widgets for quick access |
| Siri integration | Voice commands for common actions |
| Watch app | Companion Apple Watch app |

---

## 💡 Feature Requests

Have an idea? Please [open an issue](https://github.com/midiland/ios-memories-nextcloud/issues) with:
- A clear description of the feature
- The expected behavior
- Any relevant use cases

---

## 📊 Contributing

Want to help implement these features? See [Contributing Guidelines](CONTRIBUTING.md) to get started!

---

## 🔗 Related Documentation
- [Architecture Overview](ARCHITECTURE.md) - Technical architecture
- [Development Setup](DEVELOPMENT.md) - Setting up your environment
- [Testing Guide](TESTING.md) - Testing your changes
- [Releasing](RELEASING.md) - Release process
