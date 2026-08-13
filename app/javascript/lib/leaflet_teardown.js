// Shared turbo:before-cache teardown wiring for Leaflet controllers
// (map_controller, location_edit_controller — each keeps its own teardown()).
//
// disconnect() alone can't protect a Turbo Drive restore: it runs after Turbo
// has already captured the page snapshot, so the cached copy would still hold
// the fully rendered panes (the clone loses the _leaflet_id expando, so the
// next connect() happily builds a second map on top — doubled markers, broken
// hit testing). turbo:before-cache fires before capture; tearing down there
// is what makes the snapshot clean.
export function bindBeforeCacheTeardown(controller) {
  controller.boundBeforeCache = () => controller.teardown()
  document.addEventListener("turbo:before-cache", controller.boundBeforeCache)
}

// Call from disconnect(): unbind, then tear down for the non-cached case.
export function unbindBeforeCacheTeardown(controller) {
  document.removeEventListener("turbo:before-cache", controller.boundBeforeCache)
  controller.teardown()
}
