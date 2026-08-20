import QtQuick
import qs.Commons
import qs.Ui
import "Presets.js" as Presets

Panel {
  id: root
  moduleName: "io.github.ejuro.phosphor"
  ipcTarget: "io.github.ejuro.phosphor"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var builtins: Presets.PRESETS
  readonly property var userPresets: svc ? (svc.userPresets || []) : []
  readonly property var presets: Presets.PRESETS.concat(userPresets)
  readonly property bool activeIsUser: Presets.isUserId(activeId)
  readonly property string activeId: svc ? svc.presetId : ""
  readonly property bool tubeOn: svc ? svc.enabled === true : false
  readonly property int tweakCount: svc && svc.overrides ? Object.keys(svc.overrides).length : 0
  property int selected: 0
  property bool keyboardNav: false

  // Which sections are unfolded. The tube lists earn their space; the rest
  // stays folded until asked for, so the panel opens at a readable height.
  property bool tubesOpen: true
  property bool minesOpen: true
  property bool displayOpen: false
  property bool tuningOpen: false
  property bool colourOpen: false

  function open() {
    root.keyboardNav = false
    root.selected = Math.max(0, indexOf(root.activeId))
    root.controller.show()
  }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) close(); else open() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function indexOf(id) {
    for (var i = 0; i < presets.length; i++) if (presets[i].id === id) return i
    return 0
  }

  // Picking a tube switches it on: choosing a preset while the screen is off
  // and seeing nothing happen would read as a broken control.
  function choose(index) {
    if (!svc || index < 0 || index >= presets.length) return
    root.selected = index
    svc.setPreset(presets[index].id)
    if (!svc.enabled) svc.powerOn()
  }

  function override(key, value) { if (svc) svc.setOverride(key, value) }
  function clearOverride(key) { if (svc) svc.clearOverride(key) }

  function paramOf(key) {
    if (!svc) return 0
    return Presets.resolve(svc.presetId, svc.overrides, svc.userPresets)[key]
  }
  // The tube's own value for a control, ignoring any live tweak — what a
  // toggle should restore when it is switched back on.
  function stockOf(key) {
    if (!svc) return 0
    return Presets.resolve(svc.presetId, null, svc.userPresets)[key]
  }

  // Curvature and flicker are gated behind their own switches: off is the
  // normal state for both, and their sliders only appear once asked for.
  readonly property bool curvatureOn: paramOf("warp") > 0
  readonly property bool flickerOn: paramOf("flicker") > 0

  function setCurvature(on) {
    if (!on) {
      override("warp", 0)
      override("trueWarp", false)
      return
    }
    var stock = stockOf("warp")
    override("warp", stock > 0 ? stock : 0.045)
  }

  function setFlicker(on) {
    if (!on) { override("flicker", 0); return }
    var stock = stockOf("flicker")
    override("flicker", stock > 0 ? stock : 0.06)
  }

  // HSV → RGB for the custom phosphor hue, full value, most of the saturation —
  // real phosphors are never grey.
  function hueToMono(h) {
    var i = Math.floor(h * 6) % 6
    var g = h * 6 - Math.floor(h * 6)
    var v = 1.0, sat = 0.85
    var p0 = v * (1 - sat), q = v * (1 - sat * g), t = v * (1 - sat * (1 - g))
    var m = [[v,t,p0],[q,v,p0],[p0,v,t],[p0,q,v],[t,p0,v],[v,p0,q]][i]
    return [m[0], m[1], m[2]]
  }

  function setPhosphor(mono, white) {
    if (!svc) return
    svc.setOverride("mono", mono)
    if (mono) svc.setOverride("monoWhite", white === undefined ? 0.5 : white)
  }

  function setPlastic(color) {
    if (!svc) return
    svc.setOverride("bezelColor", color)
    svc.setOverride("bezelLight", [Math.min(1, color[0] * 1.32), Math.min(1, color[1] * 1.32), Math.min(1, color[2] * 1.32)])
  }

  function monoColor() {
    var m = paramOf("mono")
    return m ? Qt.rgba(m[0], m[1], m[2], 1) : null
  }

  function dim(a) { return Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, a) }

  // ---- reusable rows -------------------------------------------------------
  // Inline components cannot see the enclosing document's ids, so each takes a
  // `ui` handle back to the panel root instead.

  component Disclosure: Item {
    id: disc
    property var ui
    property string label: ""
    property bool open: true
    signal toggled()

    height: Math.max(discLabel.implicitHeight, Style.space(18))

    Text {
      id: chevron
      anchors.verticalCenter: parent.verticalCenter
      text: disc.open ? "▾" : "▸"
      color: disc.ui ? disc.ui.dim(discHover.containsMouse ? 0.9 : 0.55) : "#888"
      font.family: disc.ui ? disc.ui.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    PanelSectionHeader {
      id: discLabel
      anchors.left: chevron.right
      anchors.leftMargin: Style.space(5)
      anchors.verticalCenter: parent.verticalCenter
      text: disc.label
      foreground: disc.ui ? disc.ui.foreground : Color.foreground
      fontFamily: disc.ui ? disc.ui.fontFamily : Style.font.family
    }

    MouseArea {
      id: discHover
      anchors.fill: parent
      hoverEnabled: true
      onClicked: disc.toggled()
    }
  }

  component TubeRow: Rectangle {
    id: tube
    property var ui
    required property var modelData
    required property int index
    property int indexOffset: 0
    readonly property int idx: index + indexOffset

    height: tubeName.implicitHeight + tubeSub.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: tube.ui && tube.modelData.id === tube.ui.activeId
      ? Style.selectedFillFor(tube.ui.foreground, tube.ui.accent)
      : (tubeHover.containsMouse && tube.ui ? tube.ui.dim(0.06) : "transparent")
    border.width: (tube.ui && tube.ui.keyboardNav && tube.idx === tube.ui.selected) ? 1 : 0
    border.color: tube.ui ? tube.ui.accent : "transparent"

    Column {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      spacing: Style.space(1)

      Text {
        id: tubeName
        text: tube.modelData.name
        color: tube.ui ? tube.ui.foreground : Color.foreground
        font.family: tube.ui ? tube.ui.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        id: tubeSub
        text: tube.modelData.subtitle
        color: tube.ui ? tube.ui.dim(0.55) : "#888"
        font.family: tube.ui ? tube.ui.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: tubeHover
      anchors.fill: parent
      hoverEnabled: true
      onClicked: {
        if (!tube.ui) return
        tube.ui.keyboardNav = false
        tube.ui.choose(tube.idx)
      }
    }
  }

  component SliderRow: Item {
    id: srow
    property var ui
    property string key: ""
    property string label: ""
    property real minimum: 0
    property real maximum: 1
    property real stepSize: 0.01
    property int decimals: 2

    height: srowLabel.implicitHeight + srowSlider.height + Style.space(2)

    Text {
      id: srowLabel
      text: srow.label
      color: srow.ui ? srow.ui.dim(0.75) : "#aaa"
      font.family: srow.ui ? srow.ui.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    // Live readout: follows the knob while dragging, the resolved value otherwise.
    Text {
      anchors.right: parent.right
      text: srow.ui ? Number(srowSlider.dragging ? srowSlider.liveValue : srow.ui.paramOf(srow.key)).toFixed(srow.decimals) : ""
      color: srow.ui ? srow.ui.dim(0.45) : "#888"
      font.family: srow.ui ? srow.ui.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }

    PanelSlider {
      id: srowSlider
      anchors.bottom: parent.bottom
      width: parent.width
      bar: srow.ui ? srow.ui.bar : null
      minimum: srow.minimum
      maximum: srow.maximum
      step: srow.stepSize
      value: srow.ui ? srow.ui.paramOf(srow.key) : 0
      onMoved: function(v) { if (srow.ui) srow.ui.override(srow.key, v) }
      onRightClicked: if (srow.ui) srow.ui.clearOverride(srow.key)
    }
  }

  component ToggleRow: Item {
    id: trow
    property var ui
    property string label: ""
    property string hint: ""
    property bool checked: false
    signal switched()

    height: Math.max(trowText.implicitHeight, trowSwitch.height)

    Column {
      id: trowText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - trowSwitch.width - Style.space(12)
      spacing: Style.space(1)

      Text {
        text: trow.label
        color: trow.ui ? trow.ui.foreground : Color.foreground
        font.family: trow.ui ? trow.ui.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
      Text {
        width: parent.width
        visible: trow.hint !== ""
        text: trow.hint
        color: trow.ui ? trow.ui.dim(0.5) : "#888"
        font.family: trow.ui ? trow.ui.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    ToggleSwitch {
      id: trowSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: trow.checked
      foreground: trow.ui ? trow.ui.foreground : Color.foreground
      accent: trow.ui ? trow.ui.accent : Color.accent
      onToggled: trow.switched()
    }
  }

  component ActionButton: Rectangle {
    id: btn
    property var ui
    property string label: ""
    property color labelColor: ui ? ui.foreground : Color.foreground
    signal clicked()

    height: btnLabel.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: btn.ui ? btn.ui.dim(btnHover.containsMouse ? 0.10 : 0.05) : "#222"

    Text {
      id: btnLabel
      anchors.centerIn: parent
      text: btn.label
      color: btn.labelColor
      font.family: btn.ui ? btn.ui.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
    }
    MouseArea {
      id: btnHover
      anchors.fill: parent
      hoverEnabled: true
      onClicked: btn.clicked()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (renameField.activeFocus) return
        if (dy === 0) return
        root.keyboardNav = true
        // Keyboard navigation runs over the whole list, so both tube sections
        // have to be unfolded or the selection would move out of sight.
        root.tubesOpen = true
        root.minesOpen = true
        root.selected = Math.max(0, Math.min(root.presets.length - 1, root.selected + dy))
      }
      onActivateRequested: {
        if (renameField.activeFocus) {
          renameField.focus = false
          return
        }
        root.keyboardNav = true
        root.choose(root.selected)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (renameField.activeFocus) return
        if ((text === " " || text === "p" || text === "P") && root.svc) root.svc.toggle()
      }

      // On a short screen the card is capped to what fits and the rest
      // scrolls. Flickable's own wheel handling does the scrolling: a
      // WheelHandler here never fires, because the sliders' MouseAreas take
      // wheel events first and Flickable is the path Qt actually delivers to.
      // The sliders are horizontal and the scroll is vertical, so Qt's
      // directional grab leaves a slider drag with the slider.
      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: content
          width: scroller.width
          spacing: Style.space(8)

          // ---- power -------------------------------------------------------
          Item {
            width: parent.width
            height: Math.max(title.implicitHeight, power.height)

            Text {
              id: title
              anchors.verticalCenter: parent.verticalCenter
              text: "PHOSPHOR"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1.2
            }

            ToggleSwitch {
              id: power
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.tubeOn
              busy: root.svc ? root.svc.busy === true : false
              foreground: root.foreground
              accent: root.accent
              onToggled: if (root.svc) root.svc.toggle()
            }
          }

          PanelSeparator { width: parent.width }

          // ---- the tubes ---------------------------------------------------
          Disclosure {
            width: parent.width
            ui: root
            label: "TUBES"
            open: root.tubesOpen
            onToggled: root.tubesOpen = !root.tubesOpen
          }

          Column {
            width: parent.width
            visible: root.tubesOpen
            spacing: Style.space(2)

            Repeater {
              model: root.builtins
              TubeRow {
                width: content.width
                ui: root
              }
            }
          }

          // ---- saved copies ------------------------------------------------
          Disclosure {
            width: parent.width
            visible: root.userPresets.length > 0
            ui: root
            label: "YOUR TUBES"
            open: root.minesOpen
            onToggled: root.minesOpen = !root.minesOpen
          }

          Column {
            width: parent.width
            visible: root.minesOpen && root.userPresets.length > 0
            spacing: Style.space(2)

            Repeater {
              model: root.userPresets
              TubeRow {
                width: content.width
                ui: root
                indexOffset: root.builtins.length
              }
            }

            Item {
              width: parent.width
              height: root.activeIsUser ? renameField.implicitHeight + Style.space(4) : 0
              visible: root.activeIsUser

              TextField {
                id: renameField
                width: parent.width
                foreground: root.foreground
                accent: root.accent
                text: root.activeIsUser ? Presets.byId(root.activeId, root.userPresets).name : ""
                onEditingFinished: if (root.svc && root.activeIsUser) root.svc.renameUserPreset(root.svc.presetId, text)
              }
            }

            // A saved tube with live tweaks on top can adopt them as its new
            // stock or drop them. Built-in tubes never get this row.
            Row {
              width: parent.width
              spacing: Style.space(8)
              visible: root.activeIsUser && root.tweakCount > 0

              ActionButton {
                width: (parent.width - Style.space(8)) / 2
                ui: root
                label: "Keep changes"
                onClicked: if (root.svc) root.svc.updateUserPreset(root.svc.presetId)
              }
              ActionButton {
                width: (parent.width - Style.space(8)) / 2
                ui: root
                label: "Discard changes"
                onClicked: if (root.svc) root.svc.clearOverrides()
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            ActionButton {
              width: (parent.width - Style.space(8)) / 2
              ui: root
              label: "Save a copy"
              onClicked: if (root.svc) root.svc.savePreset()
            }
            ActionButton {
              width: (parent.width - Style.space(8)) / 2
              ui: root
              label: root.activeIsUser ? "Delete this tube" : "Reset to stock"
              labelColor: root.activeIsUser ? Color.urgent : root.foreground
              onClicked: {
                if (!root.svc) return
                if (root.activeIsUser) root.svc.deleteUserPreset(root.svc.presetId)
                else root.svc.clearOverrides()
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ---- display -----------------------------------------------------
          Disclosure {
            width: parent.width
            ui: root
            label: "DISPLAY"
            open: root.displayOpen
            onToggled: root.displayOpen = !root.displayOpen
          }

          Column {
            width: parent.width
            visible: root.displayOpen
            spacing: Style.space(8)

            ToggleRow {
              width: parent.width
              ui: root
              label: "Cabinet"
              hint: "Reserves the margins, so the desktop is laid out inside the glass — nothing moves away from where it clicks."
              checked: root.svc ? root.svc.bezel === true : true
              onSwitched: if (root.svc) root.svc.setBezel(!root.svc.bezel)
            }

            ToggleRow {
              width: parent.width
              visible: root.svc ? root.svc.bezel === true : true
              ui: root
              label: "Even frame"
              hint: "All four sides the same width. The deep chin is what carries the badge, knobs and power lamp, so an even frame drops them — and the wider rails push the bar inward, which opens plugin drawers slightly offset from their icons."
              checked: root.paramOf("evenFrame") === true
              onSwitched: root.override("evenFrame", !(root.paramOf("evenFrame") === true))
            }

            ToggleRow {
              width: parent.width
              ui: root
              label: "Power fade"
              hint: (root.svc && root.svc.animate === true)
                ? ""
                : "On: black, a breath, the picture warms up. Off: the phosphor dies, then your desktop. Costs GPU only for the moment it lasts."
              checked: root.svc ? root.svc.animate === true : false
              onSwitched: if (root.svc) root.svc.setAnimate(!root.svc.animate)
            }

            Column {
              width: parent.width
              visible: root.svc ? root.svc.animate === true : false
              spacing: Style.space(4)

              Item {
                width: parent.width
                height: warmLabel.implicitHeight + warmSlider.height + Style.space(2)

                Text {
                  id: warmLabel
                  text: "Warm-up"
                  color: root.dim(0.75)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  anchors.right: parent.right
                  text: Number(warmSlider.dragging ? warmSlider.liveValue
                                                   : (root.svc ? root.svc.warmupTime : 1.4)).toFixed(1) + "s"
                  color: root.dim(0.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                PanelSlider {
                  id: warmSlider
                  anchors.bottom: parent.bottom
                  width: parent.width
                  bar: root.bar
                  minimum: 0.4
                  maximum: 3.0
                  step: 0.1
                  value: root.svc ? root.svc.warmupTime : 1.4
                  onMoved: function(v) { if (root.svc) root.svc.setWarmupTime(v) }
                  onRightClicked: if (root.svc) root.svc.setWarmupTime(1.4)
                }
              }

              Text {
                width: parent.width
                text: "How long the tube takes to come up — dark for the first part of it, the picture rising out of the black through the rest. Switching off stays quick either way."
                color: root.dim(0.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ---- tuning ------------------------------------------------------
          Disclosure {
            width: parent.width
            ui: root
            label: "TUNING"
            open: root.tuningOpen
            onToggled: root.tuningOpen = !root.tuningOpen
          }

          Column {
            width: parent.width
            visible: root.tuningOpen
            spacing: Style.space(8)

            // Two columns keep ten controls from doubling the panel's height.
            // Ranges are normalised so the stock values sit in the lower half:
            // subtle stays easy to find, exaggerated stays reachable.
            Grid {
              width: parent.width
              columns: 2
              columnSpacing: Style.space(10)
              rowSpacing: Style.space(4)

              Repeater {
                model: [
                  { key: "bright",     label: "Brightness",  min: 0.7, max: 1.8, step: 0.01, dec: 2 },
                  { key: "contrast",   label: "Contrast",    min: 0.6, max: 1.5, step: 0.01, dec: 2 },
                  { key: "saturation", label: "Colour",      min: 0.0, max: 1.5, step: 0.01, dec: 2 },
                  { key: "bloom",      label: "Bloom",       min: 0.0, max: 1.0, step: 0.01, dec: 2 },
                  { key: "scanline",   label: "Scanlines",   min: 0.0, max: 0.6, step: 0.01, dec: 2 },
                  { key: "scanPitch",  label: "Scan pitch",  min: 2.0, max: 8.0, step: 0.5,  dec: 1 },
                  { key: "mask",       label: "Mask",        min: 0.0, max: 0.8, step: 0.01, dec: 2 },
                  { key: "vignette",   label: "Vignette",    min: 0.0, max: 0.7, step: 0.01, dec: 2 },
                  { key: "converge",   label: "Convergence", min: 0.0, max: 2.0, step: 0.05, dec: 2 },
                  { key: "noise",      label: "Grain",       min: 0.0, max: 0.3, step: 0.01, dec: 2 }
                ]

                SliderRow {
                  required property var modelData
                  width: (content.width - Style.space(10)) / 2
                  ui: root
                  key: modelData.key
                  label: modelData.label
                  minimum: modelData.min
                  maximum: modelData.max
                  stepSize: modelData.step
                  decimals: modelData.dec
                }
              }
            }

            // ---- curvature -------------------------------------------------
            ToggleRow {
              width: parent.width
              ui: root
              label: "Curvature"
              hint: root.curvatureOn ? "" : "Rounds the corners and falls the edges away into shadow."
              checked: root.curvatureOn
              onSwitched: root.setCurvature(!root.curvatureOn)
            }

            Column {
              width: parent.width
              visible: root.curvatureOn
              spacing: Style.space(6)

              SliderRow {
                width: parent.width
                ui: root
                key: "warp"
                label: "Glass curve"
                minimum: 0.005
                maximum: 0.12
                stepSize: 0.005
                decimals: 3
              }

              ToggleRow {
                width: parent.width
                ui: root
                label: "Bend the picture"
                hint: "Real curvature. The picture itself bends, so clicks near the edges land slightly off from where things appear, and things can crowd the corners. Off, the curve is drawn at the glass and nothing moves."
                checked: root.paramOf("trueWarp") === true
                onSwitched: root.override("trueWarp", !(root.paramOf("trueWarp") === true))
              }
            }

            // ---- flicker ---------------------------------------------------
            ToggleRow {
              width: parent.width
              ui: root
              label: "Flicker"
              hint: root.flickerOn ? "" : "Unsteady brightness, and grain that moves. The one setting with a real GPU cost."
              checked: root.flickerOn
              onSwitched: root.setFlicker(!root.flickerOn)
            }

            Column {
              width: parent.width
              visible: root.flickerOn
              spacing: Style.space(4)

              SliderRow {
                width: parent.width
                ui: root
                key: "flicker"
                label: "Flicker"
                minimum: 0.01
                maximum: 0.25
                stepSize: 0.01
                decimals: 2
              }

              Text {
                width: parent.width
                text: "The tube now redraws every frame, so a still screen no longer costs nothing. Grain comes alive with it."
                color: root.dim(0.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ---- colour ------------------------------------------------------
          Disclosure {
            width: parent.width
            ui: root
            label: "COLOUR"
            open: root.colourOpen
            onToggled: root.colourOpen = !root.colourOpen
          }

          Column {
            width: parent.width
            visible: root.colourOpen
            spacing: Style.space(8)

            Text {
              text: "Phosphor"
              color: root.dim(0.75)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.space(6)

              // First swatch is "Theme": the tube shows your theme's own colours.
              Repeater {
                model: [
                  { name: "Theme", mono: null,                 white: 0.5  },
                  { name: "Green", mono: [0.35, 1.00, 0.42],   white: 0.55 },
                  { name: "Amber", mono: [1.00, 0.68, 0.16],   white: 0.50 },
                  { name: "Paper", mono: [0.93, 0.95, 1.00],   white: 0.35 },
                  { name: "Cyan",  mono: [0.30, 0.95, 0.85],   white: 0.50 },
                  { name: "Blue",  mono: [0.45, 0.62, 1.00],   white: 0.50 }
                ]

                Rectangle {
                  required property var modelData
                  width: Style.space(30)
                  height: Style.space(20)
                  radius: Style.cornerRadius
                  color: modelData.mono
                    ? Qt.rgba(modelData.mono[0] * 0.85, modelData.mono[1] * 0.85, modelData.mono[2] * 0.85, 1)
                    : "transparent"
                  border.width: 1
                  border.color: root.dim(swatchHover.containsMouse ? 0.9 : 0.35)

                  Text {
                    anchors.centerIn: parent
                    visible: !parent.modelData.mono
                    text: "T"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: swatchHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.setPhosphor(parent.modelData.mono, parent.modelData.white)
                  }
                }
              }
            }

            Item {
              width: parent.width
              height: hueLabel.implicitHeight + hueSlider.height + Style.space(4)

              Text {
                id: hueLabel
                text: "Custom hue"
                color: root.dim(0.75)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              PanelSlider {
                id: hueSlider
                anchors.bottom: parent.bottom
                width: parent.width
                bar: root.bar
                minimum: 0
                maximum: 1
                step: 0.01
                value: 0.33
                fillColor: root.monoColor() || (root.bar ? root.bar.foreground : root.foreground)
                onMoved: function(v) { root.setPhosphor(root.hueToMono(v), 0.5) }
              }
            }

            Text {
              text: "Plastic"
              color: root.dim(0.75)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.space(6)

              Repeater {
                model: [
                  { name: "Beige",    c: [0.505, 0.470, 0.395] },
                  { name: "Cream",    c: [0.560, 0.552, 0.520] },
                  { name: "Ivory",    c: [0.620, 0.600, 0.550] },
                  { name: "Graphite", c: [0.225, 0.232, 0.258] },
                  { name: "Charcoal", c: [0.180, 0.176, 0.170] }
                ]

                Rectangle {
                  required property var modelData
                  width: Style.space(30)
                  height: Style.space(20)
                  radius: Style.cornerRadius
                  color: Qt.rgba(modelData.c[0], modelData.c[1], modelData.c[2], 1)
                  border.width: 1
                  border.color: root.dim(plasticHover.containsMouse ? 0.9 : 0.35)

                  MouseArea {
                    id: plasticHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.setPlastic(parent.modelData.c)
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            text: "Right-click a slider to put that one control back to stock; “Reset to stock” drops every tweak."
            color: root.dim(0.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
