import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// The bar popup. The widget owns the open state; this only shows it.
Item {
  id: root

  property var bar
  property var settings
  property var anchorItem
  property var service
  property var hostWidget

  readonly property bool opened: hostWidget ? hostWidget.opened : false
  property int current: 0

  readonly property string statusText: Logic.tooltipText(
    service ? service.nodeUp === true : false,
    service ? service.explorerUp === true : false,
    service ? service.hosted : -1)
  readonly property string messageText: service ? service.message : ""
  readonly property var rows: buildRows(service)

  function open() {
    if (hostWidget)
      hostWidget.open()
  }

  function close() {
    if (hostWidget)
      hostWidget.close()
  }

  function buildRows(s) {
    var list = [
      {
        key: "start",
        label: "Start explorer",
        detail: s && s.unitInstalled === false ? "Not set up. Run " + Logic.SETUP_PATH + " once" : "",
        actionable: true
      },
      { key: "stop", label: "Stop explorer", detail: "", actionable: true },
      { key: "openUi", label: "Open UI", detail: "", actionable: true },
      {
        key: "openKept",
        label: "Open kept files",
        detail: s && !s.keptExists
          ? "The kept folder " + s.keptDir + " does not exist yet. The explorer creates it on the first Keep."
          : "",
        actionable: true
      }
    ]

    if (s && s.nodeUnitAvailable) {
      list.push({ key: "startNode", label: "Start Freenet node", detail: "", actionable: true })
    } else if (s && s.nodeBinaryPresent) {
      list.push({
        key: "nodeInfo",
        label: "",
        detail: "The freenet binary is present but the user service is not. See https://freenet.org/quickstart/ and https://freenet.org/uninstall/",
        actionable: false
      })
    } else {
      list.push({
        key: "nodeInfo",
        label: "",
        detail: "No Freenet node found. Install it as described at https://freenet.org/quickstart/ :\ncurl -fsSL https://freenet.org/install.sh | sh\nThe AUR freenet package is the old Java client and must not be used.",
        actionable: false
      })
    }
    return list
  }

  function move(step) {
    var next = root.current + step
    while (next >= 0 && next < root.rows.length) {
      if (root.rows[next].actionable) {
        root.current = next
        return
      }
      next += step
    }
  }

  function activate(index) {
    var row = root.rows[index]
    var s = root.service
    if (!row || !row.actionable || !s)
      return
    if (row.key === "start")
      s.startExplorer()
    else if (row.key === "stop")
      s.stopExplorer()
    else if (row.key === "openUi")
      s.openUi()
    else if (row.key === "openKept")
      s.openKept()
    else if (row.key === "startNode")
      s.startNode()
  }

  onOpenedChanged: {
    if (opened) {
      current = 0
      scroller.contentY = 0
    }
  }

  // The node row can turn into text while highlighted.
  onRowsChanged: {
    if (rows[current] && !rows[current].actionable)
      move(-1)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: Math.min(Style.space(340), Math.max(Style.space(200), keyCatcher.Screen.width - Style.space(48)))
    contentHeight: Math.min(column.implicitHeight, Math.max(Style.space(160), keyCatcher.Screen.height - Style.space(96)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        function reveal(item) {
          var top = item.y + rowColumn.y
          if (top < contentY)
            contentY = top
          else if (top + item.height > contentY + height)
            contentY = top + item.height - height
        }

        Column {
          id: column
          width: scroller.width
          spacing: Style.space(6)

          Text {
            width: parent.width
            text: root.statusText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.popups.text
            font.family: Style.font.family
            font.bold: true
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: root.messageText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Color.popups.text
            font.family: Style.font.family
          }

          Column {
            id: rowColumn
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.rows

              delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool highlighted: modelData.actionable && root.current === index

                width: rowColumn.width
                height: rowText.implicitHeight + Style.space(12)
                color: highlighted ? Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.12) : "transparent"
                border.width: highlighted ? 1 : 0
                border.color: Color.popups.border

                onHighlightedChanged: if (highlighted) scroller.reveal(row)

                Column {
                  id: rowText
                  x: Style.space(8)
                  width: parent.width - Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    visible: text !== ""
                    text: row.modelData.label
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.popups.text
                    font.family: Style.font.family
                  }

                  Text {
                    width: parent.width
                    visible: text !== ""
                    text: row.modelData.detail
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.popups.text
                    opacity: 0.7
                    font.family: Style.font.family
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: row.modelData.actionable
                  hoverEnabled: true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onEntered: root.current = row.index
                  onClicked: root.activate(row.index)
                }
              }
            }
          }
        }
      }

      // Scroll cue when the content does not fit.
      Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: scroller.contentHeight - scroller.contentY > scroller.height + 1
        text: "▼"
        textFormat: Text.PlainText
        color: Color.popups.text
        font.family: Style.font.family
      }
    }

    Connections {
      target: keyCatcher
      ignoreUnknownSignals: true

      function onMoveRequested(dx, dy) {
        if (dy !== 0)
          root.move(dy > 0 ? 1 : -1)
      }
      function onActivateRequested() {
        root.activate(root.current)
      }
      function onCloseRequested() {
        root.close()
      }
      function onTabRequested(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.hostWidget, direction)
      }
    }
  }
}
