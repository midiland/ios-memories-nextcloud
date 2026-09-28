// Pont NativeX côté page — injecté par l'app iOS au début du document (WKUserScript).
//
// Définit `window.nativex`, que le frontend Memories lit au chargement de ses modules
// (src/native/api.ts) pour activer le mode « app native ». Équivalent de
// `addJavascriptInterface(NativeX, "nativex")` sur Android.
//
// - Méthodes « fire-and-forget » → `webkit.messageHandlers.nativex.postMessage`.
// - Méthodes synchrones (le JS lit la valeur immédiatement) → valeurs en cache dans
//   `state`, initialisées par le natif à l'injection et mises à jour via
//   `window.__nativexSetState(...)`.
// - Pont asynchrone : le frontend appelle `http://127.0.0.1/api/...` (codé en dur).
//   WKWebView ne sait pas intercepter http, donc on détourne `fetch` et `XMLHttpRequest`
//   pour ces URLs et on les route vers le handler natif `nativexAsync` (avec réponse).
(() => {
  'use strict';
  if (window.nativex) return;

  const handlers = window.webkit && window.webkit.messageHandlers;
  if (!handlers || !handlers.nativex || !handlers.nativexAsync) return;

  /** Cache des valeurs lues de façon synchrone (remplacé par le natif à l'injection). */
  const state = __NATIVEX_STATE__;

  const post = (method, ...args) => handlers.nativex.postMessage({ method, args });

  window.nativex = {
    isNative: () => true,
    setThemeColor: (color, isDark) => post('setThemeColor', color == null ? null : String(color), !!isDark),
    playTouchSound: () => post('playTouchSound'),
    toast: (message, long) => post('toast', String(message), !!long),
    logout: () => post('logout'),
    reload: () => post('reload'),
    downloadFromUrl: (url, filename, title) => post('downloadFromUrl', url ?? null, filename ?? null, title ?? null),
    setShareBlobs: (objects) => post('setShareBlobs', objects == null ? null : String(objects)),
    configSetLocalFolders: (json) => {
      state.localFolders = json == null ? '[]' : String(json);
      post('configSetLocalFolders', state.localFolders);
    },
    configGetLocalFolders: () => state.localFolders,
    configHasMediaPermission: () => state.hasMediaPermission,
    getSyncStatus: () => state.syncStatus,
    setHasRemote: (auids, buids, value) => post('setHasRemote', String(auids), String(buids), !!value),
    // playVideo / playVideo2 / destroyVideo volontairement absents : le frontend
    // lit alors les vidéos avec son lecteur web (WebKit gère HLS nativement).
  };

  /** Mise à jour du cache par le natif (evaluateJavaScript). */
  Object.defineProperty(window, '__nativexSetState', {
    value: (patch) => Object.assign(state, patch),
  });

  // ---------------------------------------------------------------------------
  // Pont asynchrone http://127.0.0.1 → handler natif `nativexAsync`
  // ---------------------------------------------------------------------------

  const LOOPBACK = /^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?\//i;

  /** Envoie la requête au natif. Résout `{ status, contentType, body }`. */
  const loopback = (method, url) =>
    handlers.nativexAsync.postMessage({ method: String(method || 'GET').toUpperCase(), url });

  // --- fetch ---
  const originalFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input && input.url;
    if (!url || !LOOPBACK.test(url)) return originalFetch(input, init);

    const method = (init && init.method) || (input instanceof Request ? input.method : 'GET');
    return loopback(method, url).then(
      (r) => new Response(r.body, { status: r.status, headers: { 'Content-Type': r.contentType } }),
      () => Promise.reject(new TypeError('NativeX: requête locale échouée')),
    );
  };

  // --- XMLHttpRequest (utilisé par axios) ---
  const XHR = XMLHttpRequest.prototype;
  const originalOpen = XHR.open;
  const originalSend = XHR.send;
  const originalSetRequestHeader = XHR.setRequestHeader;

  /** Remplace une propriété en lecture seule de l'instance XHR. */
  const define = (xhr, props) => {
    for (const [key, value] of Object.entries(props)) {
      Object.defineProperty(xhr, key, { value, configurable: true });
    }
  };
  const fire = (xhr, type) => xhr.dispatchEvent(new ProgressEvent(type));

  XHR.open = function (method, url, ...rest) {
    const href = String(url);
    this.__nx = LOOPBACK.test(href) ? { method, url: href } : null;
    if (this.__nx) return; // pas de vraie connexion
    return originalOpen.call(this, method, url, ...rest);
  };

  XHR.setRequestHeader = function (...args) {
    if (this.__nx) return;
    return originalSetRequestHeader.apply(this, args);
  };

  XHR.send = function (body) {
    if (!this.__nx) return originalSend.call(this, body);
    const xhr = this;
    const { method, url } = xhr.__nx;
    loopback(method, url).then(
      (r) => {
        let response = r.body;
        if (xhr.responseType === 'json') {
          try { response = JSON.parse(r.body); } catch { response = null; }
        }
        define(xhr, {
          readyState: 4,
          status: r.status,
          statusText: '',
          responseText: r.body,
          response,
          responseURL: url,
          getAllResponseHeaders: () => `content-type: ${r.contentType}\r\n`,
          getResponseHeader: (name) => (String(name).toLowerCase() === 'content-type' ? r.contentType : null),
        });
        fire(xhr, 'readystatechange');
        fire(xhr, 'load');
        fire(xhr, 'loadend');
      },
      () => {
        define(xhr, { readyState: 4, status: 0 });
        fire(xhr, 'readystatechange');
        fire(xhr, 'error');
        fire(xhr, 'loadend');
      },
    );
  };
})();
