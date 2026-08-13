// The signed-in user id as the offline queue should stamp it. The layout meta
// is authoritative on a server-rendered page, but the precached /offline shell
// can carry the PREVIOUS user's meta after an account switch on a shared phone
// (the SW's shell re-cache is async and needs signal). Every online page view
// — full load or Turbo visit — mirrors its meta into localStorage (see
// layouts/application), so localStorage
// is always at least as fresh as any page this device can show — prefer it.
// "" means "was signed out on the last online page"; null (never written)
// falls back to the meta for devices that predate the mirror.
export function currentUserId() {
  let stored = null
  try { stored = localStorage.getItem("currentUserId") } catch (_) {}
  if (stored !== null) return stored || null
  return document.querySelector("meta[name='current-user-id']")?.content || null
}
