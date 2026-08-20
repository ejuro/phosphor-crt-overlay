import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.ejuro.phosphor"

  // The service owns the tube; the widget is only a handle on it. Third-party
  // services resolve through the same lookup the first-party ones use.
  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("io.github.ejuro.phosphor") : null
  readonly property bool tubeOn: svc ? svc.enabled === true : false
  readonly property string presetName: svc ? presetLabel(svc.presetId) : ""

  function presetLabel(id) {
    var list = presetsFor()
    for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i].name
    return id
  }
  function presetsFor() { return panelLoader.item ? panelLoader.item.presets : [] }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.svc = root.svc
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSvcChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.ejuro.phosphor"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍹"
    tooltipText: root.tubeOn
      ? "Phosphor · " + root.presetName + " · right-click to switch off"
      : "Phosphor · off · right-click to switch on"
    // The icon lights up while the tube is on, which is the one piece of state
    // worth reading from across the room.
    active: root.tubeOn
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) { if (root.svc) root.svc.toggle() }
      else root.toggle()
    }
  }
}
