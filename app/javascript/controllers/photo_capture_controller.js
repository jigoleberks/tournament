import { Controller } from "@hotwired/stimulus"

// Extract the first numeric run from a camera label so we can pair the
// lowest-indexed back camera (the main lens) with the highest-indexed back
// camera (typically the ultra-wide on Samsung Android). Labels without a
// number sort last but stably. Examples:
//   "camera 0, facing back"  -> 0
//   "Facing back:2"          -> 2
//   "Back Ultra Wide Camera" -> 9999  (no digit; sorts last)
const extractCamIndex = (label) => {
  const m = label && label.match(/(\d+)/)
  return m ? parseInt(m[1], 10) : 9999
}

// State: "idle" (no camera, no capture), "streaming" (camera open),
// "captured" (photo taken, camera stopped, preview shown).
export default class extends Controller {
  static targets = [
    "preview", "video", "openButton", "captureButton", "retakeButton",
    "fullscreenButton", "fullscreenContainer", "fullscreenSlot", "inlineSlot",
    "frameGuide", "zoomToggle", "zoomHalfButton", "zoomOneButton"
  ]

  async connect() {
    this._setState("idle")
    this.zoom = 1
    this.zoomMethod = null
    this.deviceIdByZoom = null
    this.desiredZoom = this._readStoredZoom()
    try {
      await this.start()
    } catch (err) {
      // Permission denied, no camera, or insecure context — fall back to the
      // Open camera button so the user can retry with an explicit gesture.
      console.warn("Camera auto-start failed:", err)
    }
  }

  _readStoredZoom() {
    let stored
    try { stored = localStorage.getItem("catchCameraZoom") } catch (_) { return null }
    if (stored === "0.5") return 0.5
    if (stored === "1")   return 1
    return null
  }

  async start({ deviceIdHint } = {}) {
    const videoConstraints = deviceIdHint
      ? { deviceId: { exact: deviceIdHint }, width: { ideal: 4032 }, height: { ideal: 3024 } }
      : { facingMode: "environment", width: { ideal: 4032 }, height: { ideal: 3024 } }

    this.stream = await navigator.mediaDevices.getUserMedia({
      video: videoConstraints,
      audio: false
    })
    this.videoTarget.srcObject = this.stream
    await this.videoTarget.play()
    this._setState("streaming")
    await this._probeZoom()
    this._syncZoomFromStream()
    await this._restoreDesiredZoom()
    this._updateZoomButtons()
  }

  // After every fresh stream, snap this.zoom to whichever known lens the OS
  // actually opened. Without this, retake() reuses the prior this.zoom even
  // though getUserMedia({ facingMode: "environment" }) typically lands on the
  // main lens — leaving the 0.5x button highlighted, but a no-op (because
  // _setZoom short-circuits on this.zoom === value).
  _syncZoomFromStream() {
    if (this.zoomMethod !== "device" || !this.deviceIdByZoom) return
    const track = this.stream?.getVideoTracks?.()?.[0]
    const currentDeviceId = track?.getSettings?.()?.deviceId
    if (!currentDeviceId) return
    if (currentDeviceId === this.deviceIdByZoom["0.5"]) this.zoom = 0.5
    else if (currentDeviceId === this.deviceIdByZoom["1"]) this.zoom = 1
  }

  // After the probe runs on a fresh stream, push the user's last choice
  // (read from localStorage in connect) into the camera if it's reachable.
  // The probe may have already set this.zoom based on which lens the OS
  // gave us, so we only re-apply when the saved choice differs.
  // If the saved value can't be reached on the current device, fall back
  // to 1x silently and overwrite storage so we don't keep retrying.
  async _restoreDesiredZoom() {
    const want = this.desiredZoom
    this.desiredZoom = null   // only restore once per controller lifetime
    if (want == null) return  // no stored preference — accept the OS default
    if (want === this.zoom) return   // already on the right lens

    if (!this.zoomMethod) {
      this.zoom = 1
      try { localStorage.setItem("catchCameraZoom", "1") } catch (_) {}
      return
    }
    if (this.zoomMethod === "device" && !this.deviceIdByZoom?.[String(want)]) {
      this.zoom = 1
      try { localStorage.setItem("catchCameraZoom", "1") } catch (_) {}
      return
    }

    this.zoom = want
    await this._applyZoom(want)
  }

