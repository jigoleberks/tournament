import { Controller } from "@hotwired/stimulus"

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
    try { stored = localStorage.getItem("catchCameraZoom") } catch (_) { return 1 }
    if (stored === "0.5") return 0.5
    return 1
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
      el = document.createElement("div")
      el.id = "camdebug-output"
      el.style.cssText = "position:fixed;bottom:0;left:0;right:0;background:rgba(0,0,0,0.92);color:#0f0;padding:8px;font:11px/1.3 monospace;max-height:60vh;overflow:auto;z-index:9999;white-space:pre-wrap;word-break:break-all"

      const copyBtn = document.createElement("button")
      copyBtn.type = "button"
      copyBtn.textContent = "Copy JSON"
      copyBtn.style.cssText = "position:sticky;top:0;float:right;background:#222;color:#fff;border:1px solid #444;padding:4px 8px;font:12px sans-serif;border-radius:4px;cursor:pointer"
      copyBtn.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(el.dataset.json || "")
          copyBtn.textContent = "Copied!"
          setTimeout(() => { copyBtn.textContent = "Copy JSON" }, 1500)
        } catch (_) {
          copyBtn.textContent = "Copy failed"
        }
      })
      el.appendChild(copyBtn)

      const pre = document.createElement("pre")
      pre.id = "camdebug-pre"
      pre.style.cssText = "margin:0;padding-top:4px;font:inherit;color:inherit;white-space:pre-wrap;word-break:break-all"
      el.appendChild(pre)
      document.body.appendChild(el)
    }
    el.dataset.json = json
    document.getElementById("camdebug-pre").textContent = json
  }

  // After the probe runs on a fresh stream, push the user's last choice
  // (read from localStorage in connect) into the camera if it's reachable.
  // If 0.5x was saved but the current device can't deliver it, fall back to
  // 1x silently and overwrite storage so we don't keep retrying.
  async _restoreDesiredZoom() {
    const want = this.desiredZoom
    if (want == null) return
    this.desiredZoom = null   // only restore once per controller lifetime

    if (want === 1) { this.zoom = 1; return }   // 1x is the default — nothing to do

    // want === 0.5
    if (!this.zoomMethod) {
      this.zoom = 1
      try { localStorage.setItem("catchCameraZoom", "1") } catch (_) {}
      return
    }
    if (this.zoomMethod === "device" && !this.deviceIdByZoom?.["0.5"]) {
      this.zoom = 1
      try { localStorage.setItem("catchCameraZoom", "1") } catch (_) {}
      return
    }

    this.zoom = 0.5
    await this._applyZoom(0.5)
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

    // Path 1: W3C zoom constraint (Android Chrome + modern phones).
    const caps = typeof track.getCapabilities === "function" ? track.getCapabilities() : {}
    if (caps.zoom && caps.zoom.min <= 0.5 && caps.zoom.max >= 1) {
      this.zoomMethod = "constraint"
      return
    }

    // Path 2: enumerateDevices() ultra-wide lookup (iOS Safari).
    let devices
    try { devices = await navigator.mediaDevices.enumerateDevices() } catch (_) { return }

    const videoInputs = devices.filter((d) => d.kind === "videoinput")
    let backCams = videoInputs.filter((d) => /back|rear|environment/i.test(d.label))
    if (backCams.length === 0) backCams = videoInputs   // labels empty — try them all

    const ultraWide = backCams.find((d) => /ultra|wide|0\.5|0\.7/i.test(d.label))
    if (!ultraWide) return

    // The 1x lens is the first back camera that does NOT look like an ultra-wide
    // or telephoto. If nothing clears that filter, fall back to whichever lens
    // the current stream is using.
    const oneX = backCams.find((d) =>
      d.deviceId !== ultraWide.deviceId &&
      !/ultra|wide|tele|0\.5|0\.7|2x|3x|5x/i.test(d.label)
    ) || backCams.find((d) => d.deviceId === (track.getSettings && track.getSettings().deviceId))

    if (!oneX) return

    this.zoomMethod = "device"
    this.deviceIdByZoom = { "1": oneX.deviceId, "0.5": ultraWide.deviceId }
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
