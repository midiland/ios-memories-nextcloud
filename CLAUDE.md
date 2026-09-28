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
| `Offline/` | `AssetManifest` (describe `?manifest=1`), `ManifestVerifier` (Ed25519 CryptoKit), `SnapshotStore` (Application Support/offline), `AssetSyncer` (SHA-256, 8 en parallèle, réutilisation), `ShellPage` (HTML local), `CSSPathRewriter`, `OfflineAppLoader` (orchestration) |
| `LocalServer/` | Serveur HTTP/1.1 maison sur Network.framework : `LocalHTTPServer` (127.0.0.1:62079), `HTTPConnection`, `HTTPTypes`, `LocalRouter` (routage type `ServerRouter.kt`), `StaticFiles`, `UpstreamProxy` (relais en flux vers Nextcloud) |
| `Web/` | `WebViewModel` (possède la WKWebView), `WebViewFactory` (config), `WebNavigationHandler` (délégués), `WebSessionBootstrapper` (cookies), `MemoriesWebView` (UIViewRepresentable) |
| `Views/` | `LoginView`, `SafariView`, `WebContainerView` (fond thémé + toasts), `ErrorView`, `ToastView`, `SharePresenter` |
| `NativeX/` | `NativeXController` (pont), `NativeXHost` (implémenté par `WebViewModel`), `NativeXLoopbackRouter` (routes `127.0.0.1`), `NativeXShareService`, `NativeXMethod`, `WeakScriptMessageProxy` |
| `Resources/` (hors `Sources/`) | `nativex.js`, injecté au document-start ; `__NATIVEX_STATE__` y est remplacé par l'état JSON |

### Flux
1. **Login** : saisie URL → `GET api/describe` (Memories installé ? version ≥ 9.0.0-rc.1 ?) →
   `POST /index.php/login/v2` → page de login dans `SFSafariViewController` → polling 3 s / 10 min →
   `loginName` + `appPassword` → Keychain.
2. **Mode local (par défaut, étape 3)** : le serveur `127.0.0.1:62079` sert une page locale
   (`ShellPage`) + les JS/CSS d'un **snapshot** téléchargé depuis `describe?manifest=1`
   (manifeste JS signé Ed25519, chaque JS vérifié en SHA-256), et relaie tout le reste vers
   Nextcloud (`UpstreamProxy` : Basic auth + `OCS-APIREQUEST`, cookies de session dans
   `HTTPCookieStorage.shared`, flux avec contre-pression, réseau KO → 504 = « hors ligne »).
   - snapshot présent → page affichée tout de suite, mise à jour vérifiée en arrière-plan
     (nouveau snapshot → rechargement + toast) ; absent → écran de progression puis page ;
   - accès protégé par le cookie HttpOnly `local-auth` (secret par lancement) + contrôle du `Host` ;
   - page d'entrée chargée directement sur `<webroot>/index.php/apps/memories/` (évite une redirection) ;
   - les CSS du serveur ont des chemins relatifs (`@import '../../dist/icons.css'`) : réécrits
     à la volée d'après leur `href` d'origine (`CSSPathRewriter`, bug présent aussi sur Android).
3. **Mode distant (repli)** si pas de manifeste, signature invalide, échec du snapshot ou du serveur local :
   `api/describe` en Basic auth via une `URLSession` éphémère → cookies de session
   Nextcloud copiés dans `WKHTTPCookieStore` + cookie `nx_auth` (= header Basic, encodé %, HttpOnly)
   → chargement de `…/index.php/apps/memories/`. En mode natif le serveur convertit `nx_auth`
   en `Authorization` sur chaque requête (`Application::handleNativeHeaders`).
4. **Mode app (NativeX, étape 2a)** : `nativex.js` définit `window.nativex` ⇒ le frontend masque le
   bandeau Nextcloud, affiche en-tête + barre de navigation mobiles, rend la page transparente et
   envoie sa couleur (`setThemeColor`) peinte derrière la WebView et dans les safe areas.
   Les appels `http://127.0.0.1/…` (fetch et XHR) sont détournés en JS vers le handler
   `nativexAsync` (`WKScriptMessageHandlerWithReply`) : jours/photos locales vides,
   partage (`/api/share/url`, `/api/share/blobs`) réel via la feuille de partage iOS.
5. **Session expirée** (mode distant) (redirection vers `/login` ou 401) : réamorçage automatique, abandon si ça reboucle en < 30 s.
   `describe` authentifié renvoyant 401 ou `uid == null` ⇒ identifiants effacés, retour au login.