  // Determines how this device can reach 0.5x, if at all. Sets:
  //   this.zoomMethod = "constraint" | "device" | null
  //   this.deviceIdByZoom = { "1": deviceId, "0.5": deviceId }  (device mode only)
  //
  // Sticky: once a non-null zoomMethod is set, later probes do not downgrade
  // or overwrite it. This matters when device-switch mode lands on a single
  // lens whose track happens to report a zoom range — that range covers only
  // digital zoom on that lens, not the ultra-wide we already wired up.
  async _probeZoom() {
    if (this.zoomMethod) return

    const track = this.stream?.getVideoTracks()?.[0]
    if (!track) return

    let devices = []
    try { devices = await navigator.mediaDevices.enumerateDevices() } catch (_) {}
    const videoInputs = devices.filter((d) => d.kind === "videoinput")

    // Identify back-facing cameras by label substring. Labels are populated
    // after getUserMedia permission is granted. We deliberately do NOT fall
    // back to all videoinputs when no labels match — that's how the earlier
    // probe false-matched single PC webcams whose names happened to contain
    // "wide" or "ultra".
    const backCams = videoInputs.filter((d) => /\bback\b|\brear\b/i.test(d.label))

    // Primary path: 2+ back cameras = the phone exposes main + ultra-wide
    // (and possibly telephoto) as separate videoinputs. Pick the pair that
    // drives the 1x / 0.5x toggle.
    if (backCams.length >= 2) {
      // Prefer an explicit "Ultra Wide" label (iOS Safari pattern). Failing
      // that, fall back to the numeric-index convention used by Samsung's
      // Android labels: "camera 0, facing back" / "Facing back:0" — lowest
      // index is the main lens, highest is the ultra-wide.
      const explicitWide = backCams.find((d) => /ultra.{0,3}wide/i.test(d.label))
      let mainLens, wideLens
      if (explicitWide) {
        wideLens = explicitWide
        mainLens = backCams.find((d) =>
          d.deviceId !== wideLens.deviceId &&
          !/ultra.{0,3}wide|telephoto|\btele\b/i.test(d.label)
        ) || backCams.find((d) => d.deviceId !== wideLens.deviceId)
      } else {
        const sorted = [...backCams].sort((a, b) => extractCamIndex(a.label) - extractCamIndex(b.label))
        mainLens = sorted[0]
        wideLens = sorted[sorted.length - 1]
      }

      if (mainLens && wideLens && mainLens.deviceId !== wideLens.deviceId &&
          !this._isWideLensBlocked(wideLens.deviceId)) {
        this.zoomMethod = "device"
        this.deviceIdByZoom = { "1": mainLens.deviceId, "0.5": wideLens.deviceId }
        // If the OS defaulted the stream to the wide lens (Samsung's S20
        // Ultra does this on a facingMode: environment request), reflect
        // that in this.zoom so the toggle highlights the right button and
        // the restore logic doesn't think a redundant switch is needed.
        const currentDeviceId = track.getSettings?.().deviceId
        if (currentDeviceId === wideLens.deviceId) this.zoom = 0.5
        return
      }
    }

    // Fallback: a single back camera whose zoom range itself crosses below
    // 1x. Rare in practice — Samsung's caps.zoom is {min:1, max:8}, digital
    // zoom only on the active lens. Kept for any device where the constraint
    // path is genuinely the way to reach the ultra-wide.
    const caps = typeof track.getCapabilities === "function" ? track.getCapabilities() : {}
    if (caps.zoom && caps.zoom.min <= 0.5 && caps.zoom.max >= 1) {
      this.zoomMethod = "constraint"
    }
  }

