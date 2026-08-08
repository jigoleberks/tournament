// A browser tab on iOS/iPadOS that is NOT the installed home-screen app —
// where PushManager doesn't exist and installing is the fix. Shared by the
// push toggle and the install-coach banner so the two can never disagree.
// iPadOS 13+ masquerades as Macintosh in the UA; maxTouchPoints tells it apart.
export function iosBrowserTab() {
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1)
  const standalone = window.matchMedia("(display-mode: standalone)").matches ||
    window.navigator.standalone === true
  return ios && !standalone
}
