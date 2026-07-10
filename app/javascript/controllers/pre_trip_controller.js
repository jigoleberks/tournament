import { Controller } from "@hotwired/stimulus"

// Status levels. The glyph is retained alongside the color so the page still
// reads for colorblind users, and so the existing "…" assertions keep working.
const LEVELS = {
  ok:      { glyph: "✓", color: "text-emerald-400" },
  warn:    { glyph: "⚠", color: "text-amber-300" },
  fail:    { glyph: "✗", color: "text-red-400" },
  info:    { glyph: "ℹ", color: "text-blue-300" },
  pending: { glyph: "…", color: "text-slate-400" },
}

const COLOR_CLASSES = Object.values(LEVELS).map((l) => l.color)

// Angler-facing guidance for every non-passing check, keyed check → cause.
// Wording is iOS-first: roughly 70% of the club is on iPhone. Each string names
// the cause and the remedy, because a troubleshooting page that only names the
// cause has done half the job.
const HINTS = {
  tournaments: {
    none: "You can still log catches — they'll go to your catch history, but won't score until a tournament is running.",
  },
  camera: {
    blocked: "Camera access is blocked. Open your browser's settings for this site, set Camera to Allow, then Re-test.",
    missing: "This device has no rear camera. Log catches from a phone.",
    busy: "Another app is using the camera. Close it, then Re-test.",
    unknown: "The camera didn't respond. Close and reopen the app, then Re-test.",
  },
  microphone: {
    blocked: "Microphone access is blocked. Open your browser's settings for this site, set Microphone to Allow, then Re-test.",
    missing: "This device has no microphone. Photo catches still work — only video catches need one.",
    busy: "Another app is using the microphone. Close it, then Re-test.",
    unknown: "The microphone didn't respond. Close and reopen the app, then Re-test.",
  },
  gps: {
    unsupported: "This browser can't provide location. Use Safari on iPhone, or Chrome on Android.",
    blocked: "Location is blocked for this site. Allow location in your browser's site settings, then Re-test.",
    unavailable: "Your phone can't get a fix. Turn Location Services off and back on in system settings, step outside away from buildings, then Re-test.",
    timeout: "No fix within 8 seconds. Turn Location Services off and back on, wait a few seconds outdoors, then Re-test.",
    low: "Accuracy is poor, so a catch here may be flagged for judge review. Turn on Precise Location for this app and move into the open, then Re-test.",
    poor: "Too imprecise to place a catch. Turn Location Services off and back on, enable Precise Location, then Re-test.",
  },
  clock: {
    noFix: "Couldn't check your clock without a GPS fix. Fix GPS above, then Re-test.",
    skewed: "Catches logged with a skewed clock get flagged for judge review. Turn on automatic date & time in system settings (iPhone: Settings → General → Date & Time), then Re-test.",
  },
  notifications: {
    unsupported: "This browser can't show notifications. On iPhone, add this app to your Home Screen first (Share → Add to Home Screen), then enable notifications. On Android use Chrome.",
    blocked: "Notifications are blocked, so you won't get alerts when you take the lead or get bumped from a slot. Allow them in your browser's site settings, then Re-test.",
    notEnabled: "Tap Enable in the Notifications box on the home screen.",
  },
  network: {
    offline: "Catches you log are saved on your phone and upload on their own when signal returns.",
  },
  version: {
    stale: "Tap 'Update app (clear cache)' below to get the newest version. Pending catches are kept.",
    unreachable: "You're offline, or the server is down. Nothing to do if the rest of this page is green.",
  },
}

// getUserMedia rejects with a DOMException whose .name is stable across
// browsers. Its .message is not, and is too long for a phone-width row.
const MEDIA_CAUSES = {
  NotAllowedError: "blocked",
  SecurityError: "blocked",
  NotFoundError: "missing",
  OverconstrainedError: "missing",
  NotReadableError: "busy",
  AbortError: "busy",
}

const MEDIA_STATUS = {
  blocked: () => "blocked",
  missing: (device) => `no ${device} found`,
  busy: (device) => `${device} busy`,
  unknown: () => "unavailable",
}

// PositionError codes. 1 = PERMISSION_DENIED, 2 = POSITION_UNAVAILABLE,
// 3 = TIMEOUT. The three want different remedies: unblock, cycle Location
// Services, wait outdoors.
const GPS_ERRORS = {
  1: { cause: "blocked", status: "blocked" },
  2: { cause: "unavailable", status: "no fix" },
  3: { cause: "timeout", status: "no fix (timeout)" },
}

