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
    await this._restoreDesiredZoom()
    this._updateZoomButtons()
    if (this._cameraDebugEnabled()) await this._renderCameraDebug()
  }

  // Temporary diagnostic: visit /catches/new?camdebug=1 to see what
  // getUserMedia + enumerateDevices report on this device. Used to tune the
  // capability probe against real hardware. Safe to leave in normal use — the
  // overlay only renders when the query param is present.
  _cameraDebugEnabled() {
    try { return new URLSearchParams(location.search).get("camdebug") === "1" }
    catch (_) { return false }
  }

  async _renderCameraDebug() {
    const track = this.stream?.getVideoTracks?.()?.[0]
    const caps = track && typeof track.getCapabilities === "function" ? track.getCapabilities() : null
    const settings = track && typeof track.getSettings === "function" ? track.getSettings() : null
    let devices = []
    try { devices = await navigator.mediaDevices.enumerateDevices() } catch (_) {}
    const videoInputs = devices.filter((d) => d.kind === "videoinput").map((d) => ({
      label:    d.label || "(empty)",
      deviceId: d.deviceId ? d.deviceId.slice(0, 12) + "…" : "(empty)",
      groupId:  d.groupId  ? d.groupId.slice(0, 12)  + "…" : "(empty)"
    }))

    const info = {
      userAgent:         navigator.userAgent,
      standaloneDisplay: matchMedia("(display-mode: standalone)").matches,
      probeResult: {
        zoomMethod:     this.zoomMethod,
        deviceIdByZoom: this.deviceIdByZoom
      },
      trackSettings:     settings,
      trackCapabilities: caps,
      videoInputs
    }
    const json = JSON.stringify(info, null, 2)

    let el = document.getElementById("camdebug-output")
    if (!el) {
      // Floating chip in the top-left, expands to a full overlay on tap.
      // Default-collapsed so it doesn't cover the zoom toggle at the bottom.
      el = document.createElement("div")
      el.id = "camdebug-output"
      el.style.cssText = "position:fixed;top:8px;left:8px;z-index:9999;background:rgba(0,0,0,0.85);color:#0f0;font:11px/1.3 monospace;border:1px solid #0f0;border-radius:6px;max-width:calc(100vw - 16px)"

      const header = document.createElement("div")
      header.id = "camdebug-header"
      header.style.cssText = "padding:6px 10px;cursor:pointer;user-select:none;white-space:nowrap"
      header.textContent = "▶ camdebug"
      el.appendChild(header)

      const body = document.createElement("div")
      body.id = "camdebug-body"
      body.style.cssText = "display:none;padding:0 10px 10px 10px;max-height:60vh;overflow:auto;word-break:break-all"

      const copyBtn = document.createElement("button")
      copyBtn.type = "button"
      copyBtn.textContent = "Copy JSON"
      copyBtn.style.cssText = "background:#222;color:#fff;border:1px solid #444;padding:4px 8px;font:12px sans-serif;border-radius:4px;cursor:pointer;margin-bottom:6px"
      copyBtn.addEventListener("click", async (event) => {
        event.stopPropagation()
        try {
          await navigator.clipboard.writeText(el.dataset.json || "")
          copyBtn.textContent = "Copied!"
          setTimeout(() => { copyBtn.textContent = "Copy JSON" }, 1500)
        } catch (_) {
          copyBtn.textContent = "Copy failed"
        }
      })
      body.appendChild(copyBtn)

      const pre = document.createElement("pre")
      pre.id = "camdebug-pre"
      pre.style.cssText = "margin:0;font:inherit;color:inherit;white-space:pre-wrap;word-break:break-all"
      body.appendChild(pre)
      el.appendChild(body)

      header.addEventListener("click", () => {
        const expanded = body.style.display !== "none"
        body.style.display = expanded ? "none" : "block"
        header.textContent = expanded ? "▶ camdebug" : "▼ camdebug (tap to collapse)"
      })

      document.body.appendChild(el)
    }
    el.dataset.json = json
    document.getElementById("camdebug-pre").textContent = json
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

      if (mainLens && wideLens && mainLens.deviceId !== wideLens.deviceId) {
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

  retake() {
    this.previewTarget.removeAttribute("src")
    this.previewTarget.dataset.captured = "false"
    this.input = null
    // Re-seed desiredZoom so the next start() re-applies the saved level on
    // the fresh track (otherwise retake silently drops back to the default lens).
    this.desiredZoom = this.zoom
    this.start()
  }

  setZoomHalf() { this._setZoom(0.5) }
  setZoomOne()  { this._setZoom(1) }

  async _setZoom(value) {
    if (this.zoom === value) return
    if (!this.zoomMethod) return
    this.zoom = value
    try { localStorage.setItem("catchCameraZoom", String(value)) } catch (_) {}
    this._updateZoomButtons()
    await this._applyZoom(value)
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
      this.stop()
      try {
        await this.start({ deviceIdHint })
      } catch (err) {
        console.warn("Lens switch failed:", err)
        this._setState("idle")
      }
    }
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
