import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// One instance per monitor. IPC lives on the service, not here.
BarWidget {
  id: root
  moduleName: "io.mcmurray.freenet-explorer"

  // Bumped to retry the lookup if the service appeared after this widget.
  property int lookupTick: 0
  property var service: lookupService(lookupTick)
  property bool opened: false
  property bool popoutSwitchClosing: false

  readonly property bool nodeUp: service ? service.nodeUp === true : false
  readonly property bool explorerUp: service ? service.explorerUp === true : false
  readonly property int hosted: service ? service.hosted : -1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function lookupService(tick) {
    var shell = root.bar ? root.bar.shell : null
    if (shell && typeof shell.serviceFor === "function")
      return shell.serviceFor("io.mcmurray.freenet-explorer") || null
    return null
  }

  function retryLookup() {
    if (!root.service)
      root.lookupTick += 1
  }

  function open(): void {
    root.retryLookup()
    root.popoutSwitchClosing = false
    root.opened = true
  }

  function close(): void {
    root.opened = false
  }

  function toggle(): void {
    if (root.opened)
      root.close()
    else
      root.open()
  }

  function closeForPopoutSwitch(): void {
    root.popoutSwitchClosing = true
    root.opened = false
    Qt.callLater(root.endPopoutSwitch)
  }

  function endPopoutSwitch() {
    root.popoutSwitchClosing = false
  }

  function assignPanel() {
    var panel = panelLoader.item
    if (!panel)
      return
    panel.bar = root.bar
    panel.settings = root.settings
    panel.anchorItem = button
    panel.service = root.service
    panel.hostWidget = root
  }

  onBarChanged: assignPanel()
  onSettingsChanged: assignPanel()
  onServiceChanged: {
    assignPanel()
    if (root.service && root.opened)
      root.service.panelOpened()
  }
  onOpenedChanged: {
    if (!root.service)
      return
    if (root.opened)
      root.service.panelOpened()
    else
      root.service.panelClosed()
  }
  Component.onCompleted: Qt.callLater(root.retryLookup)
  Component.onDestruction: {
    if (root.service && root.opened)
      root.service.panelClosed()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: Logic.tooltipText(root.nodeUp, root.explorerUp, root.hosted)
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton)
        root.toggle()
    }

    // A bare Canvas child does not count as content, so WidgetButton stays
    // invisible. iconComponent is what the bar button actually paints.
    // Down: hollow ring. Node only: ring with a core. Running: three linked nodes.
    iconComponent: Component {
      Canvas {
        id: glyph
        width: Style.space(16)
        height: Style.space(16)

        readonly property string mode: Logic.glyphState(root.nodeUp, root.explorerUp)
        readonly property color foreground: (root.bar && (root.bar.foreground || root.bar.barForeground)) || Color.bar.text
        readonly property color tint: mode === "running" ? foreground
          : mode === "nodeOnly" ? Color.urgent
          : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.4)

        onModeChanged: requestPaint()
        onTintChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.scale(width / 16, height / 16)
          ctx.strokeStyle = glyph.tint
          ctx.fillStyle = glyph.tint
          ctx.lineWidth = 1.5

          function dot(x, y, r) {
            ctx.beginPath()
            ctx.arc(x, y, r, 0, 2 * Math.PI)
            ctx.fill()
          }

          if (glyph.mode === "running") {
            ctx.beginPath()
            ctx.moveTo(8, 3)
            ctx.lineTo(13, 12)
            ctx.lineTo(3, 12)
            ctx.closePath()
            ctx.stroke()
            dot(8, 3, 2.5)
            dot(13, 12, 2.5)
            dot(3, 12, 2.5)
            return
          }

          ctx.beginPath()
          ctx.arc(8, 8, 6, 0, 2 * Math.PI)
          ctx.stroke()
          if (glyph.mode === "nodeOnly")
            dot(8, 8, 3)
        }
      }
    }
  }

  Loader {
    id: panelLoader
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: root.assignPanel()
  }
}
