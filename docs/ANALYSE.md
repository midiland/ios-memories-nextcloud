# Analyse de l'app Android Memories → portage iOS

Référence analysée : `reference/memories` (clone `--depth 1` de `pulsejet/memories`,
commit `20ffc54`, 28/09/2026, branche après `v9.1.0-alpha.2`).
Code Android : `reference/memories/android/app/src/main/java/gallery/memories/`.

---

## 0. Constat principal : ce n'est plus un simple wrapper "WebView → serveur"

L'hypothèse de départ (« une WebView qui charge l'UI depuis le serveur + `shouldInterceptRequest` »)
correspond aux **anciennes** versions de l'app. La version actuelle est différente :

- **Aucun `shouldInterceptRequest`** dans le code (vérifié par grep).
- L'app embarque un **serveur HTTP local Ktor/CIO** sur `http://127.0.0.1:62079`
  (`server/LocalHttpServer.kt`). La WebView ne charge **jamais** une page du serveur Nextcloud :
  elle charge tout depuis `127.0.0.1`.
- Les fichiers JS/CSS de Memories sont **téléchargés et mis en cache** (« snapshot hors-ligne »)
  à partir d'un manifeste **signé Ed25519** renvoyé par `GET …/apps/memories/api/describe?manifest=1`
  (`data/remote/assets/*`, `ManifestVerifier.kt`).
- La page HTML est un **« shell » généré localement** (`server/shell/ShellPage.kt`) qui imite le
  template PHP de Nextcloud (`_oc_webroot`, `_oc_capabilities`, CSS, l10n, CSP à nonce).
- Toutes les autres requêtes (API Memories, WebDAV, OCS…) sont **proxifiées** vers Nextcloud par
  le serveur local, qui ajoute `Authorization: Basic` + `OCS-APIREQUEST: true`
  (`server/controllers/ProxyController.kt`). Le JS est donc toujours *same-origin*.
- Les routes `/api/*` et `/image/*` sur 127.0.0.1 sont le **pont asynchrone NativeX**
  (`bridge/ApiRouter.kt`), `/video/full/{id}` sert les vidéos locales avec support `Range`.

Conséquence : « authentifié de la même façon qu'Android » = *le natif injecte les identifiants
dans chaque requête* ; la WebView elle-même n'a jamais de cookie de session Nextcloud.

---

## 1. Configuration de la WebView

Fichiers : `ui/web/WebViewSetup.kt`, `MainActivity.kt`, `ui/web/MemoriesWebViewClient.kt`,
`ui/web/MemoriesWebChromeClient.kt`, `ui/startup/AppStartupCoordinator.kt`.

| Réglage | Valeur |
|---|---|
| JavaScript | activé |
| DOM storage | activé |
| Popups / multi-fenêtres | désactivés (`window.open` retombe dans `shouldOverrideUrlLoading`) |
| Zoom | désactivé |
| User-Agent | `MemoriesNative/<version> ` + UA par défaut |
| Fond | transparent (le thème natif est peint derrière) |
| Interface JS | `addJavascriptInterface(NativeX, "nativex")` → `window.nativex` |
| Debug | `setWebContentsDebuggingEnabled(true)` en build debug |
| Cookie | cookie HttpOnly `local-auth=<uuid par process>` posé sur `http://127.0.0.1/` **avant** le premier chargement ; le serveur local rejette (403) toute requête sans lui |

