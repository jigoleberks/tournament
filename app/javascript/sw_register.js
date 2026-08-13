if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js").then((reg) => {
      window.__swRegistered = true;
      // Keep the precached /offline shell's embedded species list fresh
      // between deploys. Pinged once per page load; the SW throttles the
      // actual /offline re-fetch (~hourly) so page views don't double the
      // server's render load. No navigator.onLine gate — same
      // reason as offline/sync.js: WebKit's flag goes stale (false while
      // actually online) after backgrounding, and a wrongly-false flag here
      // left the shell stale despite working connectivity. The SW's fetch of
      // /offline just fails quietly when truly offline.
      if (reg.active) reg.active.postMessage({ type: "refresh-shell" });
    }).catch((err) => {
      console.warn("SW registration failed:", err);
    });
  });
}