6. **Déconnexion** : Paramètres > Compte dans l'UI web (`nativex.logout`) ou écran d'erreur → révocation du mot de passe d'application
   (`DELETE /ocs/v2.php/core/apppassword`), suppression Keychain + données WebView + cookies
   du relais + configuration du serveur local (les snapshots restent sur disque).

## Décisions prises

- **iOS 16 minimum**, Swift 5 (mode de langage), `ObservableObject` (pas `@Observable`, iOS 17+).
- **MVP = chargement direct du serveur distant** + session par cookies (option C de l'analyse),
  alors qu'Android sert un snapshot local via un serveur 127.0.0.1 qui proxifie avec Basic auth.
  Pour l'étape NativeX, prévu : **serveur HTTP local 127.0.0.1** (option B), car le frontend
  appelle le pont sur `http://127.0.0.1` en dur (`src/native/api.ts`) et `WKURLSchemeHandler`
  ne peut pas intercepter http/https.
- **User-Agent** : suffixe `Version/x.y Mobile/15E148 Safari/604.1 MemoriesNative/1.15 MemoriesIOS/<v>`.
  - `Safari/…` évite la page Nextcloud « navigateur non supporté ».
  - `MemoriesNative/<v>` active le mode natif côté serveur (`Util::callerIsNative`) ; `<v>` doit
    rester ≥ `BinExt::NX_VER_MIN` (1.1), sinon page « app trop ancienne ». Aligné sur Android (1.15).
  - `MemoriesNative` et `window.nativex` vont ensemble : ne jamais activer l'un sans l'autre.
- **Pont 127.0.0.1 sans serveur local (2a)** : interception JS de `fetch`/`XMLHttpRequest`, réponses texte
  uniquement. Ne couvre pas les `<img src="http://127.0.0.1/image/…">` : il faudra un vrai serveur local
  (ou un patch frontend) pour les miniatures de photos locales en 2b.
- `playVideo`/`playVideo2`/`destroyVideo` **non exposés** : le frontend garde son lecteur web.
- `playTouchSound` = retour haptique ; `downloadFromUrl` = téléchargement puis feuille de partage
  (les identifiants ne partent que vers l'hôte du compte).
- Barre d'état : son style suit le thème système, pas `isDark` (limite connue si le thème
  Nextcloud forcé diffère du thème iOS).
- `SFSafariViewController` plutôt qu'`ASWebAuthenticationSession` (Login Flow v2 n'a pas de schéma de retour).
- Keychain : `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, un seul compte.
- ATS : `NSAllowsLocalNetworking` seulement (serveurs `.local` en http ; les IP sont exemptées d'ATS).
  Pas de « trust all certificates » pour l'instant (option Android non portée).

## Tester

- **Journaux** (Debug) : `xcrun simctl spawn booted log stream --level debug --predicate 'subsystem == "gallery.memories.ios"'`
  → une ligne par requête du serveur local (`GET /chemin → statut`) + événements du mode hors ligne.
- **Serveur local hors simulateur** : `LocalServer/`, `Offline/{AssetManifest,SnapshotStore,ShellPage,CSSPathRewriter}`,
  `Network/{ServerURL,NextcloudModels}`, `Auth/Credentials`, `App/Log` compilent avec `swiftc` sur macOS
  (harnais + faux Nextcloud en Python + `curl`).
- **Signature** : un manifeste signé par Node avec la graine par défaut de `webpack.manifest-sign-plugin.ts`
  doit être accepté en Debug et refusé en Release.
- Simulateur avec le compte de l'utilisateur : **iPhone 17 Pro** (ne rien supprimer, ne pas se déconnecter :
  la déconnexion révoque le mot de passe d'application).

## Tester le JS du pont

`nativex.js` peut être testé hors simulateur avec Node en simulant `window.webkit.messageHandlers`,
`XMLHttpRequest` et `ProgressEvent`. Inspection réelle : Safari > Développement > Simulateur.

## Prochaines étapes

Photos locales (PhotoKit) **mises de côté** : l'utilisateur fait l'upload auto avec l'app Nextcloud
officielle, et le renommage/conversion HEIC de celle-ci casserait le dédoublonnage AUID/BUID.
Pour mémoire :

PhotoKit (`/api/days`, `/api/days/{id}`, `/api/image/info`, suppression, upload), AUID/BUID identiques
au serveur (`docs/ANALYSE.md` §7.3), serveur local 127.0.0.1 pour `/image/*` et `/video/*`,
`configHasMediaPermission`/`getSyncStatus` réels poussés via `window.__nativexSetState`,
écran `nxsetup` (choix des albums), événement `nativex:db:updated` sur changement de la photothèque.

## Git

Un commit par étape fonctionnelle, message en français, trailer `Co-Authored-By` Claude.
