if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js").then((reg) => {
      window.__swRegistered = true;
      // Keep the precached /offline shell's embedded species list fresh
      // between deploys. Once per page load, online only.
      if (navigator.onLine && reg.active) reg.active.postMessage({ type: "refresh-shell" });
    }).catch((err) => {
      console.warn("SW registration failed:", err);
    });
  });
}
