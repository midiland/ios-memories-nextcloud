// Swipe-to-select enhancement for iOS (midiland/ios-memories-nextcloud#11).
//
// Injected at document start via WKUserScript (same mechanism as nativex.js).
// The web app already implements the long-press + swipe gesture (SelectionManager.vue
// in pulsejet/memories). This script adds iOS-specific improvements:
//
// 1. Haptic feedback when photos are selected/deselected during a swipe
// 2. Prevents the native scroll from stealing touchmove events during swipe-select
// 3. Manual auto-scroll when swiping near the screen edges (the web app's own
//    auto-scroll may not work reliably on iOS WKWebView)
// 4. Allows normal scrolling when the user is NOT swiping over photos
//
// The CSS (swipe-select.css) sets touch-action: pan-y by default and touch-action: none
// on photos in selection mode. This script adds the non-passive touchmove handler
// needed to preventDefault() during swipe-select, plus manual auto-scroll.
(() => {
  'use strict';

  // Only run when the NativeX bridge is present (i.e., inside the iOS app).
  const isNative = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativex);
  if (!isNative) return;

  // Guard against double-injection
  if (window.__swipeSelectInstalled) return;
  window.__swipeSelectInstalled = true;

  // Haptic feedback helper — uses the existing nativex.playTouchSound bridge.
  const haptic = () => {
    try {
      window.webkit.messageHandlers.nativex.postMessage({ method: 'playTouchSound', args: [] });
    } catch (e) { /* bridge not ready yet */ }
  };

  // ---------------------------------------------------------------------------
  // Haptic feedback on selection change
  // ---------------------------------------------------------------------------

  let lastSelectedCount = 0;
  let hapticCooldown = 0;

  const checkSelectionChange = () => {
    const selected = document.querySelectorAll('.recycler .p-outer.selected');
    const count = selected.length;
    if (count !== lastSelectedCount) {
      lastSelectedCount = count;
      // Throttle haptics: at most one per 50ms during a fast swipe
      const now = Date.now();
      if (now - hapticCooldown > 50) {
        hapticCooldown = now;
        haptic();
      }
    }
  };

  // Observe DOM mutations to detect selection changes (Vue updates classes reactively).
  const observer = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      if (mutation.type === 'attributes' && mutation.attributeName === 'class') {
        const target = mutation.target;
        if (target.classList && target.classList.contains('p-outer')) {
          checkSelectionChange();
          return;
        }
      }
      if (mutation.type === 'childList') {
        checkSelectionChange();
        return;
      }
    }
  });

  const startObserver = () => {
    const recycler = document.querySelector('.recycler');
    if (recycler) {
      observer.observe(recycler, {
        attributes: true,
        attributeFilter: ['class'],
        childList: true,
        subtree: true,
      });
      window.__swipeSelect.observerActive = true;
    } else {
      // Recycler not mounted yet — retry
      setTimeout(startObserver, 500);
    }
  };

  if (document.body) {
    startObserver();
  } else {
    document.addEventListener('DOMContentLoaded', startObserver, { once: true });
  }

  // ---------------------------------------------------------------------------
  // Swipe-select scroll management
  //
  // On iOS WKWebView, the native scroll interceptor may steal touchmove events
  // even with touch-action CSS. We add a non-passive touchmove listener on
  // document to preventDefault() during swipe-select, and implement manual
  // auto-scroll when the finger is near the screen edges.
  // ---------------------------------------------------------------------------

  // Auto-scroll constants (matching SelectionManager.vue's TOUCH_SELECT_CLAMP)
  const CLAMP_TOP = 110;      // px from top where auto-scroll kicks in
  const CLAMP_BOTTOM = 110;   // px from bottom where auto-scroll kicks in
  const MAX_DELTA = 10;       // max scroll speed per frame

  let swipeState = {
    active: false,        // true while swiping over photos in selection mode
    startY: 0,            // touch start Y position
    lastY: 0,             // last touch Y position (for delta calculation)
    rafId: 0,             // requestAnimationFrame ID for auto-scroll
  };

  const isSelectionMode = () => !!document.querySelector('.recycler .p-outer.selected');

  const isOnPhoto = (target) => {
    return target && target.closest && target.closest('.recycler .p-outer-super, .recycler .photo');
  };

  // Manual auto-scroll: scroll the recycler when the finger is near the edges
  const autoScroll = (clientY) => {
    const recycler = document.querySelector('.recycler');
    if (!recycler) return;

    const height = window.innerHeight;
    let delta = 0;

    if (clientY < CLAMP_TOP) {
      // Near top: scroll up
      delta = Math.max((clientY - CLAMP_TOP) / 3, -MAX_DELTA);
    } else if (clientY > height - CLAMP_BOTTOM) {
      // Near bottom: scroll down
      delta = Math.min((clientY - height + CLAMP_BOTTOM) / 3, MAX_DELTA);
    }

    if (delta !== 0) {
      recycler.scrollTop += delta;
    }
  };

  // Start/stop the auto-scroll loop
  const startAutoScrollLoop = (clientY) => {
    if (swipeState.rafId) return; // already running
    const loop = () => {
      if (!swipeState.active) {
        swipeState.rafId = 0;
        return;
      }
      autoScroll(clientY);
      swipeState.rafId = requestAnimationFrame(loop);
    };
    swipeState.rafId = requestAnimationFrame(loop);
  };

  const stopAutoScrollLoop = () => {
    if (swipeState.rafId) {
      cancelAnimationFrame(swipeState.rafId);
      swipeState.rafId = 0;
    }
  };

  // touchstart: detect if we're starting a swipe-select gesture
  document.addEventListener('touchstart', (e) => {
    if (e.touches.length !== 1) {
      swipeState.active = false;
      return;
    }
    const touch = e.touches[0];
    // Only start swipe-select if:
    // 1. Selection mode is active (at least one photo selected), AND
    // 2. The touch started on a photo element
    if (isSelectionMode() && isOnPhoto(e.target)) {
      swipeState.active = true;
      swipeState.startY = touch.clientY;
      swipeState.lastY = touch.clientY;
    } else {
      swipeState.active = false;
    }
  }, { passive: true });

  // touchmove: NON-PASSIVE — we need preventDefault() to stop native scroll
  document.addEventListener('touchmove', (e) => {
    if (!swipeState.active || e.touches.length !== 1) return;

    const touch = e.touches[0];
    swipeState.lastY = touch.clientY;

    // Prevent the native scroll from stealing the gesture.
    // This is the key fix for iOS: without this, WebKit starts scrolling
    // and sends touchcancel, breaking the swipe-select.
    e.preventDefault();

    // Start auto-scroll if near the edges
    const height = window.innerHeight;
    if (touch.clientY < CLAMP_TOP || touch.clientY > height - CLAMP_BOTTOM) {
      startAutoScrollLoop(touch.clientY);
    } else {
      stopAutoScrollLoop();
    }
  }, { passive: false });

  // touchend / touchcancel: end the swipe-select gesture
  const endSwipe = () => {
    swipeState.active = false;
    stopAutoScrollLoop();
  };
  document.addEventListener('touchend', endSwipe, { passive: true });
  document.addEventListener('touchcancel', endSwipe, { passive: true });

  // ---------------------------------------------------------------------------
  // Debug handle (Safari Web Inspector)
  // ---------------------------------------------------------------------------
  window.__swipeSelect = {
    version: '2.0',
    observerActive: false,
    getSwipeState: () => ({ ...swipeState }),
  };
})();
