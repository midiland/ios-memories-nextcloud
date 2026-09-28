#if DEBUG
import Foundation

/// Automatisation de test (builds Debug uniquement), pilotée par arguments de lancement,
/// faute de pouvoir toucher l'écran du simulateur depuis la ligne de commande :
///
///     xcrun simctl launch "iPhone 17 Pro" gallery.memories.ios -MXRoute /thisday -MXBackAfter 4
///
/// - `-MXRoute <route>` : 4 s après le premier affichage, navigue via le routeur Vue (`_m.router.push`) ;
/// - `-MXBackAfter <s>` : puis appuie sur le bouton retour natif après `<s>` secondes.
@MainActor
enum DebugAutomation {
    private static var didRun = false

    static func run(on model: WebViewModel) {
        guard !didRun else { return }
        let defaults = UserDefaults.standard
        guard let route = defaults.string(forKey: "MXRoute") else { return }
        didRun = true
        let backAfter = defaults.double(forKey: "MXBackAfter")

        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let js = "window._m && _m.router.push(\(jsonString(route)))"
            _ = try? await model.webView.evaluateJavaScript(js)
            Log.offline.debug("Debug : navigation vers \(route, privacy: .public)")
            guard backAfter > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(backAfter * 1_000_000_000))
            Log.offline.debug("Debug : bouton retour visible = \(model.showsBackButton), appui")
            model.goBack()
        }
    }

    private static func jsonString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
#endif
