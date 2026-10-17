# Memories iOS - Releasing

This document describes the versioning scheme and release process for Memories iOS.

---

## 📦 Bundle Identification

| Identifier | Value | Purpose |
|------------|-------|---------|
| Bundle ID | `fr.midiland.memories` | App identifier |
| Test Bundle ID | `fr.midiland.memories.tests` | Unit tests |
| Logger Subsystem | `fr.midiland.memories` | Logs (Debug builds) |

---

## 📊 Versioning Scheme

The app uses **semantic versioning** (`MAJOR.MINOR.PATCH`) with release candidates.

### Version Numbers in Xcode
Two version numbers are configured in `MemoriesIOS/project.yml` (`settings.base`):

| Xcode Setting | CFBundle Key | Format | Purpose |
|----------------|--------------|--------|---------|
| `MARKETING_VERSION` | `CFBundleShortVersionString` | `MAJOR.MINOR.PATCH` | Display version (App Store) |
| `CURRENT_PROJECT_VERSION` | `CFBundleVersion` | Build number | Internal build identifier |

### Build Number Calculation
The build number (`CURRENT_PROJECT_VERSION`) is calculated as:
```
MAJOR × 1,000,000 + MINOR × 10,000 + PATCH × 100 + N
```
- **N** = Release candidate number (1, 2, 3...) or 0 for final release
- **Maximum**: 99 minors, 99 patches, 99 RCs
- **Always increasing**: Each build must have a higher number than the previous

### Examples

| Git Tag | `MARKETING_VERSION` | `CURRENT_PROJECT_VERSION` | Notes |
|---------|----------------------|----------------------------|-------|
| `v1.0.0-rc.1` | `1.0.0` | `1000001` | First RC for 1.0.0 |
| `v1.0.0-rc.2` | `1.0.0` | `1000002` | Second RC for 1.0.0 |
| `v1.0.0` | `1.0.0` | `1000002` | Final release (same build as last RC) |
| `v1.2.3-rc.1` | `1.2.3` | `1020301` | First RC for 1.2.3 |
| `v1.2.3-rc.2` | `1.2.3` | `1020302` | Second RC for 1.2.3 |
| `v1.2.3` | `1.2.3` | `1020302` | Final release |
| `v2.0.0-rc.1` | `2.0.0` | `2000001` | Major version bump |

---

## 🚀 Release Process

### 1. Release Candidate (RC)

**Steps:**
1. Ensure all changes for the release are committed to `main`
2. Create a commit that **only** updates the version numbers in `project.yml`:
   ```bash
   git commit -m "chore(release): 1.2.3 (1020301)"
   ```
3. Regenerate the Xcode project:
   ```bash
   cd MemoriesIOS
   xcodegen generate
   ```
4. Commit the regenerated `project.pbxproj`:
   ```bash
   git add MemoriesIOS/MemoriesIOS.xcodeproj
   git commit --amend -m "chore(release): 1.2.3 (1020301)"
   ```
5. Create an **annotated tag**:
   ```bash
   git tag -a v1.2.3-rc.1 -m "Release candidate 1 for v1.2.3"
   ```
6. Push the commit and tag:
   ```bash
   git push origin main --follow-tags
   ```

**Important:**
- The commit must **only** change version numbers and the regenerated project file
- Do **not** include other changes in the release commit

### 2. Distribute on TestFlight

1. Build the app in Xcode using the **Release** configuration
2. Archive the app (Product > Archive)
3. Distribute to TestFlight via Organizer
4. Fill in the release notes for this RC

**Note:** TestFlight builds must use **increasing build numbers** (handled automatically by the versioning scheme).

### 3. Final Release

**No rebuild required!** The final release uses the **same build** as the last RC.

**Steps:**
1. In **App Store Connect**, promote the last RC build to release
2. Fill in the release notes for the final version
3. Submit for review
4. Create the final tag (same commit as last RC):
   ```bash
   git tag -a v1.2.3 -m "Release v1.2.3"
   git push origin v1.2.3
   ```

---

## 🔒 Release Rules

### Golden Rules
1. **Never add builds to a released version**
   - Once a version is on the App Store, **no new builds** can be added to it
   - The next change **must** bump at least the PATCH version

2. **Always increase build numbers**
   - Each build (RC or final) must have a higher `CURRENT_PROJECT_VERSION` than the previous

3. **RC tags use `-rc.N` suffix**
   - Git tags: `v1.2.3-rc.1`, `v1.2.3-rc.2`
   - App Store: Only integer versions (`1.2.3`) - **no `-rc.N` suffix** in App Store versions

4. **Final tag matches RC commit**
   - The `v1.2.3` tag points to the **same commit** as `v1.2.3-rc.2` (last RC)

### Version Bumps
| Change Type | Version Bump | Example |
|-------------|--------------|---------|
| Bug fixes, minor improvements | PATCH (+1) | `1.2.3` → `1.2.4` |
| New features (backward compatible) | MINOR (+1) | `1.2.3` → `1.3.0` |
| Breaking changes | MAJOR (+1) | `1.2.3` → `2.0.0` |

---

## 📝 Release Notes

### For TestFlight (RC)
Include:
- Major new features
- Bug fixes
- Known issues
- Testing focus areas

### For App Store (Final)
Include:
- User-facing features (what's new)
- Bug fixes (general descriptions, no technical details)
- Performance improvements

**Language:** Always write release notes in **English** first, then add French translation.

---

## 🔄 Hotfix Process

For urgent bug fixes after a release:

1. **Do not patch the released version** (see rule #1 above)
2. Instead, **bump the PATCH version**:
   - If last release was `1.2.3`, create `1.2.4-rc.1`
3. Follow the normal RC process
4. Release `1.2.4` as a hotfix

---

## 📊 Version Matrix

| Version | Status | Build Number | Git Tag | TestFlight | App Store |
|---------|--------|--------------|---------|------------|-----------|
| 1.0.0-rc.1 | RC | 1000001 | `v1.0.0-rc.1` | ✅ | ❌ |
| 1.0.0-rc.2 | RC | 1000002 | `v1.0.0-rc.2` | ✅ | ❌ |
| 1.0.0 | Final | 1000002 | `v1.0.0` | ❌ | ✅ |
| 1.0.1-rc.1 | RC | 1000101 | `v1.0.1-rc.1` | ✅ | ❌ |
| 1.0.1 | Final | 1000101 | `v1.0.1` | ❌ | ✅ |
| 1.1.0-rc.1 | RC | 1010001 | `v1.1.0-rc.1` | ✅ | ❌ |

---

## 🔧 Updating Version Numbers

### In `project.yml`
```yaml
settings:
  base:
    MARKETING_VERSION: 1.2.3
    CURRENT_PROJECT_VERSION: 1020301
```

### Calculation Helper
```bash
# For version 1.2.3-rc.1
MAJOR=1
MINOR=2
PATCH=3
RC=1
BUILD=$((MAJOR * 1000000 + MINOR * 10000 + PATCH * 100 + RC))
echo "Build number: $BUILD"  # Output: 1020301
```

---

## 🔗 Related Documentation
- [Development Setup](DEVELOPMENT.md) - Build commands and project configuration
- [Testing Guide](TESTING.md) - How to test before releasing
- [Contributing Guidelines](CONTRIBUTING.md) - Contribution rules
- [Architecture Overview](ARCHITECTURE.md) - Technical architecture
