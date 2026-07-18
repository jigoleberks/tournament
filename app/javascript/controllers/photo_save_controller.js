import { Controller } from "@hotwired/stimulus"

// Saves a photo to the device. Prefers the Web Share API (so iOS users
// can pick "Save Image" and the file lands in Photos). Falls back to a
// synthetic anchor download on desktop / older browsers.
export default class extends Controller {
  static values = { url: String, filename: String }

  async save(event) {
    event.preventDefault()

    // Cache the blob across taps: on slow cellular the fetch below can outlive
    // iOS's transient user activation, making share() reject NotAllowedError.
    // The second tap then shares the cached blob immediately, well inside its
    // own activation window.
    let blob = this._blob
    if (!blob) {
      try {
        const response = await fetch(this.urlValue)
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        blob = await response.blob()
        this._blob = blob
      } catch (err) {
        console.warn("photo-save: fetch failed", err)
        alert("Couldn't load photo. Try again when online.")
        return
      }
    }

    // Android's share sheet hides "Save image" behind a list of apps on
    // older Samsung One UI versions, so anchor-download is more reliable
    // there — files land in Downloads and the media scanner surfaces them
    // in Gallery. iOS keeps the Web Share path so users can save to Photos.
    const isAndroid = /Android/i.test(navigator.userAgent)

    if (!isAndroid) {
      const file = new File([blob], this.filenameValue, {
        type: blob.type || "image/jpeg"
      })

      if (navigator.canShare && navigator.canShare({ files: [file] })) {
        try {
          await navigator.share({ files: [file] })
          return
        } catch (err) {
          if (err.name === "AbortError") return
          // Activation expired during the fetch — the blob is cached now, so a
          // second tap opens the sheet instantly. Don't fall through to the
          // anchor download, which is a silent no-op in iOS standalone mode.
          if (err.name === "NotAllowedError") {
            alert("Tap “Save photo” once more to open the share sheet.")
            return
          }
          console.warn("photo-save: share failed, falling back", err)
        }
      }
    }

    this._downloadFallback(blob)
  }

  _downloadFallback(blob) {
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = this.filenameValue
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    setTimeout(() => URL.revokeObjectURL(url), 100)
  }
}
