import UIKit
import WebKit

/// Implémentation du pont NativeX (étape 2a : « mode app », sans photos locales).
///
/// - injecte `nativex.js` au début du document (définit `window.nativex`) ;
/// - handler `nativex` : appels « fire-and-forget » (`postMessage`) ;
/// - handler `nativexAsync` : requêtes `http://127.0.0.1/...` détournées par le JS,
///   avec réponse (`WKScriptMessageHandlerWithReply`).
@MainActor
final class NativeXController: NSObject, NativeXBridge {
    static let syncHandler = "nativex"
    static let asyncHandler = "nativexAsync"

    weak var host: NativeXHost? {
        didSet { share.host = host }
    }

    private let share = NativeXShareService()
    private lazy var router = NativeXLoopbackRouter(share: share)
    private let defaults = UserDefaults.standard
    private let localFoldersKey = "nativex.localFolders"

    // MARK: - NativeXBridge

    func install(into controller: WKUserContentController) {
        guard let source = Self.scriptSource(state: initialState) else {
            assertionFailure("nativex.js introuvable dans le bundle")
            return
        }
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let proxy = WeakScriptMessageProxy(self)
        controller.add(proxy, name: Self.syncHandler)
        controller.addScriptMessageHandler(proxy, contentWorld: .page, name: Self.asyncHandler)
    }

    func uninstall(from controller: WKUserContentController) {
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: Self.syncHandler)
        controller.removeScriptMessageHandler(forName: Self.asyncHandler, contentWorld: .page)
    }

    // MARK: - État synchrone

    /// Valeurs lues de façon synchrone par le frontend (voir `NativeXMethod.isSynchronous`).
    private var initialState: [String: Any] {
        [
            "localFolders": defaults.string(forKey: localFoldersKey) ?? "[]",
            "hasMediaPermission": false, // PhotoKit : étape 2b
            "syncStatus": -1,
        ]
    }

    /// Lit `nativex.js` et y insère l'état initial en JSON.
    private static func scriptSource(state: [String: Any]) -> String? {
        guard let url = Bundle.main.url(forResource: "nativex", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8),
              let json = try? JSONSerialization.data(withJSONObject: state),
              let stateJSON = String(data: json, encoding: .utf8)
        else { return nil }
        return template.replacingOccurrences(of: "__NATIVEX_STATE__", with: stateJSON)
    }
}

// MARK: - Messages JS → natif

extension NativeXController: WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    /// Appels « fire-and-forget » : `{ method, args }`.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let name = body["method"] as? String,
              let method = NativeXMethod(rawValue: name)
        else { return }
        let args = (body["args"] as? [Any]) ?? []
        dispatch(method, args: NativeXArguments(args))
    }

    /// Requêtes du pont asynchrone : `{ method, url }` → `{ status, contentType, body }`.
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let body = message.body as? [String: Any],
              let urlString = body["url"] as? String,
              let url = URL(string: urlString)
        else { return replyHandler(NativeXResponse.error.dictionary, nil) }
        let method = (body["method"] as? String) ?? "GET"

        Task {
            let response = await router.handle(method: method, url: url)
            replyHandler(response.dictionary, nil)
        }
    }

    private func dispatch(_ method: NativeXMethod, args: NativeXArguments) {
        switch method {
        case .setThemeColor:
            host?.nativeXSetTheme(color: args.string(0).flatMap(UIColor.init(css:)), isDark: args.bool(1))
        case .playTouchSound:
            UISelectionFeedbackGenerator().selectionChanged()
        case .toast:
            host?.nativeXToast(args.string(0) ?? "", long: args.bool(1))
        case .logout:
            host?.nativeXLogout()
        case .reload:
            host?.nativeXReload()
        case .downloadFromUrl:
            share.download(urlString: args.string(0), filename: args.string(1), title: args.string(2))
        case .setShareBlobs:
            share.stageBlobs(args.string(0))
        case .configSetLocalFolders:
            defaults.set(args.string(0) ?? "[]", forKey: localFoldersKey)
        case .setHasRemote:
            break // index local : étape 2b
        case .isNative, .configGetLocalFolders, .configHasMediaPermission, .getSyncStatus,
             .playVideo, .playVideo2, .destroyVideo:
            break // synchrones (servies par le cache JS) ou non exposées
        }
    }
}

/// Accès typé aux arguments d'un message JS (`null` JS → `NSNull`).
struct NativeXArguments {
    private let values: [Any]

    init(_ values: [Any]) { self.values = values }

    func string(_ index: Int) -> String? {
        index < values.count ? values[index] as? String : nil
    }

    func bool(_ index: Int) -> Bool {
        index < values.count ? (values[index] as? Bool) ?? false : false
    }
}
