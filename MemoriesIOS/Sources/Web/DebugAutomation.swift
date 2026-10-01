#if DEBUG
import Foundation
import WebKit

/// Test automation (Debug builds only), driven by launch arguments, since the simulator
/// screen cannot be tapped from the command line:
///
///     xcrun simctl launch "iPhone 17 Pro" gallery.memories.ios -MXRoute /thisday -MXBackAfter 4
///
/// - `-MXRoute <route>`: 4 s after first display, navigates via the Vue router (`_m.router.push`);
/// - `-MXClick <css selector>`: then clicks the first matching element 3 s later
///   (e.g. `.cluster` to open the first person of `/recognize`);
/// - `-MXBackAfter <s>`: then taps the native back button after `<s>` seconds;
/// - `-MXEval <js>`: runs a script 4 s after first display (after the route, if any), then every
///   `-MXEvalEvery <s>` seconds if given, and logs its result (`log stream`, category `web`).
///   Async expressions are awaited, e.g. `-MXEval "JSON.stringify(await (await fetch(...)).json())"`.
@MainActor
enum DebugAutomation {
    private static var didRun = false

    static func run(on model: WebViewModel) {
        guard !didRun else { return }
        let defaults = UserDefaults.standard
        let route = defaults.string(forKey: "MXRoute")
        let script = defaults.string(forKey: "MXEval")
        guard route != nil || script != nil else { return }
        didRun = true
        let backAfter = defaults.double(forKey: "MXBackAfter")
        let click = defaults.string(forKey: "MXClick")
        let every = defaults.double(forKey: "MXEvalEvery")

        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if let route {
                let js = "window._m && _m.router.push(\(jsonString(route)))"
                _ = try? await model.webView.evaluateJavaScript(js)
                Log.web.debug("Debug: navigating to \(route, privacy: .public)")
            }
            if let script {
                repeat {
                    await evaluate(script, on: model)
                    guard every > 0 else { break }
                    try? await Task.sleep(nanoseconds: UInt64(every * 1_000_000_000))
                } while true
                return
            }
            if let click {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                _ = try? await model.webView.evaluateJavaScript("document.querySelector(\(jsonString(click)))?.click()")
                Log.web.debug("Debug: clicked \(click, privacy: .public)")
            }
            guard backAfter > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(backAfter * 1_000_000_000))
            Log.web.debug("Debug: back button visible = \(model.showsBackButton), tapping")
            model.goBack()
        }
    }

    /// Runs `script` as the body of an async function and logs its result.
    private static func evaluate(_ script: String, on model: WebViewModel) async {
        do {
            let result = try await model.webView.callAsyncJavaScript(
                "return await (async () => \(script))()", arguments: [:], contentWorld: .page
            )
            Log.web.debug("Debug eval: \(String(describing: result ?? "nil"), privacy: .public)")
        } catch {
            Log.web.debug("Debug eval failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func jsonString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
#endif
