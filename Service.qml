import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "Presets.js" as Presets
import "ShaderBuilder.js" as ShaderBuilder

// Owns the virtual monitor: generates the shader, applies it, and keeps it
// applied. Nothing here touches colours, wallpaper or styling — those belong to
// the theme, and the two must never disturb each other.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/phosphor"
  readonly property string statePath: stateRoot + "/state.json"
  readonly property string shaderPath: stateRoot + "/current.frag"

  property bool enabled: false
  property string presetId: "trinitron"
  property var overrides: ({})
  property bool animate: true
  // How long the tube takes to come up, in seconds: black for the first 40% of
  // it, the picture rising out of the black through the rest. A transition
  // preference rather than a property of any one tube, so it lives here beside
  // `animate` and survives switching tubes. Switching off is not scaled by it —
  // the asymmetry is the point.
  property real warmupTime: 1.4
  // The cabinet is lovely and it costs pointer accuracy: insetting the picture
  // moves everything away from where it responds, the bar most of all. Kept as
  // a display-mode choice rather than a preset value so it survives switching
  // tubes and resetting sliders.
  property bool bezel: true
  // Saved copies of tubes, owned by the user. Stored in state.json; built-in
  // presets are never mutated, so "reset to stock" is just dropping overrides.
  property var userPresets: []
  // Bumped whenever anything that shapes the tube changes, so the reserve
  // strips below re-derive their zones.
  property int paramsRevision: 0
  property bool loaded: false
  property bool busy: false

  // Baselines are captured before Phosphor first changes anything and are
  // persisted, so a shell restart mid-session can still put them back.
  property int baseDamage: -1

  // Dark scanlines across a white background read far harsher than light ones
  // across black, so the tube is gentler under a light theme. Derived from the
  // shell's own palette singleton, which updates on every theme change.
  readonly property bool lightTheme: {
    var c = Color.background
    return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) > 0.5
  }

  property string pendingMode: "static"
  // The damage-tracking mode the pending shader needs, applied atomically with it.
  property int pendingDamage: 1
  // FileView does not write — and so never emits `saved` — when the new text is
  // identical to what is already on disk, which is the common case: enabling
  // the same tube twice regenerates the same bytes. Applying only from
  // `onSaved` therefore silently did nothing. Each render gets a generation
  // number and is applied exactly once, by whichever of the two paths runs.
  property int renderGeneration: 0
  property int appliedGeneration: 0

  signal changed()
  onChanged: root.paramsRevision = root.paramsRevision + 1

  // ---- Hyprland plumbing ---------------------------------------------------
  // Quattro configures Hyprland in Lua, and `hyprctl keyword` refuses to work
  // with a non-legacy parser ("keyword can't work with non-legacy parsers. Use
  // eval."), so everything goes through `hyprctl eval`. Note that an empty
  // string clears the shader; the usual [[EMPTY]] sentinel would be parsed as
  // Lua long-bracket string syntax and set it to the literal text "EMPTY".
  function hypr(lua) {
    Quickshell.execDetached(["hyprctl", "eval", lua])
  }

  // Hyprland reads debug:damage_tracking at the moment it loads a screen
  // shader and complains if an animated shader arrives while tracking is on,
  // so damage tracking has to be set FIRST — every time, guaranteed.
  //
  // Two `hyprctl eval` calls are two processes with no ordering between them.
  // One call with both keys in a single table is no better: Lua table key order
  // is unspecified, so the shader may still be applied before the debug key.
  // Two statements in one eval are ordered by Lua's own semantics.
  function applyWith(damage, shader) {
    hypr('hl.config({ debug = { damage_tracking = ' + Math.round(damage) + ' } }); ' +
         'hl.config({ decoration = { screen_shader = "' + shader + '" } })')
  }

  function applyShaderFile() { applyWith(root.pendingDamage, root.shaderPath) }

  function clearShaderOption(damage) { applyWith(damage, "") }

  // ---- rendering -----------------------------------------------------------
  function currentParams() {
    return Presets.resolve(root.presetId, root.overrides, root.userPresets)
  }

  // ---- reserved margins ------------------------------------------------
  // The cabinet does not shrink the picture. Instead these zones make Hyprland
  // lay the desktop out inside the glass: invisible, click-through strips carry
  // exclusive zones matching the bezel, and the bar and every window respect
  // them. The shader then samples 1:1 — nothing on screen is displaced from
  // where it clicks. The strips live on the BOTTOM layer because Hyprland
  // arranges layers background→overlay: only a strip arranged before the bar
  // (Top layer) can reserve space the bar will honour.
  readonly property var zoneParams: {
    var rev = root.paramsRevision  // dependency: re-derive when the tube changes
    return rev >= 0 ? currentParams() : null
  }
  readonly property bool zonesActive: root.enabled && root.bezel && root.loaded

  // ---- keeping the picture moving ------------------------------------------
  // Hyprland re-renders a monitor when something damages it. A shader's `time`
  // advancing is not damage: on an idle desktop a power transient repaints only
  // on the two or three occasions something else happens to change, which turns
  // a smooth fade into a couple of visible steps. Measured with nvidia-smi, a
  // three-second warm-up drew one brief burst and then sat at idle.
  //
  // So while a timed shader is loaded, something has to commit a buffer every
  // frame. The strip below is that something.
  readonly property bool live: {
    var rev = root.paramsRevision
    return rev >= 0 && root.enabled && Number(currentParams().flicker) > 0
  }
  readonly property bool needsFrames: root.busy || (root.live && root.loaded)

  function edgeZone(screenItem, edge) {
    if (!root.zonesActive || !screenItem) return 0
    var p = root.zoneParams
    var half = screenItem.height / 2
    // Must mirror ShaderBuilder exactly: slim lip on the rails that would
    // displace the bar (Omarchy's drawer popups assume an edge-glued bar),
    // full chin on the bottom, which displaces nothing — unless the user has
    // asked for an even frame, which makes all four sides the rail width.
    var even = p.evenFrame === true
    var frac = edge === "bottom"
      ? p.bezelWidth * (even ? 1.0 : p.chin)
      : (even ? p.bezelWidth : Math.min(p.bezelWidth, 0.010))
    return Math.max(0, Math.round(frac * half))
  }

  // A tube tuned with flicker above zero needs the timed shader permanently,
  // and `time` is only fed while damage tracking is fully off — the one
  // tuning that trades the idle skip away, and it says so in the panel.
  function tubeIsLive() { return Number(currentParams().flicker) > 0 }
  function litDamage() { return tubeIsLive() ? 0 : root.staticDamage }

  // mode: "static" | "on" | "off"
  // Modes that declare `time` (the power transients, and "live" — which
  // render() substitutes for "static" when the tube flickers) must be applied
  // with damage = 0, because Hyprland only feeds `time` in that mode.
  function render(mode, damage) {
    if (mode === "static" && tubeIsLive()) mode = "live"
    root.pendingMode = mode
    root.pendingDamage = (damage === undefined)
      ? (mode === "static" ? root.staticDamage : 0)
      : damage
    root.renderGeneration += 1
    var src = ShaderBuilder.build(root.currentParams(), {
      light: root.lightTheme,
      bezel: root.bezel,
      mode: mode,
      warmup: root.warmupTime
    })
    shaderFile.setText(src)
    applyFallbackTimer.restart()
  }

  // Applied once per render, whichever path gets there first.
  function applyRendered() {
    if (root.appliedGeneration === root.renderGeneration) return
    root.appliedGeneration = root.renderGeneration
    applyFallbackTimer.stop()
    applyShaderFile()
    // A transient's clock starts when Hyprland loads the shader, not when the
    // toggle was pressed: writing the file and the hyprctl round trip cost
    // 100-200ms, and timing the swap from the keypress cut the fade off while
    // the screen was still black — which read as a blink rather than a fade.
    if (root.pendingMode === "on" || root.pendingMode === "off") transientTimer.restart()
  }

  // Deliberately does NOT force software cursors. Hyprland never warps input
  // hit-testing, so a hardware cursor — drawn at the true input position —
  // agrees with where clicks actually land. Forcing software cursors makes the
  // pointer follow the warped picture instead, which puts it somewhere other
  // than the thing it is pointing at, worst of all near the screen edges where
  // the bar lives.
  //
  // Region damage tracking cannot be left on while the tube is lit. The shader
  // reads neighbouring texels (bloom, convergence) and displaces coordinates
  // (warp), so pixels outside a damage rectangle still need re-shading and
  // never get it — which trails smears behind anything that moves. Mode 1
  // (DAMAGE_TRACKING_MONITOR) invalidates the whole monitor when anything is
  // damaged, and unlike mode 0 it still skips rendering when nothing changed.
  readonly property int staticDamage: 1

  function powerOn() {
    if (root.enabled || root.busy) return
    root.enabled = true
    root.saveState()

    if (root.animate) {
      // Power-on: the desktop drops to black at once, holds dark while the
      // tube warms, then the picture fades up with the phosphor already lit.
      // The envelope finishes `warmupTime` after the shader loads; the timer is
      // started from the apply, and overshooting it is harmless because the
      // transient ends identical to the static shader.
      root.busy = true
      transientTimer.interval = Math.round((0.04 + root.warmupTime) * 1000) + 80
      render("on", 0)
    } else {
      render("static")
    }
    root.changed()
  }

  function powerOff() {
    if (!root.enabled || root.busy) return
    root.enabled = false
    root.saveState()

    if (root.animate) {
      // Power-off: the phosphor dies to black fast (~150ms), the screen holds
      // dark a beat, and the shader is cleared while it is still black — so
      // the plain desktop returns in one step, no second fade.
      root.busy = true
      transientTimer.interval = 230
      render("off", 0)
    } else {
      finishPowerOff()
    }
    root.changed()
  }

  // Put back exactly what was there. 2 is Hyprland's default region tracking.
  //
  // Dropping straight from mode 0 to region tracking leaves whatever the tube
  // last drew sitting in any region nothing happens to touch — CRT-looking
  // smears that linger until something damages them. Clearing at mode 1 forces
  // one whole-monitor redraw of the plain desktop first; the baseline goes back
  // a beat later, once there is nothing left to smear.
  function finishPowerOff() {
    clearShaderOption(1)
    restoreDamageTimer.restart()
    root.busy = false
  }

  function toggle() { root.enabled ? powerOff() : powerOn() }

  function setPreset(id) {
    root.presetId = Presets.byId(id, root.userPresets).id
    root.overrides = ({})
    root.saveState()
    if (root.enabled && !root.busy) render("static")
    root.changed()
  }

  function setOverride(key, value) {
    var next = {}
    for (var k in root.overrides) next[k] = root.overrides[k]
    next[key] = value
    root.overrides = next
    root.saveState()
    if (root.enabled && !root.busy) render("static")
    root.changed()
  }

  // Right-click on a single slider: put just that control back to the tube's
  // stock value, leaving every other tweak alone.
  function clearOverride(key) {
    if (!(key in root.overrides)) return
    var next = {}
    for (var k in root.overrides) if (k !== key) next[k] = root.overrides[k]
    root.overrides = next
    root.saveState()
    if (root.enabled && !root.busy) render("static")
    root.changed()
  }

  function setBezel(on) {
    if (root.bezel === !!on) return
    root.bezel = !!on
    root.saveState()
    if (root.enabled && !root.busy) render("static")
    root.changed()
  }

  function savePreset() {
    var base = Presets.byId(root.presetId, root.userPresets)
    var entry = {
      id: "user-" + Date.now(),
      name: Presets.copyName(base.name, root.userPresets),
      subtitle: "your copy of " + base.name,
      params: currentParams()
    }
    var next = root.userPresets.slice()
    next.push(entry)
    root.userPresets = next
    root.presetId = entry.id
    root.overrides = ({})
    root.saveState()
    root.changed()
    return entry.id
  }

  // Fold the current tweaks into a saved tube, making them its new stock.
  // Only user copies can be overwritten; the built-ins stay immutable.
  function updateUserPreset(id) {
    if (!Presets.isUserId(id)) return
    var params = currentParams()
    var next = []
    for (var i = 0; i < root.userPresets.length; i++) {
      var u = root.userPresets[i]
      if (u.id === id) u = { id: u.id, name: u.name, subtitle: u.subtitle, params: params }
      next.push(u)
    }
    root.userPresets = next
    if (root.presetId === id) root.overrides = ({})
    root.saveState()
    root.changed()
  }

  function renameUserPreset(id, name) {
    name = String(name || "").trim().slice(0, 48)
    if (!Presets.isUserId(id) || name === "") return
    var next = []
    for (var i = 0; i < root.userPresets.length; i++) {
      var u = root.userPresets[i]
      if (u.id === id) u = { id: u.id, name: name, subtitle: u.subtitle, params: u.params }
      next.push(u)
    }
    root.userPresets = next
    root.saveState()
    root.changed()
  }

  function deleteUserPreset(id) {
    if (!Presets.isUserId(id)) return
    var next = []
    for (var i = 0; i < root.userPresets.length; i++)
      if (root.userPresets[i].id !== id) next.push(root.userPresets[i])
    root.userPresets = next
    if (root.presetId === id) {
      root.presetId = "trinitron"
      root.overrides = ({})
      if (root.enabled && !root.busy) render("static")
    }
    root.saveState()
    root.changed()
  }

  function setAnimate(on) {
    if (root.animate === !!on) return
    root.animate = !!on
    root.saveState()
    root.changed()
  }

  // Only shapes the next power-on, so there is nothing to re-render here.
  function setWarmupTime(seconds) {
    var v = Number(seconds)
    if (isNaN(v)) return
    root.warmupTime = Math.max(0.4, Math.min(3.0, v))
    root.saveState()
  }

  function clearOverrides() {
    root.overrides = ({})
    root.saveState()
    if (root.enabled && !root.busy) render("static")
    root.changed()
  }

  // A reload drops every runtime value set through eval, so anything that
  // reloads Hyprland — a theme switch above all — silently turns Phosphor off
  // unless it is put back. omarchy-theme-set calls omarchy-restart-hyprctl,
  // which is exactly `hyprctl reload`.
  // A reload restores the configured damage tracking along with everything
  // else, so both go back together.
  function reapply() {
    if (!root.enabled || root.busy) return
    root.pendingDamage = root.litDamage()
    applyShaderFile()
  }

  // ---- persistence ---------------------------------------------------------
  function loadState(text) {
    var data = null
    try { data = JSON.parse(String(text || "")) } catch (e) { data = null }
    if (data && typeof data === "object") {
      root.enabled = !!data.enabled
      root.userPresets = Array.isArray(data.userPresets) ? data.userPresets : []
      root.presetId = Presets.byId(data.preset || "trinitron", root.userPresets).id
      root.overrides = (data.overrides && typeof data.overrides === "object") ? data.overrides : ({})
      root.animate = (data.animate === undefined) ? true : !!data.animate
      if (typeof data.warmupTime === "number")
        root.warmupTime = Math.max(0.4, Math.min(3.0, data.warmupTime))
      root.bezel = (data.bezel === undefined) ? true : !!data.bezel
      if (data.baseline && typeof data.baseline === "object") {
        root.baseDamage = (typeof data.baseline.damage === "number") ? data.baseline.damage : -1
      }
    }
    root.loaded = true

    // A shell restart with Phosphor left on must put the tube back, without
    // replaying the power-on animation.
    if (root.enabled) {
      render("static")
    }
    if (root.baseDamage < 0) baselineProc.running = true
    root.changed()
  }

  function saveState() {
    if (!root.loaded) return
    saveTimer.restart()
  }

  function flushState() {
    stateFile.setText(JSON.stringify({
      version: 1,
      enabled: root.enabled,
      preset: root.presetId,
      overrides: root.overrides,
      userPresets: root.userPresets,
      animate: root.animate,
      warmupTime: root.warmupTime,
      bezel: root.bezel,
      baseline: { damage: root.baseDamage }
    }, null, 2) + "\n")
  }

  onLightThemeChanged: if (root.enabled && !root.busy && root.loaded) render("static")

  Component.onCompleted: ensureStateDir.running = true

  Process {
    id: ensureStateDir
    command: ["mkdir", "-p", root.stateRoot]
    running: false
    onExited: stateFile.reload()
  }

  // Read what the session looked like before Phosphor touched it, so "off"
  // really is off rather than whatever the defaults happen to be.
  Process {
    id: baselineProc
    running: false
    command: ["bash", "-c",
      "hyprctl getoption debug:damage_tracking -j | grep -o '\"int\": *[0-9-]*' | grep -o '[0-9-]*$'"]
    stdout: StdioCollector {
      onStreamFinished: {
        var v = parseInt(String(text || "").trim(), 10)
        if (root.baseDamage < 0) root.baseDamage = isNaN(v) ? 2 : v
        root.saveState()
      }
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  FileView {
    id: shaderFile
    path: root.shaderPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    // Apply only once the file is actually on disk, or Hyprland can read the
    // previous generation.
    onSaved: root.applyRendered()
  }

  // Covers the case where FileView had nothing to write.
  Timer {
    id: applyFallbackTimer
    interval: 90
    repeat: false
    onTriggered: root.applyRendered()
  }

  Timer {
    id: saveTimer
    interval: 150
    repeat: false
    onTriggered: root.flushState()
  }

  // The power transient runs with damage tracking off, which Hyprland warns is
  // expensive. It lasts a beat, then the cheap static shader takes over.
  Timer {
    id: transientTimer
    interval: 1450
    repeat: false
    onTriggered: {
      if (root.enabled) {
        render("static")
      } else {
        finishPowerOff()
      }
      root.busy = false
    }
  }

  Timer {
    id: reapplyTimer
    interval: 250
    repeat: false
    onTriggered: root.reapply()
  }

  // Second half of finishPowerOff: hand damage tracking back once the plain
  // desktop has been drawn whole at least once.
  Timer {
    id: restoreDamageTimer
    interval: 120
    repeat: false
    onTriggered: if (!root.enabled) root.clearShaderOption(root.baseDamage >= 0 ? root.baseDamage : 2)
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.zonesActive
      color: "transparent"
      anchors { top: true; left: true; right: true }
      implicitHeight: 1
      exclusiveZone: root.edgeZone(modelData, "top")
      WlrLayershell.namespace: "phosphor-reserve"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
    }
  }
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.zonesActive
      color: "transparent"
      anchors { bottom: true; left: true; right: true }
      implicitHeight: 1
      exclusiveZone: root.edgeZone(modelData, "bottom")
      WlrLayershell.namespace: "phosphor-reserve"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
    }
  }
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.zonesActive
      color: "transparent"
      anchors { left: true; top: true; bottom: true }
      implicitWidth: 1
      exclusiveZone: root.edgeZone(modelData, "left")
      WlrLayershell.namespace: "phosphor-reserve"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
    }
  }
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.zonesActive
      color: "transparent"
      anchors { right: true; top: true; bottom: true }
      implicitWidth: 1
      exclusiveZone: root.edgeZone(modelData, "right")
      WlrLayershell.namespace: "phosphor-reserve"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}
    }
  }

  // A 1×1 transparent, click-through surface that commits a new buffer every
  // frame while a transient runs or the tube is live. Invisible in itself — the
  // point is the commit, which is the damage that keeps Hyprland redrawing the
  // monitor so `time` actually reaches the screen. Overlay so it can never be
  // occluded away, and it reserves nothing.
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.needsFrames
      color: "transparent"
      anchors { top: true; left: true }
      implicitWidth: 1
      implicitHeight: 1
      exclusiveZone: 0
      WlrLayershell.namespace: "phosphor-tick"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        // Both alphas are far below anything the eye can resolve; what matters
        // is only that the buffer differs from the last one.
        color: ticker.odd ? "#01ffffff" : "#02ffffff"
      }

      FrameAnimation {
        id: ticker
        running: root.needsFrames
        property bool odd: false
        onTriggered: ticker.odd = !ticker.odd
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event && event.name ? event.name : "") === "configreloaded") reapplyTimer.restart()
    }
  }

  IpcHandler {
    target: "phosphor"

    function enable(): void { root.powerOn() }
    function disable(): void { root.powerOff() }
    function toggle(): void { root.toggle() }
    function preset(id: string): void { root.setPreset(id) }
    function reapply(): void { root.reapply() }
    function cabinet(on: string): void { root.setBezel(String(on) !== "false" && String(on) !== "off") }
    function warmup(on: string): void { root.setAnimate(String(on) !== "false" && String(on) !== "off") }
    function fade(seconds: string): void { root.setWarmupTime(parseFloat(String(seconds))) }
    // Scriptable tuning: `omarchy-shell phosphor set flicker 0.1`,
    // `set trueWarp true`, `stock flicker`. Values are clamped by the shader
    // builder, so nothing typed here can produce a shader that fails.
    function set(key: string, value: string): void {
      var s = String(value)
      var v
      if (s === "true") v = true
      else if (s === "false") v = false
      else { v = parseFloat(s); if (isNaN(v)) return }
      root.setOverride(String(key), v)
    }
    function stock(key: string): void { root.clearOverride(String(key)) }
    function save(): string { return root.savePreset() }
    function keep(): void { root.updateUserPreset(root.presetId) }
    function reset(): void { root.clearOverrides() }
    function remove(): void { root.deleteUserPreset(root.presetId) }
    function rename(name: string): void { root.renameUserPreset(root.presetId, name) }
    function status(): string {
      return JSON.stringify({ enabled: root.enabled, preset: root.presetId, light: root.lightTheme,
                              bezel: root.bezel, warmup: root.animate, fade: root.warmupTime,
                              damage: root.enabled ? root.litDamage() : root.baseDamage })
    }
  }
}