  // Shows/hides the toggle wrapper based on whether a zoomMethod was found,
  // and styles the buttons so the active level is white-on-dark.
  _updateZoomButtons() {
    if (!this.hasZoomToggleTarget) return

    const visible = this.zoomMethod !== null && this.state === "streaming"
    this.zoomToggleTarget.classList.toggle("hidden", !visible)

    if (!visible) return
    if (!this.hasZoomHalfButtonTarget || !this.hasZoomOneButtonTarget) return

    const setActive = (btn, active) => {
      btn.classList.toggle("bg-white",          active)
      btn.classList.toggle("text-slate-900",    active)
      btn.classList.toggle("text-white",        !active)
    }
    setActive(this.zoomHalfButtonTarget, this.zoom === 0.5)
    setActive(this.zoomOneButtonTarget,  this.zoom === 1)
  }

  capture() {
    const v = this.videoTarget
    const canvas = document.createElement("canvas")
    canvas.width = v.videoWidth
    canvas.height = v.videoHeight
    canvas.getContext("2d").drawImage(v, 0, 0)
    canvas.toBlob((blob) => {
      this.previewTarget.src = URL.createObjectURL(blob)
      this.previewTarget.dataset.captured = "true"
      this.input = blob
      this.dispatch("captured", { detail: { blob } })
      if (this._isFullscreen()) this._collapseFullscreen()
      this.stop()
      this._setState("captured")
    }, "image/jpeg", 0.9)
  }

  async retake() {
    this.previewTarget.removeAttribute("src")
    this.previewTarget.dataset.captured = "false"
    this.input = null
    // Re-seed desiredZoom so the next start() re-applies the saved level on
    // the fresh track (otherwise retake silently drops back to the default lens).
    this.desiredZoom = this.zoom
    try {
      await this.start()
    } catch (err) {
      console.warn("Camera restart after retake failed:", err)
      this._setState("idle")
    }
  }

  setZoomHalf() { this._setZoom(0.5) }
  setZoomOne()  { this._setZoom(1) }

  async _setZoom(value) {
    if (this.zoom === value) return
    if (!this.zoomMethod) return
    // Serialize zoom changes. Rapid 0.5x↔1x taps used to interleave two
    // stop()/start() pairs, leaving this.stream pointing at the losing track
    // while the visible video was the winner's. Worse, the losing start()'s
    // _waitForFirstFrame would time out (its stream was killed by the second
    // tap's stop()) and the catch path would permanently blocklist the wide
    // deviceId — turning a transient race into permanent loss of 0.5x.
    if (this._zoomBusy) return
    this._zoomBusy = true
    try {
      this.zoom = value
      try { localStorage.setItem("catchCameraZoom", String(value)) } catch (_) {}
      this._updateZoomButtons()
      await this._applyZoom(value)
    } finally {
      this._zoomBusy = false
    }
  }

  async _applyZoom(value) {
    if (this.zoomMethod === "constraint") {
      const track = this.stream?.getVideoTracks()?.[0]
      if (!track) return
      try {
        await track.applyConstraints({ advanced: [{ zoom: value }] })
      } catch (err) {
        console.warn("Zoom constraint rejected:", err)
      }
      return
    }

    if (this.zoomMethod === "device") {
      const deviceIdHint = this.deviceIdByZoom?.[String(value)]
      if (!deviceIdHint) return
      const wideId = this.deviceIdByZoom["0.5"]
      this.stop()
      try {
        await this.start({ deviceIdHint })
        await this._waitForFirstFrame()
      } catch (err) {
        console.warn("Lens switch failed:", err)
        // The requested lens opened (or didn't) but produces no usable
        // video on this device. On the S25 Ultra this happens with the
        // ultra-wide deviceId — enumerateDevices exposes it but the
        // stream comes up blank. Blocklist the wide lens deviceId so we
        // don't show the toggle on this device again, reset to the main
        // lens, and bring the camera back to life.
        if (wideId) this._blockWideLens(wideId)
        this.zoomMethod = null
        this.deviceIdByZoom = null
        this.zoom = 1
        try { localStorage.setItem("catchCameraZoom", "1") } catch (_) {}
        this.stop()
        try {
          await this.start()
        } catch (_) {
          this._setState("idle")
        }
        this._updateZoomButtons()
      }
    }
  }

