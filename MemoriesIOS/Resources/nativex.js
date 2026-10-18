// Page-side NativeX bridge — injected by the iOS app at document start (WKUserScript).
//
// Defines `window.nativex`, which the Memories frontend reads when its modules load
// (src/native/api.ts) to enable "native app" mode. Equivalent of
// `addJavascriptInterface(NativeX, "nativex")` on Android.
//
// - Fire-and-forget methods → `webkit.messageHandlers.nativex.postMessage`.
// - Synchronous methods (the JS reads the value immediately) → values cached in
//   `state`, initialized by the native side at injection and updated via
//   `window.__nativexSetState(...)`.
// - Async bridge: the frontend calls `http://127.0.0.1/api/...` (hard-coded).
//   WKWebView cannot intercept http, so we hijack `fetch` and `XMLHttpRequest`
//   for these URLs and route them to the native `nativexAsync` handler (with reply).
(() => {
  'use strict';
  if (window.nativex) return;

  const handlers = window.webkit && window.webkit.messageHandlers;
  if (!handlers || !handlers.nativex || !handlers.nativexAsync) return;

  /** Cache of synchronously read values (replaced by the native side at injection). */
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
    // playVideo / playVideo2 / destroyVideo intentionally omitted: the frontend
    // then plays videos with its web player (WebKit handles HLS natively).
  };

  // Web controls the iOS app replaces or does not support yet:
  // - the web back arrows of the cluster headers (*TopMatter.vue: person, place, tag, album):
  //   the app shows a single native back button on every page that needs one
  //   (BackNavigationRule.swift). Matched by icon, not by the translated "Back" label;
  // - the upload button of the mobile header (UploadMenuItem.vue) and the "Upload Local" action
  //   of the selection bar (SelectionManager.vue, inline or in its overflow menu): upload is not
  //   implemented on iOS yet. Remove these rules once it is;
  // - the logo of the mobile header (MobileHeader.vue) when the navigation sidebar is open
  //   (wide screens, e.g. iPad): the header spans the whole width and its logo covers the sidebar.
  const hideUnsupportedControls = () => {
    const style = document.createElement('style');
    style.textContent = [
      ':is(.face-top-matter, .places-top-matter, .top-matter) > :has(.arrow-left-icon) { display: none !important; }',
      '#mobile-header .upload-menu { display: none !important; }',
      ':is(.memories-top-bar button, li.action):has(.cloud-upload-icon) { display: none !important; }',
      'body:has(.app-navigation:not(.app-navigation--closed)) #mobile-header .logo { visibility: hidden; }',
    ].join('\n');
    document.head.appendChild(style);
  };
  if (document.head) hideUnsupportedControls();
  else document.addEventListener('DOMContentLoaded', hideUnsupportedControls, { once: true });

  /** Cache update from the native side (evaluateJavaScript). */
  Object.defineProperty(window, '__nativexSetState', {
    value: (patch) => Object.assign(state, patch),
  });

  // ---------------------------------------------------------------------------
  // Async bridge http://127.0.0.1 → native `nativexAsync` handler
  // ---------------------------------------------------------------------------

  // Only the bridge routes (`/api/...` at the root, `NAPI` in `src/native/api.ts`): in local mode the
  // page itself is served from 127.0.0.1, and its other requests (HLS playlists and segments,
  // Nextcloud APIs, device images) must reach the local server.
  const LOOPBACK = /^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/api\//i;

  /** Sends the request to the native side. Resolves to `{ status, contentType, body }`. */
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
      () => Promise.reject(new TypeError('NativeX: local request failed')),
    );
  };

  // --- XMLHttpRequest (used by axios) ---
  const XHR = XMLHttpRequest.prototype;
  const originalOpen = XHR.open;
  const originalSend = XHR.send;
  const originalSetRequestHeader = XHR.setRequestHeader;

  /** Overrides read-only properties of the XHR instance. */
  const define = (xhr, props) => {
    for (const [key, value] of Object.entries(props)) {
      Object.defineProperty(xhr, key, { value, configurable: true });
    }
  };
  const fire = (xhr, type) => xhr.dispatchEvent(new ProgressEvent(type));

  XHR.open = function (method, url, ...rest) {
    const href = String(url);
    this.__nx = LOOPBACK.test(href) ? { method, url: href } : null;
    if (this.__nx) return; // no real connection
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
