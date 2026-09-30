import Foundation

/// `window.nativex` methods expected by the frontend (`src/native/api.ts`),
/// with the same signatures as `NativeX.kt` on Android.
enum NativeXMethod: String {
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
}