  // Wait until the active stream has produced at least one frame, or fail
  // fast (within 800 ms) if it never will. Used after a deviceId-pinned
  // start() to detect lenses that enumerate but don't actually deliver
  // video (the S25 Ultra's "Facing back:2" via Firefox Android behaves
  // this way). Resolves immediately if frames are already visible or the
  // track reports usable dimensions; otherwise waits for the first
  // loadeddata event with a timeout.
  async _waitForFirstFrame(timeoutMs = 800) {
    const v = this.videoTarget
    if (v.videoWidth > 0 && v.videoHeight > 0) return

    const track = this.stream?.getVideoTracks?.()?.[0]
    if (!track || track.readyState !== "live") throw new Error("No live video track")
    const settings = track.getSettings?.()
    if (settings && settings.width > 0 && settings.height > 0) return

    await new Promise((resolve, reject) => {
      const onLoad = () => { cleanup(); resolve() }
      const timer = setTimeout(() => { cleanup(); reject(new Error("Video frame timeout")) }, timeoutMs)
      const cleanup = () => {
        v.removeEventListener("loadeddata", onLoad)
        clearTimeout(timer)
      }
      v.addEventListener("loadeddata", onLoad, { once: true })
    })
  }

  _isWideLensBlocked(deviceId) {
    try {
      const raw = localStorage.getItem("catchCameraBlockedWideLens")
      if (!raw) return false
      const blocked = JSON.parse(raw)
      return Array.isArray(blocked) && blocked.includes(deviceId)
    } catch (_) { return false }
  }

  _blockWideLens(deviceId) {
    try {
      const raw = localStorage.getItem("catchCameraBlockedWideLens")
      const blocked = raw ? JSON.parse(raw) : []
      if (Array.isArray(blocked) && !blocked.includes(deviceId)) {
        blocked.push(deviceId)
        localStorage.setItem("catchCameraBlockedWideLens", JSON.stringify(blocked))
      }
    } catch (_) {}
  }

  enterFullscreen() {
    if (!this.stream || !this.hasFullscreenContainerTarget) return
    this.fullscreenSlotTarget.appendChild(this.videoTarget)
    if (this.hasFrameGuideTarget) this.fullscreenSlotTarget.appendChild(this.frameGuideTarget)
    if (this.hasZoomToggleTarget) this.fullscreenSlotTarget.appendChild(this.zoomToggleTarget)
    this.videoTarget.classList.remove("aspect-[3/4]", "rounded-lg")
    this.videoTarget.classList.add("w-full", "h-full")
    this.fullscreenContainerTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  exitFullscreen() {
    this._collapseFullscreen()
  }

  stop() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
  }

  disconnect() {
    if (this._isFullscreen()) this._collapseFullscreen()
    this.stop()
  }

  get blob() { return this.input }

  _setState(state) {
    this.state = state
    this._toggle(this.openButtonTarget,       state === "idle")
    this._toggle(this.videoTarget,            state === "streaming")
    this._toggle(this.captureButtonTarget,    state === "streaming")
    this._toggle(this.fullscreenButtonTarget, state === "streaming")
    if (this.hasFrameGuideTarget) this._toggle(this.frameGuideTarget, state === "streaming")
    this._toggle(this.previewTarget,          state === "captured")
    this._toggle(this.retakeButtonTarget,     state === "captured")
    this._updateZoomButtons()
  }

  _toggle(el, visible) {
    if (!el) return
    el.classList.toggle("hidden", !visible)
  }

  _isFullscreen() {
    return this.hasFullscreenContainerTarget &&
           !this.fullscreenContainerTarget.classList.contains("hidden")
  }

  _collapseFullscreen() {
    if (!this.hasFullscreenContainerTarget) return
    this.inlineSlotTarget.appendChild(this.videoTarget)
    if (this.hasFrameGuideTarget) this.inlineSlotTarget.appendChild(this.frameGuideTarget)
    if (this.hasZoomToggleTarget) this.inlineSlotTarget.appendChild(this.zoomToggleTarget)
    this.videoTarget.classList.remove("w-full", "h-full")
    this.videoTarget.classList.add("aspect-[3/4]", "rounded-lg")
    this.fullscreenContainerTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }
}
