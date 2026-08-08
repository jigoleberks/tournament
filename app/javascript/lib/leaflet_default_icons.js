import L from "leaflet"

// Propshaft digests the vendored leaflet.css AND its marker images, which
// defeats Leaflet's runtime icon-path detection: it regex-strips a literal
// "marker-icon.png" suffix from the CSS url() (now digested), and its
// stylesheet-href fallback looks for a link ending in "leaflet.css" (also
// digested) — so imagePath resolves to "" and every default marker requests a
// page-relative marker-icon.png that 404s. The layouts emit the digested
// image URLs as meta tags; wire them into Icon.Default explicitly.
export function configureDefaultIcons() {
  const url = (name) => document.querySelector(`meta[name='${name}']`)?.content
  const iconUrl = url("leaflet-marker-icon")
  if (!iconUrl) return
  // A string imagePath suppresses detection; it is prepended to every icon
  // URL, so it must be empty for the absolute URLs below to survive.
  L.Icon.Default.imagePath = ""
  L.Icon.Default.mergeOptions({
    iconUrl: iconUrl,
    iconRetinaUrl: url("leaflet-marker-icon-2x") || iconUrl,
    shadowUrl: url("leaflet-marker-shadow")
  })
}