export default class extends Controller {
  static targets = ["session", "tournaments", "camera", "microphone", "gps", "clock", "notifications", "network", "version", "troubleshootStatus"]
  static values = { activeTournaments: Number }

  // The diagnostic-check rows that _reset() blanks to "…" before a run.
  // Excludes troubleshootStatus, which is the Update-app button's own status
  // line, not a check — sweeping it would stamp a stray "…" there every run.
  static CHECK_TARGETS = ["session", "tournaments", "camera", "microphone", "gps", "clock", "notifications", "network", "version"]

  connect() { this.runAll() }

  async runAll() {
    // Each run gets a generation. A GPS fix can take 8s, so a second Re-test can
    // start while the first is still awaiting; without this, the older run's
    // callbacks resolve last and overwrite the newer run's rows with stale results.
    const gen = this._gen = (this._gen ?? 0) + 1
    this._reset(gen)
    this.set(gen, "session", "ok", "")
    if (this.activeTournamentsValue > 0) {
      this.set(gen, "tournaments", "ok", "")
    } else {
      // info, not warn: no tournament is the normal state on most days, and a
      // warning color on a healthy phone teaches people to ignore warning colors.
      this.set(gen, "tournaments", "info", "no active tournaments today", HINTS.tournaments.none)
    }
    await this.checkCamera(gen)
    await this.checkMicrophone(gen)
    await this.checkGps(gen)
    await this.checkNotifications(gen)
    this.checkNetwork(gen)
    await this.checkVersion(gen)
  }

  checkNetwork(gen) {
    if (navigator.onLine) {
      this.set(gen, "network", "ok", `(${navigator.connection?.effectiveType ?? "online"})`)
    } else {
      this.set(gen, "network", "info", "offline (sync deferred)", HINTS.network.offline)
    }
  }

  // Compares the build the phone is running (data-app-build, baked into the page
  // it loaded) against the live server build fetched from /api/version. The
  // endpoint lives under /api/ so the service worker passes it straight to the
  // network (never cached), so a re-test discovers a deploy that landed after
  // the phone last loaded — even while it's still showing the pre-deploy page.
  // A mismatch means "Update app" below will pull the newer build.
  async checkVersion(gen) {
    const loaded = document.documentElement.dataset.appBuild || ""
    const short = (v) => v.slice(0, 7) || "unknown"

    let server
    try {
      const res = await fetch("/api/version", { headers: { Accept: "application/json" }, cache: "no-store" })
      if (res.ok) server = (await res.json()).build
    } catch (e) {
      // Offline or unreachable: fall through to the can't-check state below.
    }

    if (!server) {
      this.set(gen, "version", "info", `${short(loaded)} (couldn't reach server)`, HINTS.version.unreachable)
    } else if (server === loaded) {
      this.set(gen, "version", "ok", short(loaded))
    } else {
      this.set(gen, "version", "warn", `update available — you: ${short(loaded)} · server: ${short(server)}`, HINTS.version.stale)
    }
  }

  _reset(gen) {
    for (const name of this.constructor.CHECK_TARGETS) {
      this.set(gen, name, "pending", "")
    }
  }

  // level picks the glyph and the color and nothing else; text carries no glyph.
  // An empty hint hides the row's hint paragraph, so a clean run shows no gaps
  // and a Re-test can't leave a stale hint under a now-passing check.
  // gen is the run this write belongs to; if a newer run has since started, the
  // write is dropped so the older run's late callbacks can't clobber it.
  set(gen, name, level, text, hint = "") {
    if (gen !== this._gen) return
    const { glyph, color } = LEVELS[level]
    const el = this[`${name}Target`]
    el.textContent = text ? `${glyph} ${text}` : glyph
    el.classList.remove(...COLOR_CLASSES)
    el.classList.add(color)
    this._hint(name, hint)
  }

  // The hint paragraph is found through the row's existing data-check anchor
  // rather than nine more Stimulus targets.
  _hint(name, text) {
    const el = this.element.querySelector(`[data-check="${name}"] [data-pre-trip-hint]`)
    if (!el) return
    el.textContent = text
    el.classList.toggle("hidden", !text)
  }

  async checkCamera(gen) {
    await this._checkMedia(gen, "camera", { video: { facingMode: "environment" } })
  }

