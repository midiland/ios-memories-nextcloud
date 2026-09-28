import Foundation

/// Méthodes de `window.nativex` attendues par le frontend (`src/native/api.ts`),
/// avec la même signature que `NativeX.kt` côté Android.
enum NativeXMethod: String, CaseIterable {
    case isNative                  // () -> Boolean
    case setThemeColor             // (color: String?, isDark: Boolean)
    case playTouchSound            // ()
    case toast                     // (message: String, long: Boolean = false)
    case logout                    // ()
    case reload                    // ()
    case downloadFromUrl           // (url: String?, filename: String?, title: String?)
    case setShareBlobs             // (objects: String JSON) — à traiter AVANT GET /api/share/blobs
    case playVideo                 // (auid: String, fileid: Long, urlsArray: String JSON)
    case playVideo2                // (auid, fileid, urlsArray, loop: Boolean = false)
    case destroyVideo              // (fileid: Long)
    case configSetLocalFolders     // (json: String)
    case configGetLocalFolders     // () -> String JSON
    case configHasMediaPermission  // () -> Boolean
    case getSyncStatus             // () -> Int (-1 si pas de synchro)
    case setHasRemote              // (auids: String JSON, buids: String JSON, value: Boolean)

    /// Le JS lit la valeur de retour immédiatement : impossible via `postMessage`,
    /// il faudra une valeur mise en cache côté JS et poussée par le natif.
    var isSynchronous: Bool {
        switch self {
        case .isNative, .configGetLocalFolders, .configHasMediaPermission, .getSyncStatus:
            return true
        default:
            return false
        }
    }
}
