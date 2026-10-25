import UIKit
import WebKit

/// NativeX bridge: exposes native functions to the Memories JavaScript.
///
/// On Android this is the `window.nativex` object (`addJavascriptInterface`) plus an HTTP bridge
/// on 127.0.0.1 (see `docs/ANALYSIS.md` §3). On iOS:
/// - injects `nativex.js` at document start (defines `window.nativex`);
/// - `nativex` handler: fire-and-forget calls (`postMessage`);
/// - `nativexAsync` handler: `http://127.0.0.1/...` requests intercepted by the JS,
///   with a reply (`WKScriptMessageHandlerWithReply`).
@MainActor
final class NativeXController: NSObject {
    static let syncHandler = "nativex"
    static let asyncHandler = "nativexAsync"

    weak var host: NativeXHost? {
        didSet {
            share.host = host
            photos.host = host
        }
    }

    private let share: NativeXShareService
    let photos: NativeXPhotoService
    private let router: NativeXLoopbackRouter
    /// Port of the local server: messages are only accepted from its main frame.
    private let localPort: @MainActor () -> UInt16

    init(share: NativeXShareService, photos: NativeXPhotoService, serverOrigin: URL, localPort: @escaping @MainActor () -> UInt16) {
        self.share = share
        self.photos = photos
        self.localPort = localPort
        router = NativeXLoopbackRouter(share: share, photos: photos, serverOrigin: serverOrigin)
    }

    /// Cancels the ongoing album download, if any (issue #14).
    func cancelDownload() {
        share.cancelDownload()
    }

    // MARK: - Installation

    /// Installs the script and the message handlers into the web view configuration.
    /// `WKUserContentController` retains its handlers strongly: they go through a weak proxy.
    func install(into controller: WKUserContentController) {
        guard let source = Self.scriptSource(state: initialState) else {
            assertionFailure("nativex.js not found in bundle")
            return
        }
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // Swipe-to-select enhancement for iOS (issue #11): haptic feedback + scroll bounce fix.
        if let swipeSource = Self.swipeSelectScriptSource() {
            controller.addUserScript(WKUserScript(source: swipeSource, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let proxy = WeakScriptMessageProxy(self)
        controller.add(proxy, name: Self.syncHandler)
        controller.addScriptMessageHandler(proxy, contentWorld: .page, name: Self.asyncHandler)
    }

    /// Reads `swipe-select.js` from the bundle (internal for the script tests).
    nonisolated static func swipeSelectScriptSource() -> String? {
        guard let url = Bundle.main.url(forResource: "swipe-select", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return source
    }

    // MARK: - Synchronous state

    /// Values the frontend reads synchronously (`configGetLocalFolders`, `configHasMediaPermission`,
    /// `getSyncStatus`): impossible through `postMessage`, so `nativex.js` serves them from this state.
    private var initialState: [String: Any] { photos.state }

    /// Reads `nativex.js` and injects the initial state as JSON (internal for the script tests).
    nonisolated static func scriptSource(state: [String: Any]) -> String? {
        guard let url = Bundle.main.url(forResource: "nativex", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8),
              let json = try? JSONSerialization.data(withJSONObject: state),
              let stateJSON = String(data: json, encoding: .utf8)
        else { return nil }
        return template.replacingOccurrences(of: "__NATIVEX_STATE__", with: stateJSON)
    }
}

// MARK: - JS → native messages

extension NativeXController: WKScriptMessageHandler, WKScriptMessageHandlerWithReply {
    /// Fire-and-forget calls: `{ method, args }`.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard isTrusted(message.frameInfo),
              let body = message.body as? [String: Any],
              let name = body["method"] as? String,
              let method = NativeXMethod(rawValue: name)
        else { return }
        let args = (body["args"] as? [Any]) ?? []
        dispatch(method, args: NativeXArguments(args))
    }

    /// Async bridge requests: `{ method, url }` → `{ status, contentType, body }`.
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard isTrusted(message.frameInfo),
              let body = message.body as? [String: Any],
              let urlString = body["url"] as? String,
              let url = URL(string: urlString)
        else { return replyHandler(NativeXResponse.error.dictionary, nil) }
        let method = (body["method"] as? String) ?? "GET"

        Task {
            let response = await router.handle(method: method, url: url)
            replyHandler(response.dictionary, nil)
        }
    }

    /// Handlers are exposed to every frame: only the local server's main frame may call native code.
    private func isTrusted(_ frame: WKFrameInfo) -> Bool {
        let origin = frame.securityOrigin
        return LocalOrigin.isTrustedFrame(
            isMainFrame: frame.isMainFrame, scheme: origin.protocol, host: origin.host, port: origin.port, localPort: localPort()
        )
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
            photos.setFolders(json: args.string(0))
        case .setHasRemote:
            photos.setHasRemote(auidsJSON: args.string(0), buidsJSON: args.string(1), value: args.bool(2))
        case .setViewerFullscreen:
            host?.nativeXSetViewerFullscreen(args.bool(0))
        case .isNative, .configGetLocalFolders, .configHasMediaPermission, .getSyncStatus,
             .playVideo, .playVideo2, .destroyVideo:
            break // synchronous (served by the JS cache) or not exposed
        }
    }
}