  async checkMicrophone(gen) {
    await this._checkMedia(gen, "microphone", { audio: true })
  }

  // OverconstrainedError maps to "missing" because the only constraint we ask
  // for is facingMode: "environment" — a device that can't satisfy it has no
  // rear camera, which is exactly what the "missing" hint tells the angler.
  async _checkMedia(gen, name, constraints) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia(constraints)
      stream.getTracks().forEach((t) => t.stop())
      this.set(gen, name, "ok", "")
    } catch (e) {
      const cause = MEDIA_CAUSES[e.name] ?? "unknown"
      this.set(gen, name, "fail", MEDIA_STATUS[cause](name), HINTS[name][cause])
    }
  }

  checkGps(gen) {
    return new Promise((resolve) => {
      if (!navigator.geolocation) { this._gpsFailed(gen, "unsupported", "not supported"); return resolve() }
      const safetyTimeout = setTimeout(() => {
        // Some browsers never fire success or error at all; treat that as a timeout.
        this._gpsFailed(gen, "timeout", "no fix (timeout)")
        resolve()
      }, 10000)
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          clearTimeout(safetyTimeout)
          const acc = pos.coords.accuracy
          if (acc <= 50) this.set(gen, "gps", "ok", `${acc.toFixed(0)}m`)
          else if (acc <= 200) this.set(gen, "gps", "warn", `${acc.toFixed(0)}m (low)`, HINTS.gps.low)
          else this.set(gen, "gps", "fail", `${acc.toFixed(0)}m`, HINTS.gps.poor)
          this.checkClock(gen, pos.timestamp)
          resolve()
        },
        (err) => {
          clearTimeout(safetyTimeout)
          const { cause, status } = GPS_ERRORS[err.code] ?? GPS_ERRORS[2]
          this._gpsFailed(gen, cause, status)
          resolve()
        },
        { enableHighAccuracy: true, timeout: 8000 }
      )
    })
  }

  checkClock(gen, gpsMillis) {
    const skewMs = Math.abs(Date.now() - gpsMillis)
    if (skewMs <= 5 * 60 * 1000) this.set(gen, "clock", "ok", `${(skewMs / 1000).toFixed(0)}s skew`)
    else this.set(gen, "clock", "fail", `${Math.round(skewMs / 60000)}m skew (> 5)`, HINTS.clock.skewed)
  }

  // Every GPS failure also strands the clock check, which has no other time
  // source to compare against.
  _gpsFailed(gen, cause, status) {
    this.set(gen, "gps", "fail", status, HINTS.gps[cause])
    this.set(gen, "clock", "warn", "no GPS clock", HINTS.clock.noFix)
  }

  async checkNotifications(gen) {
    if (!("Notification" in window)) return this.set(gen, "notifications", "warn", "unsupported", HINTS.notifications.unsupported)
    if (Notification.permission === "granted") return this.set(gen, "notifications", "ok", "")
    if (Notification.permission === "denied")  return this.set(gen, "notifications", "warn", "blocked", HINTS.notifications.blocked)
    return this.set(gen, "notifications", "warn", "not enabled", HINTS.notifications.notEnabled)
  }

  // Forces a fresh copy of the app: unregister the service worker and drop every
  // Cache Storage entry (the precached shell + fingerprinted assets), then reload
  // so a clean worker reinstalls. Recovers a phone stuck on an old deploy or a
  // broken offline shell. The offline catch queue lives in IndexedDB, which we
  // deliberately leave untouched — pending catches survive the reset.
  async updateApp() {
    // Wiping the SW + caches while offline would reload into an app with neither
    // network nor a precached shell to serve — a bricked PWA until connectivity
    // returns. Refuse and tell the user to get back online first.
    if (!navigator.onLine) {
      this._troubleshoot("⚠ You're offline — reconnect before updating.")
      return
    }
    this._troubleshoot("Updating…")
    try {
      if ("serviceWorker" in navigator) {
        const regs = await navigator.serviceWorker.getRegistrations()
        await Promise.all(regs.map((r) => r.unregister()))
      }
      if ("caches" in window) {
        const keys = await caches.keys()
        await Promise.all(keys.map((k) => caches.delete(k)))
      }
    } catch (e) {
      console.warn("App update/clear-cache failed:", e)
    }
    location.reload()
  }

  _troubleshoot(text) {
    if (this.hasTroubleshootStatusTarget) this.troubleshootStatusTarget.textContent = text
  }
}
