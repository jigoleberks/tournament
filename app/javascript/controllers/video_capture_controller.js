import { Controller } from "@hotwired/stimulus"
import { MAX_VIDEO_BYTES } from "offline/limits"

export default class extends Controller {
  static targets = ["preview", "video", "recordButton", "stopButton", "failedButton"]

  async start() {
    // Double-tap guard. It must cover the getUserMedia await too: on first use
    // iOS holds that await open for seconds behind the permission prompt, and
    // a second tap in the window would orphan the first stream's tracks
    // (camera light pinned on; iOS's single-capture-session rule can wedge the
    // camera until the tab dies) and cross-wire this.chunks.
    if (this.acquiring) return
    if (this.recorder && this.recorder.state !== "inactive") return
    this.acquiring = true
    this.stopStream()
    // A getUserMedia rejection (permission denied, no camera) must route
    // through markFailed like every other failure — an uncaught throw here
    // wedges the video UI and the catch form never hears the failed event.
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "environment",
          width: { ideal: 1920 },
          height: { ideal: 1080 }
        },
        audio: true
      })
      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()
    } catch (_) {
      this.markFailed()
      return
    } finally {
      this.acquiring = false
    }
    this.chunks = []
    // iOS Safari only supports video/mp4 for MediaRecorder; Chrome/Firefox prefer webm.
    // Hardcoding webm previously made every iPhone hit NotSupportedError on construct.
    // A browser missing MediaRecorder entirely must fail gracefully, not throw a
    // ReferenceError that skips the failed-event the catch form listens for.
    if (typeof MediaRecorder === "undefined" || !MediaRecorder.isTypeSupported) {
      this.markFailed()
      return
    }
    const candidates = ["video/mp4;codecs=h264,aac", "video/mp4", "video/webm;codecs=vp9", "video/webm"]
    const mimeType = candidates.find((t) => MediaRecorder.isTypeSupported(t))
    if (!mimeType) {
      this.markFailed()
      return
    }
    this.recorder = new MediaRecorder(this.stream, { mimeType })
    this.recorder.ondataavailable = (e) => { if (e.data.size) this.chunks.push(e.data) }
    // iOS kills the capture session on a phone call, screen lock, app switch,
    // or when the native photo sheet opens (one capture session at a time).
    // The recorder either errors or its tracks end — both must finalize into a
    // visible state instead of wedging the UI in "recording".
    this.recorder.onerror = () => {
      this.markFailed("Recording was interrupted — record again, or mark video failed.")
    }
    this.stream.getTracks().forEach((t) => {
      // track.stop() (our own teardown) does NOT fire "ended" — only external
      // interruption does, so this can't race stopStream().
      t.addEventListener("ended", () => {
        if (this.recorder && this.recorder.state === "recording") this.stop()
      })
    })
    this.recorder.onstop = () => {
      const blob = new Blob(this.chunks, { type: mimeType })
      // Zero bytes means the recording died (interruption, instant stop).
      // Treating it as captured used to submit the catch with no video at all
      // — flagged video_missing in review while the angler believed they
      // recorded it.
      if (blob.size === 0) {
        this.markFailed("Recording failed — nothing was captured. Record again, or mark video failed.")
        return
      }
      // Oversized videos would be silently dropped at drain time; fail loudly
      // while the angler can still re-record.
      if (blob.size > MAX_VIDEO_BYTES) {
        this.markFailed("That video is too large to upload — record a shorter one, or mark video failed.")
        return
      }
      this.blob = blob
      if (this.previewUrl) URL.revokeObjectURL(this.previewUrl)
      this.previewUrl = URL.createObjectURL(this.blob)
      this.previewTarget.src = this.previewUrl
      this.previewTarget.dataset.captured = "true"
      this.setRecordingUi(false)
      this.dispatch("captured", { detail: { blob: this.blob } })
      this.stopStream()
    }
    this.recorder.start()
    this.setRecordingUi(true)
  }

  stop() {
    if (this.recorder && this.recorder.state !== "inactive") this.recorder.stop()
  }

  markFailed(reason) {
    this.blob = null
    this.previewTarget.dataset.captured = "failed"
    this.setRecordingUi(false)
    this.dispatch("failed", { detail: { reason } })
    this.stopStream()
  }

  setRecordingUi(recording) {
    if (this.hasRecordButtonTarget) {
      this.recordButtonTarget.disabled = recording
      this.recordButtonTarget.textContent = recording ? "● Recording…" : "Start recording"
    }
    if (this.hasStopButtonTarget) this.stopButtonTarget.disabled = !recording
  }

  stopStream() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop())
      this.stream = null
    }
  }

  disconnect() {
    this.stop()
    this.stopStream()
    if (this.previewUrl) {
      URL.revokeObjectURL(this.previewUrl)
      this.previewUrl = null
    }
  }
}
