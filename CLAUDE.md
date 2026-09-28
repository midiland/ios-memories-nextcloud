# Memories iOS

App iOS native (Swift/SwiftUI + WKWebView) pour [Memories](https://github.com/pulsejet/memories),
l'app photos de Nextcloud. Objectif : porter le wrapper Android officiel (WebView + pont « NativeX »).

- Analyse détaillée du code Android et du frontend : `docs/ANALYSE.md` (à lire avant de toucher au pont NativeX).
- Code de référence (non versionné, dans `.gitignore`) : `reference/memories`.
  Le recréer avec `git clone --depth 1 https://github.com/pulsejet/memories reference/memories`.
- Langue : code, commentaires et UI en **français**. Fichiers courts, un rôle par fichier.

## Commandes

```sh
# Régénérer le projet Xcode (obligatoire après ajout/suppression de fichiers ou modif de project.yml)
cd MemoriesIOS && xcodegen generate

# Build (le simulateur « iPhone 16 » a été créé à la main sur le runtime iOS 26.5)
xcodebuild -project MemoriesIOS/MemoriesIOS.xcodeproj -scheme MemoriesIOS \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Le `.xcodeproj` est généré mais versionné pour pouvoir builder sans XcodeGen ; `project.yml` fait foi.
Info.plist est généré par XcodeGen depuis la section `info:` de `project.yml` (ne pas l'éditer à la main).

## Architecture (`MemoriesIOS/Sources/`)

| Dossier | Rôle |
|---|---|
| `App/` | `MemoriesApp` (@main), `RootView` (connexion ↔ WebView), `AppConstants` |
| `Auth/` | `Credentials`, `CredentialStore` (Keychain), `LoginFlowV2`, `SessionStore` (état global, ObservableObject) |
| `Network/` | `ServerURL` (normalisation de la saisie → `…/index.php/apps/memories/`), `NextcloudClient` (describe, Login Flow v2, révocation), modèles, `AppError` |
| `Web/` | `WebViewModel` (possède la WKWebView), `WebViewFactory` (config), `WebNavigationHandler` (délégués), `WebSessionBootstrapper` (cookies), `MemoriesWebView` (UIViewRepresentable) |
| `Views/` | `LoginView`, `SafariView`, `WebContainerView`, `ErrorView` |
| `NativeX/` | protocole `NativeXBridge` + `DisabledNativeXBridge` (MVP), `NativeXMethod` (liste des 16 méthodes Android) |

### Flux
1. **Login** : saisie URL → `GET api/describe` (Memories installé ? version ≥ 9.0.0-rc.1 ?) →
   `POST /index.php/login/v2` → page de login dans `SFSafariViewController` → polling 3 s / 10 min →
   `loginName` + `appPassword` → Keychain.
2. **WebView** : `api/describe` en Basic auth via une `URLSession` éphémère → cookies de session
   Nextcloud copiés dans `WKHTTPCookieStore` → chargement de `…/index.php/apps/memories/`
   (header `Authorization` en secours sur ce premier chargement).
3. **Session expirée** (redirection vers `/login` ou 401) : réamorçage automatique, abandon si ça reboucle en < 30 s.
   `describe` authentifié renvoyant 401 ou `uid == null` ⇒ identifiants effacés, retour au login.
4. **Déconnexion** : bouton flottant « … » → révocation du mot de passe d'application
   (`DELETE /ocs/v2.php/core/apppassword`), suppression Keychain + données WebView.

## Décisions prises

- **iOS 16 minimum**, Swift 5 (mode de langage), `ObservableObject` (pas `@Observable`, iOS 17+).
- **MVP = chargement direct du serveur distant** + session par cookies (option C de l'analyse),
  alors qu'Android sert un snapshot local via un serveur 127.0.0.1 qui proxifie avec Basic auth.
  Pour l'étape NativeX, prévu : **serveur HTTP local 127.0.0.1** (option B), car le frontend
  appelle le pont sur `http://127.0.0.1` en dur (`src/native/api.ts`) et `WKURLSchemeHandler`
  ne peut pas intercepter http/https.
- **User-Agent** : suffixe `Version/x.y Mobile/15E148 Safari/604.1 MemoriesIOS/<v>`.
  - `Safari/…` évite la page Nextcloud « navigateur non supporté ».
  - **Ne pas** mettre `MemoriesNative/<v>` tant que `window.nativex` n'existe pas : le serveur
    (`Util::callerIsNative`) change alors de template et de comportement.
- **Ne pas définir `window.nativex`** tant que le pont n'est pas complet (le frontend passerait en mode natif).
- `SFSafariViewController` plutôt qu'`ASWebAuthenticationSession` (Login Flow v2 n'a pas de schéma de retour).
- Keychain : `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, un seul compte.
- ATS : `NSAllowsLocalNetworking` seulement (serveurs `.local` en http ; les IP sont exemptées d'ATS).
  Pas de « trust all certificates » pour l'instant (option Android non portée).

## Prochaines étapes (étape 2 : NativeX)

Voir `docs/ANALYSE.md` §6–7 : `WKUserScript` au document-start définissant `window.nativex`,
`WKScriptMessageHandler` (proxy faible), cache JS pour les méthodes synchrones
(`configGetLocalFolders`, `configHasMediaPermission`, `getSyncStatus`, `isNative`),
serveur local 127.0.0.1 pour `/api/*`, `/image/*`, `/video/*`, puis PhotoKit (AUID/BUID identiques au serveur).

## Git

Un commit par étape fonctionnelle, message en français, trailer `Co-Authored-By` Claude.
