if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/service-worker.js").then(() => {
      window.__swRegistered = true;
    }).catch((err) => {
      console.warn("SW registration failed:", err);
    });
  });
}
