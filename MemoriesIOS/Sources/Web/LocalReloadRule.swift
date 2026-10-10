import Foundation

/// How the page recovers when the local server was not listening.
///
/// The local server stops listening in the background. Meanwhile iOS may kill the WebContent
/// process (memory pressure, common after a few hours): reloading right away hits a closed port
/// and ends on the "Server unreachable" screen although nothing is wrong. Loads are therefore
/// deferred until the server listens again, and a local connection failure is retried once.
enum LocalReloadRule {
    enum Action: Equatable {
        case none
        /// Reload the current page (keeps the user's route).
        case reload
        /// Load the entry page (new origin, or no page left to reload).
        case loadEntry
        /// Full restart (`WebViewModel.start()`).
        case restart
    }

    /// Back in the foreground, once the local server listens again on `serverPort`.
    /// - Parameters:
    ///   - page: URL of the web view, if it is a local page.
    ///   - contentProcessTerminated: the WebContent process died since the last load.
    ///   - showsUnreachableError: the "Server unreachable" screen is shown.
    static func onBecomeActive(
        page: URL?, serverPort: UInt16, contentProcessTerminated: Bool, showsUnreachableError: Bool
    ) -> Action {
        if showsUnreachableError { return .restart }
        if let page, page.port != Int(serverPort) { return .loadEntry }
        if contentProcessTerminated { return page == nil ? .loadEntry : .reload }
        return .none
    }

    /// Whether a failed main-frame load is worth retrying once the local server listens again:
    /// only connection errors on the loopback host, and only once.
    static func shouldRetry(_ error: Error, alreadyRetried: Bool) -> Bool {
        guard !alreadyRetried else { return false }
        let error = error as NSError
        guard error.domain == NSURLErrorDomain, retriedCodes.contains(error.code) else { return false }
        let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        return url?.host == LocalHTTPServer.host || url?.host == "localhost"
    }

    private static let retriedCodes: Set<Int> = [
        NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
    ]
}
