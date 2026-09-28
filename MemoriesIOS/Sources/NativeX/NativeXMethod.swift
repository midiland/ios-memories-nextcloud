import Foundation

/// `window.nativex` methods expected by the frontend (`src/native/api.ts`),
/// with the same signatures as `NativeX.kt` on Android.
enum NativeXMethod: String, CaseIterable {
    case isNative                  // () -> Boolean
    case setThemeColor             // (color: String?, isDark: Boolean)
    case playTouchSound            // ()
    case toast                     // (message: String, long: Boolean = false)
    case logout                    // ()
    case reload                    // ()
    case downloadFromUrl           // (url: String?, filename: String?, title: String?)
    case setShareBlobs             // (objects: String JSON) — must be handled BEFORE GET /api/share/blobs
    case playVideo                 // (auid: String, fileid: Long, urlsArray: String JSON)
    case playVideo2                // (auid, fileid, urlsArray, loop: Boolean = false)
    case destroyVideo              // (fileid: Long)
    case configSetLocalFolders     // (json: String)
    case configGetLocalFolders     // () -> String JSON
    case configHasMediaPermission  // () -> Boolean
    case getSyncStatus             // () -> Int (-1 if no sync)
    case setHasRemote              // (auids: String JSON, buids: String JSON, value: Boolean)

    /// The JS reads the return value immediately: impossible via `postMessage`,
    /// so the value has to be cached on the JS side and pushed by the native code.
    var isSynchronous: Bool {
        switch self {
        case .isNative, .configGetLocalFolders, .configHasMediaPermission, .getSyncStatus:
            return true
        default:
            return false
        }
    }
}
