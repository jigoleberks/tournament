import { Controller } from "@hotwired/stimulus"

// Hides the fixed bottom nav while a text-entering control has focus. iOS
// keeps position:fixed elements pinned to the visual viewport, so the opened
// keyboard floats the nav directly over the form — covering the fields being
// typed into and putting the Refresh button (which discards an unsaved catch
// photo/video) one accidental thumb-tap above the keyboard.
export default class extends Controller {
  connect() {
    // Turbo can snapshot the page while the nav is hidden (input focused when
    // the user navigated away, before the 150ms show-timer fired); on a
    // restoration visit that snapshot renders as-is and nothing else would
    // ever remove the class. Nothing has focus right after a restore, so
    // visible is always the correct starting state.
    this.element.classList.remove("hidden")
    this.onFocusIn = (e) => {
      if (!this._wantsKeyboard(e.target)) return
      clearTimeout(this._showTimer)
      this.element.classList.add("hidden")
    }
    this.onFocusOut = () => {
      // Focus hops field-to-field as a blur→focus pair; wait a beat so the
      // nav doesn't flash back in between fields.
      clearTimeout(this._showTimer)
      this._showTimer = setTimeout(() => {
        if (!this._wantsKeyboard(document.activeElement)) {
          this.element.classList.remove("hidden")
        }
      }, 150)
    }
    document.addEventListener("focusin", this.onFocusIn)
    document.addEventListener("focusout", this.onFocusOut)
  }

  disconnect() {
    clearTimeout(this._showTimer)
    document.removeEventListener("focusin", this.onFocusIn)
    document.removeEventListener("focusout", this.onFocusOut)
  }

  _wantsKeyboard(el) {
    if (!el || !el.matches) return false
    if (el.matches("textarea, [contenteditable]")) return true
    if (!el.matches("input")) return false
    return !["checkbox", "radio", "button", "submit", "reset", "file", "range", "color"].includes(el.type)
  }
}