### URLs chargées (`AppStartupCoordinator`)
1. Pas connecté → `http://127.0.0.1:62079/local/static/welcome.html` (page embarquée dans l'APK).
2. Connecté + snapshot en cache → `http://127.0.0.1:62079<webroot>/` (shell local),
   puis vérification de mise à jour en arrière-plan.
3. Connecté sans snapshot → `…/local/static/waiting.html` (progression via `/api/assets/progress`),
   puis le shell.
4. Après un login → `…<webroot>/index.php/apps/memories/nxsetup` (écran de config native).

### Navigation (`MemoriesWebViewClient`)
- Seules les pages loopback restent dans la WebView ; tout autre lien part dans le navigateur.
- Un chemin loopback qui correspond à un chemin *proxifié* est « déballé » vers l'URL réelle du
  serveur et ouvert dehors (`LocalHttpServer.browserUrlFor`).
- `data:`, `blob:`, `javascript:` en navigation top-level : bloqués.
- Erreurs réseau / HTTP du main frame → toast.
- Erreur SSL : `proceed()` seulement si l'utilisateur a coché « faire confiance à tous les certificats ».
- `WebChromeClient` : accorde toutes les permissions, sélecteur de fichiers pour l'upload,
  poster vidéo transparent.

---

## 2. Login Nextcloud

Fichiers : `assets/welcome.html`, `auth/AccountManager.kt`, `data/remote/http/*`,
`data/local/secure/SecureCredentialStore.kt`.

**Oui, c'est Login Flow v2.** Séquence :

1. `welcome.html` normalise l'URL saisie : ajoute `https://` si absent, `/`, `index.php/`
   puis `apps/memories/` → ex. `https://cloud.exemple.fr/index.php/apps/memories/`.
2. Le JS appelle le pont : `GET /api/login/{url doublement encodée}?trustAll=0|1`.
3. Natif : `GET <url>api/describe?manifest=1` → vérifie 200 + signature du manifeste,
   récupère `baseUrl` et `loginFlowUrl` (= `/index.php/login/v2`). Lance la synchro des assets.
4. `POST loginFlowUrl` → `{ poll: { token, endpoint }, login }`.
5. Ouvre `login` dans le **navigateur système** (`Intent.ACTION_VIEW`), affiche `waiting.html?login=1`.
6. Thread de polling : `POST poll.endpoint` avec `token=…` toutes les **3 s** pendant **10 min**
   (le commentaire dit 30 min, le code fait 10). 200 → `{ server, loginName, appPassword }`.
   Un compteur de « génération » invalide les polls obsolètes (retry/logout).
7. Stockage : `SharedPreferences` avec URL, `trustAll`, username en clair + **token chiffré**
   (AES/CBC, clé dans l'Android Keystore).
8. Au démarrage : `checkCredentialsAndVersion()` → `GET api/describe` ; 401 ou `uid == null`
   → déconnexion ; version < `9.0.0-rc.1` → avertissement.

**Utilisation des identifiants** : header `Authorization: Basic base64(loginName:appPassword)` sur
chaque requête proxifiée. En plus, un `SessionCookieJar` persistant renvoie les cookies `oc*`
reçus : la doc interne mesure ~1 s/requête en Basic seul contre ~0,06 s avec session (×17).

**Logout** : `nativex.logout()` (appelé par le JS après `GET /logout`) → efface identifiants et
cookies, recharge `welcome.html`.

---

## 3. Méthodes exposées via `addJavascriptInterface` (`NativeX.kt`)

Toutes les méthodes `@JavascriptInterface` sont **synchrones côté JS** (le thread JS bloque
jusqu'au retour). La colonne « Retour utilisé » indique si le JS a réellement besoin de la valeur.

| # | Signature Kotlin | Retour utilisé par le JS ? | Comportement |
|---|---|---|---|
| 1 | `isNative(): Boolean` | oui (mais seule l'existence de `window.nativex` est testée) | `true` |
| 2 | `setThemeColor(color: String?, isDark: Boolean)` | non | couleur barres système ; mémorisée une fois par login |
| 3 | `playTouchSound()` | non | son de clic |
| 4 | `toast(message: String, long: Boolean = false)` | non | toast natif |
| 5 | `logout()` | non | efface identifiants, retour à welcome |
| 6 | `reload()` | non | recharge l'URL par défaut |
| 7 | `downloadFromUrl(url: String?, filename: String?, title: String?)` | non | téléchargement en arrière-plan + notification |
| 8 | `setShareBlobs(objects: String?)` | non, **mais doit être pris en compte avant** le `GET /api/share/blobs` qui suit immédiatement | JSON `[{auid, href}]` |
| 9 | `playVideo(auid: String, fileid: Long, urlsArray: String)` | non | alias de `playVideo2(…, false)` |
| 10 | `playVideo2(auid: String, fileid: Long, urlsArray: String, loop: Boolean = false)` | non | lecteur ExoPlayer natif superposé ; fichier local si l'AUID est indexé, sinon 1ʳᵉ URL |
| 11 | `destroyVideo(fileid: Long)` | non | ferme le lecteur si même `fileid` |
| 12 | `configSetLocalFolders(json: String?)` | non | dossiers locaux affichés dans la timeline |
| 13 | `configGetLocalFolders(): String` | **OUI, synchrone** | JSON `[{id, name, enabled}]` |
| 14 | `configHasMediaPermission(): Boolean` | **OUI, synchrone** | opt-in utilisateur ET permission OS |
| 15 | `getSyncStatus(): Int` | **OUI, synchrone** (déclaré dans `api.ts`) | nb de fichiers indexés, `-1` si pas de synchro |
| 16 | `setHasRemote(auids: String, buids: String, value: Boolean)` | non | marque des fichiers locaux comme présents sur le serveur |

Le JS teste aussi `typeof nativex?.playVideo2 === 'function'` : toutes les fonctions doivent
**exister réellement** sur l'objet (pas de proxy « catch-all » naïf).

### Pont asynchrone HTTP (`/api/*`, `/image/*`, `/video/*` sur 127.0.0.1) — `ApiRouter.kt`

GET uniquement (+ OPTIONS), en-têtes CORS `*`, erreurs → 500 `{}`.

| Route | Rôle |
|---|---|
| `/api/login/{url}` `?trustAll` | lance le login (§2) |
| `/api/days` | jours contenant des photos locales (`IDay[]`) |
| `/api/days/{dayId}` | photos locales d'un jour (`IPhoto[]`) |
| `/api/image/info/{fileId}` | métadonnées (`IImageInfo`) |
| `/api/image/delete/{auid,…}` `?dry` | suppression locale (dialogue système) |
| `/image/preview/{fileId}` `?x&y` | miniature JPEG (cache 7 j) |
| `/image/full/{auid}` `?size` | image pleine JPEG |
| `/video/full/{fileId}` | flux vidéo local, supporte `Range` |
| `/api/upload/local` `?auid&filename` | upload natif WebDAV d'un fichier local |
| `/api/share/url/{url}` | feuille de partage d'une URL |
| `/api/share/blobs` | télécharge les blobs posés par `setShareBlobs` puis les partage |
| `/api/config/allow_media/{0|1}` | demande la permission médias + synchro complète |
| `/api/assets/progress` | progression du téléchargement des assets |

### Natif → JS
`evaluateJavascript("window._nc_event_bus?.emit('<event>', <data>)")` avec notamment
`nativex:db:updated` et `memories:timeline:soft-refresh` (index local modifié), différé si l'app
est en pause (`ui/web/JsEventBus.kt`).

---

## 4. Interception de requêtes

Il n'y a **pas** de `shouldInterceptRequest`. Son rôle est tenu par le serveur local
(`server/ServerRouter.kt`), dans cet ordre :

1. Cookie `local-auth` absent → 403.
2. `/video/full/\d+` → vidéo locale (Range).
3. `/api/*`, `/image/*` → pont NativeX (fonctionne même non connecté).
4. `/local/static/*` → fichiers embarqués (welcome, waiting, CSS d'override).
5. `/local/assets/js|css/*` → fichiers du snapshot ; autre `/local/*` → 404.
6. `/favicon.ico` → 404 local.
7. `<webroot>/(index.php/)apps/memories/js/*` en GET → servi depuis le snapshot.
8. Entrée (`/`, `<webroot>/`) ou route de l'app acceptant `text/html` → **shell local**.
9. Toute autre navigation de document → 404 (jamais de HTML distant rendu comme page locale).
10. Sinon → **proxy** vers Nextcloud (tous verbes, y compris PROPFIND/REPORT/SEARCH),
    réécriture des `Location`, réseau KO → 504 (le frontend l'interprète comme « hors-ligne »).

---

## 5. Côté frontend (`reference/memories/src/native/`)

- **Détection** : `src/native/api.ts` → `export const nativex = globalThis.nativex` ;
  `has()` = `!!nativex`. Évalué **au chargement du module** : `window.nativex` doit exister
  **avant** l'exécution du bundle (→ `WKUserScript` en `.atDocumentStart`).
- **URL du pont** : `BASE_URL = location.hostname === '127.0.0.1' ? location.origin : 'http://127.0.0.1'`.
  ⇒ le pont asynchrone est **codé en dur sur 127.0.0.1**.
- `initialize()` (appelé par `main.ts`) : désactive l'alerte « navigateur non supporté »,
  `initShellSync()` (langue/locale/l10n empaquetée), écoute le thème système.
- Service worker désactivé quand `has()`.

| Fonction JS | Fichier | Appel NativeX |
|---|---|---|
| `setTheme()` | `basic.ts` (App, FirstStart, Viewer, Setup) | `setThemeColor` |
| `playTouchSound()` | `basic.ts` (MobileNav, Cluster, Viewer, SelectionManager) | `playTouchSound` |
| `logout()` | `basic.ts` (Settings) | `GET /logout` puis `nativex.logout()` |
| `getLocalFolders / setLocalFolders` | `config.ts` (Settings, Setup) | `configGetLocalFolders` (sync) / `configSetLocalFolders` |
| `configHasMediaPermission()` | `config.ts` (Setup) | sync |
| `configAllowMedia()` | `config.ts` | `fetch NAPI.CONFIG_ALLOW_MEDIA` |
| `getLocalDays / getLocalDay / processFreshServerDay` | `days.ts` (Timeline) | `NAPI.DAYS`, `NAPI.DAY`, `setHasRemote` |
| `deleteLocalPhotos` | `days.ts` (dav/base.ts) | `NAPI.IMAGE_DELETE` |
| URLs d'images locales | `services/utils/helpers.ts` | `NAPI.IMAGE_PREVIEW/FULL/INFO` |
| `playVideo / destroyVideo / getLocalVideoUrl` | `video.ts` (PsVideo) | `playVideo2`/`playVideo`, `destroyVideo`, `NAPI.VIDEO_FULL` |
| `downloadFromUrl` | `share.ts` (dav/download.ts) | `downloadFromUrl` |
| `shareUrl` | `share.ts` (NodeShareModal, AlbumCollaborators) | `NAPI.SHARE_URL` |
| `shareBlobs` | `share.ts` (ShareModal) | `setShareBlobs` puis `NAPI.SHARE_BLOBS` |
| upload local | `UploadModal.vue` | `NAPI.UPLOAD_LOCAL` |

---

## 6. Tableau de correspondance Android → iOS proposé

| Android | iOS proposé |
|---|---|
| `WebView` + réglages | `WKWebView` dans `UIViewRepresentable`, `WKWebViewConfiguration` partagée, `customUserAgent = "MemoriesNative/<v> …"`, `isInspectable = true` en Debug (iOS 16.4+) |
| `addJavascriptInterface(…,"nativex")` | `WKUserScript` (`.atDocumentStart`, main frame) qui définit `window.nativex` en JS ; chaque méthode appelle `webkit.messageHandlers.nativex.postMessage({method, args})` |
| Méthodes sync (`configGetLocalFolders`, `configHasMediaPermission`, `getSyncStatus`, `isNative`) | Valeurs **mises en cache côté JS** : injectées au document-start, puis rafraîchies par `evaluateJavaScript` quand elles changent. Repli possible : astuce `prompt()` + `WKUIDelegate.runJavaScriptTextInputPanel` (vraiment bloquant) |
| Serveur Ktor 127.0.0.1 (pont + proxy + shell) | Option A : `WKURLSchemeHandler` sur schéma custom `memories-app://` ; Option B : mini serveur HTTP local (`Network.framework`/`NWListener`) sur 127.0.0.1 + `NSAllowsLocalNetworking` (voir §7) |
| Cookie `local-auth` | `WKHTTPCookieStore.setCookie` avant le premier `load` (option B) ; inutile en option A |
| `SecureCredentialStore` (Keystore) | **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) |
| `SessionCookieJar` | `HTTPCookieStorage` d'une `URLSession` dédiée (persistant par défaut) |
| Login Flow v2 + navigateur système | `ASWebAuthenticationSession` (ou `SFSafariViewController`) + polling `URLSession` async/await |
| `trustAll` (certificats auto-signés) | `URLSessionDelegate` (challenge serverTrust) + `WKNavigationDelegate.didReceive challenge` — à éviter/retarder (option explicite) |
| `welcome.html` / `waiting.html` | Écrans **SwiftUI** natifs |
| `setThemeColor` | couleur de fond + `preferredColorScheme` / style de la status bar |
| `playTouchSound` | `UIDevice.current.playInputClick()` (nécessite `UIInputViewAudioFeedback`) ou `UIImpactFeedbackGenerator` |
| `toast` | overlay SwiftUI temporaire |
| `logout` / `reload` | callbacks vers le `SessionStore` SwiftUI |
| `downloadFromUrl` | `URLSession` download → `UIActivityViewController` / enregistrement Photos (`PHPhotoLibrary`) |
| `setShareBlobs` + `/api/share/blobs`, `/api/share/url` | `UIActivityViewController` |
| `playVideo2` / `destroyVideo` (ExoPlayer) | `AVPlayerViewController` ou `AVPlayerLayer` superposé ; ou laisser la `<video>` HTML jouer (WebKit lit HLS nativement) |
| MediaStore (`/api/days`, `/image/*`, `/video/full`) | **PhotoKit** : `PHAsset.fetchAssets`, `PHImageManager` (miniatures/pleine taille), `PHAssetResource` / `requestAVAsset` (vidéo) |
| Room (index local) | SQLite (GRDB) ou SwiftData/Core Data — index `PHAsset.localIdentifier` ↔ id numérique ↔ AUID/BUID |
| `/api/image/delete` (dialogue système) | `PHAssetChangeRequest.deleteAssets` (iOS affiche sa propre confirmation) |
| `/api/upload/local` | `URLSession` upload WebDAV (`PUT remote.php/dav/files/<uid>/…`) depuis un fichier exporté du `PHAsset` |
| `nativex:db:updated` via `evaluateJavascript` | `PHPhotoLibraryChangeObserver` → `webView.evaluateJavaScript("window._nc_event_bus?.emit(…)")` |
| Permissions médias | `PHPhotoLibrary.requestAuthorization(for: .readWrite)` (+ accès limité) |
| Sélecteur de fichiers (`onShowFileChooser`) | géré nativement par WKWebView (`<input type=file>`) |
| Bouton retour Android | geste de swipe (`allowsBackForwardNavigationGestures`) |

---

## 7. Difficultés et décisions à prendre

### 7.1 Appels synchrones impossibles avec `WKScriptMessageHandler`
`postMessage` est asynchrone ; `WKScriptMessageHandlerWithReply` renvoie une **Promise**, pas une
valeur. Or `configGetLocalFolders()`, `configHasMediaPermission()`, `getSyncStatus()` sont lus
de façon synchrone (`JSON.parse(nativex.configGetLocalFolders())`).
→ **Solution retenue** : l'objet JS garde un cache (`window.nativex._state`) rempli au
document-start par le natif et mis à jour par `evaluateJavaScript` à chaque changement ; les
setters mettent à jour le cache JS immédiatement **et** notifient le natif.
→ Repli : `prompt()` synchrone intercepté par `WKUIDelegate` (fonctionne, mais hack).

### 7.2 Interception http/https impossible avec `WKURLSchemeHandler`
`WKURLSchemeHandler` ne peut pas enregistrer `http`/`https` (exception au runtime). Or le frontend
appelle le pont sur **`http://127.0.0.1…`** (codé en dur dans `api.ts`).
Options :
- **A. Schéma custom** (`memories-app://app/…`) servant shell + assets et proxifiant l'API via
  `URLSession`. Tout est same-origin, pas de port ouvert. **Mais** `NAPI.*` pointe vers
  `http://127.0.0.1` (car `hostname !== '127.0.0.1'`) → nécessite soit un patch du frontend
  (utiliser `location.origin` en mode natif — PR amont à proposer), soit l'option B pour le pont.
  Autres limites : pas de service worker, `Range` à implémenter soi-même pour `<video>`,
  corps de requêtes POST parfois dans `httpBodyStream` à lire, cookies sur schéma custom capricieux.
- **B. Serveur HTTP local** sur 127.0.0.1 (NWListener / lib type FlyingFox/Swifter), comme Android.
  Compatible avec le frontend **sans modification**. Nécessite `NSAppTransportSecurity >
  NSAllowsLocalNetworking = YES`, un secret (cookie) comme Android, et le serveur est suspendu
  en arrière-plan (à redémarrer au retour au premier plan).
- **C. Chargement direct du serveur distant** (`https://serveur/index.php/apps/memories/`),
  authentifié par cookie de session. Le plus simple, mais le pont `http://127.0.0.1` devient
  une requête cross-origin http depuis une page https (mixed content ; WebKit traite le loopback
  comme « potentiellement fiable », à vérifier) + CORS, et on perd le mode hors-ligne.

### 7.3 PHAsset vs chemins de fichiers
- Android identifie les médias par un **ID MediaStore `Long`** (utilisé comme `fileid` et dans
  `/image/preview/{id}`, `/video/full/{id}` qui imposent `\d+`). iOS a `localIdentifier`
  (chaîne type `UUID/L0/001`) → il faut une **table de correspondance** id numérique ↔ identifiant.
- **AUID** = `md5("<epoch><taille>")`, **BUID** = `md5("<nomFichier>" + "iuid=<EXIF ImageUniqueID>" | "size=<taille>")`.
  Ils doivent être **identiques à ceux calculés par le serveur** pour dédoublonner local/distant.
  Sur iOS : la taille et le nom d'origine viennent de `PHAssetResource` (`originalFilename`, clé
  privée `fileSize` via KVC — non documentée), l'EXIF impose de lire les données (coûteux, iCloud).
- Photos **dans iCloud** (non téléchargées) : `PHImageManager` doit autoriser le réseau ;
  latence et coût à gérer.
- Pas de « dossiers » sur iOS : les `LocalFolders` deviennent des **albums** (`PHAssetCollection`).
- HEIC : `/image/full` doit renvoyer du JPEG → conversion.
- Suppression : iOS affiche sa propre alerte (pas de mode `dry` natif).

### 7.4 Autres points
- **Signature du manifeste** (option A/B hors-ligne) : Ed25519 → `CryptoKit.Curve25519.Signing.PublicKey`
  (disponible iOS 13+), clés publiques à reprendre de `ManifestVerifier.kt`.
- **Login Flow v2 et `ASWebAuthenticationSession`** : le flow v2 ne redirige pas vers un schéma
  de callback ; la session se ferme manuellement quand le polling réussit (ou utiliser
  `SFSafariViewController`, plus naturel ici).
- **Performance Basic auth** (×17 plus lent sans session) : garder les cookies de session côté
  `URLSession`.
- **Lecture vidéo** : WebKit lit HLS nativement ; on peut ne pas implémenter `playVideo2`
  au début (le frontend retombe sur le lecteur web si la fonction n'existe pas).
- **Arrière-plan** : pas de synchro continue comme sur Android ; utiliser `BGTaskScheduler`
  plus tard.
- **App Store** : une app qui télécharge et exécute du JS distant est acceptée pour un wrapper
  web (règle 4.7 / 2.5.2 à surveiller), l'UI native minimale (login) aide.

---

## 8. Proposition pour le MVP (étape 1)

Puisque le pont NativeX n'est pas dans le MVP, je propose :

1. **MVP = option C (chargement direct du serveur)** : après Login Flow v2, une `URLSession`
   fait `GET …/apps/memories/api/describe` en Basic auth → Nextcloud renvoie les cookies de
   session (`oc…`, `nc_session_id`, `nc_sameSiteCookie*`), qu'on **copie dans
   `WKHTTPCookieStore`** ; la WebView charge ensuite `…/index.php/apps/memories/` et la page
   est rendue authentifiée par le serveur. Le premier `load` envoie aussi le header
   `Authorization` en secours. Si la session expire (redirection vers `/login`), on refait
   l'amorçage automatiquement.
   Vérification « Memories installé » : `api/describe` → 404 = non installé ; erreur réseau =
   serveur injoignable ; version minimale `9.0.0-rc.1`.
2. **Étape NativeX (suivante)** : passer à l'option **B (serveur local 127.0.0.1)**, qui
   reproduit fidèlement Android et évite de patcher le frontend ; le code réseau/auth du MVP
   (`NextcloudClient`, `CredentialStore`) sera réutilisé tel quel par le proxy.

Structure envisagée (`MemoriesIOS/`) :
```
Sources/
  App/            MemoriesApp.swift, RootView.swift
  Auth/           LoginFlowV2.swift, CredentialStore.swift (Keychain), SessionStore.swift
  Network/        NextcloudClient.swift, ServerURL.swift, AppError.swift
  Views/          LoginView.swift, WebContainerView.swift, ErrorView.swift
  Web/            MemoriesWebView.swift (UIViewRepresentable), WebViewCoordinator.swift, CookieBridge.swift
  NativeX/        NativeXBridge.swift (protocole), NativeXMethod.swift, nativex.js (vide pour l'instant)
```
