import QtQuick
import QtQuick.Effects
import QtQuick.Window
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// Live peer readout plus the explorer actions. Numbers, peers, and apps come
// from this machine's own dashboard. Every open stays on 127.0.0.1.
Item {
  id: root

  property var bar
  property var settings
  property var anchorItem
  property var service
  property var hostWidget

  readonly property bool opened: hostWidget ? hostWidget.opened : false
  property int current: 0
  property bool filtering: false
  property string query: ""
  property bool peersOpen: false
  property bool hostedOpen: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Util.alpha(foreground, 0.14)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var dash: service && service.dashboard ? service.dashboard : ({})
  readonly property bool nodeUp: service ? service.nodeUp === true : false
  readonly property bool explorerUp: service ? service.explorerUp === true : false
  readonly property string messageText: service ? service.message : ""

  readonly property string heroMeta: {
    if (!nodeUp)
      return "Node is not accepting connections"
    var count = service ? service.peerCount : -1
    if (count < 0)
      return "Node is up"
    var parts = [count === 1 ? "1 peer" : (count + " peers")]
    if (dash.uptime)
      parts.push(dash.uptime)
    if (dash.version)
      parts.push("v" + dash.version)
    return parts.join("   ")
  }

  readonly property string heroDetail: {
    if (!explorerUp)
      return "explorer stopped"
    var hosted = service ? service.hosted : -1
    var kept = service ? service.kept : -1
    if (hosted < 0)
      return "explorer running"
    var bit = hosted + " hosted"
    if (kept >= 0)
      bit += " · " + kept + " kept"
    return bit
  }

  function stick(text) {
    return String(text).replace(/ /g, "\u00A0")
  }

  readonly property string factText: {
    var parts = []
    if (dash.peerId)
      parts.push(stick(dash.peerId))
    if (dash.nat)
      parts.push(stick("NAT " + dash.nat))
    if (dash.location)
      parts.push(stick("loc " + dash.location))
    if (dash.external)
      parts.push(stick(dash.external))
    if (dash.uploaded)
      parts.push(stick("sent " + dash.uploaded))
    if (dash.downloaded)
      parts.push(stick("got " + dash.downloaded))
    if (dash.attempts)
      parts.push(stick(dash.attempts + " attempts"))
    return parts.join("   ")
  }

  readonly property var metrics: {
    var list = []
    if (dash.ringPeers)
      list.push({ value: dash.ringPeers, caption: "Peers" })
    else if (service && service.peerCount >= 0)
      list.push({ value: String(service.peerCount), caption: "Peers" })
    if (dash.hosted)
      list.push({ value: dash.hosted, caption: "Hosted" })
    if (dash.upload)
      list.push({ value: dash.upload, caption: "Up" })
    if (dash.download)
      list.push({ value: dash.download, caption: "Down" })
    return list
  }

  readonly property var rows: buildRows(service, query, nodeUp, explorerUp, dash, peersOpen, hostedOpen, service ? service.busy : false, service ? service.action : "", service ? service.aegisPath : "")
  readonly property var leadRows: { var parts = splitRows(rows); return parts.lead }
  readonly property var appRows: { var parts = splitRows(rows); return parts.apps }
  readonly property var tailRows: { var parts = splitRows(rows); return parts.tail }

  readonly property string legendText: filtering
    ? "type to filter    enter open    esc clear"
    : "j/k move    enter open    c copy    / filter\nr refresh    e explorer    u node"

  function open() {
    if (hostWidget)
      hostWidget.open()
  }

  function close() {
    if (hostWidget)
      hostWidget.close()
  }

  function buildRows(s, q, up, exploring, board, peersOpen, hostedOpen, busy, action, aegisPath) {
    var list = []
    var queryText = String(q || "").trim().toLowerCase()
    var info = board || {}

    function push(section, title, row) {
      if (queryText !== "" && section !== "actions") {
        var hay = (row.label + " " + (row.detail || "") + " " + (row.copy || "")).toLowerCase()
        if (hay.indexOf(queryText) < 0)
          return
      }
      var previous = list.length > 0 ? list[list.length - 1] : null
      row.header = !previous || previous.section !== section ? title : ""
      row.section = section
      list.push(row)
    }

    if (!up) {
      if (s && s.nodeUnitAvailable) {
        push("node", "Node", {
          kind: "startNode",
          label: "Start Freenet node",
          detail: "",
          actionable: true
        })
      } else if (s && s.nodeBinaryPresent) {
        push("node", "Node", {
          kind: "note",
          label: "",
          detail: "The freenet binary is present but the user service is not. See https://freenet.org/quickstart/ and https://freenet.org/uninstall/",
          actionable: false
        })
      } else {
        push("node", "Node", {
          kind: "note",
          label: "",
          detail: "No Freenet node found. Install it as described at https://freenet.org/quickstart/ :\ncurl -fsSL https://freenet.org/install.sh | sh\nThe AUR freenet package is the old Java client and must not be used.",
          actionable: false
        })
      }
    } else if (info.peerCount === 0) {
      push("node", "Node", {
        kind: "openPeer",
        label: "Not connected yet",
        detail: "The node is running and has no peers. Enter opens the peer UI.",
        actionable: true
      })
    }

    if (up && info.peerId && Logic.copyable(info.peerId)) {
      push("self", "This node", {
        kind: "self",
        label: info.peerId,
        detail: "Local peer",
        copy: info.peerId,
        actionable: true
      })
    }

    var places = info.places || []
    var sawAegis = false
    if (up && info.peerCount > 0) {
      // Explorer and the peer UI are this machine's own pages, so they lead
      // the grid and sit on one row. They are not contract ids.
      push("apps", "Apps", {
        kind: "explorerApp",
        label: "Freenet Explorer",
        detail: "Local index",
        copy: Logic.UI_URL,
        actionable: true
      })
      push("apps", "Apps", {
        kind: "peerApp",
        label: "Peer UI",
        detail: "Dashboard",
        copy: Logic.PEER_UI_URL,
        actionable: true
      })
      for (var i = 0; i < places.length && i < 12; i++) {
        var place = places[i]
        if (!place || !Logic.placeUrl(place.path))
          continue
        if (Logic.appMark(place.label) === "aegis")
          sawAegis = true
        push("apps", "Apps", {
          kind: "place",
          label: Logic.oneLine(place.label),
          detail: place.detail || "",
          path: place.path,
          copy: Logic.placeUrl(place.path),
          actionable: true
        })
      }
      var aegisUrl = Logic.aegisLaunchUrl(aegisPath)
      if (!sawAegis && aegisUrl) {
        push("apps", "Apps", {
          kind: "aegis",
          label: "Aegis",
          detail: "Password manager",
          copy: aegisUrl,
          actionable: true
        })
      }
    }

    var peerRows = []
    var sourcePeers = info.peers || []
    if (up) {
      for (var p = 0; p < sourcePeers.length; p++) {
        var peer = sourcePeers[p]
        if (peer && Logic.peerPageUrl(peer.addr))
          peerRows.push(peer)
      }
    }
    if (peerRows.length > 0) {
      var peerTotal = info.peerCount >= 0 ? info.peerCount : peerRows.length
      if (queryText === "") {
        push("peers", "Peers", {
          kind: "togglePeers",
          label: peerTotal === 1 ? "1 peer" : (peerTotal + " peers"),
          detail: peersOpen ? "Enter to hide" : "Enter to show",
          actionable: true
        })
      }
      if (peersOpen || queryText !== "") {
        for (var pr = 0; pr < peerRows.length; pr++) {
          var shown = peerRows[pr]
          var bits = []
          if (shown.loc)
            bits.push("loc " + shown.loc)
          if (shown.sent)
            bits.push("up " + shown.sent)
          if (shown.recv)
            bits.push("down " + shown.recv)
          if (shown.age)
            bits.push(shown.age)
          push("peers", "Peers", {
            kind: "peer",
            label: shown.addr,
            detail: bits.join("   "),
            copy: shown.addr,
            actionable: true
          })
        }
        if (queryText === "" && peerTotal > peerRows.length) {
          push("peers", "Peers", {
            kind: "note",
            label: "",
            detail: "Showing " + peerRows.length + " of " + peerTotal + ". Open peer UI for the rest.",
            actionable: false
          })
        }
      }
    } else if (up && info.peerCount > 0 && queryText === "") {
      push("peers", "Peers", {
        kind: "note",
        label: "",
        detail: "Peer rows were not readable. Open peer UI for the full list.",
        actionable: false
      })
    }

    var contractRows = []
    var sourceContracts = info.contracts || []
    if (up) {
      for (var c = 0; c < sourceContracts.length; c++) {
        var contract = sourceContracts[c]
        if (contract && Logic.contractPageUrl(contract.key))
          contractRows.push(contract)
      }
    }
    if (contractRows.length > 0) {
      var hostedTotal = Logic.listedCount(info.hosted, contractRows.length)
      if (queryText === "") {
        push("contracts", "Hosted", {
          kind: "toggleHosted",
          label: hostedTotal === 1 ? "1 contract" : (hostedTotal + " contracts"),
          detail: hostedOpen ? "Enter to hide" : "Enter to show",
          actionable: true
        })
      }
      if (hostedOpen || queryText !== "") {
        for (var cr = 0; cr < contractRows.length; cr++) {
          var item = contractRows[cr]
          var about = []
          if (item.size)
            about.push(item.size)
          if (item.state)
            about.push(item.state)
          push("contracts", "Hosted", {
            kind: "contract",
            label: item.short || item.key,
            detail: about.join("   "),
            copy: item.key,
            actionable: true
          })
        }
        if (queryText === "" && hostedTotal > contractRows.length) {
          push("contracts", "Hosted", {
            kind: "note",
            label: "",
            detail: "Showing " + contractRows.length + " of " + hostedTotal + ". Open peer UI for the rest.",
            actionable: false
          })
        }
      }
    }

    var explored = s ? s.explored : -1
    var explorerPending = busy === true && (action === "start" || action === "stop")
    push("actions", "Explorer", {
      kind: "explorerSwitch",
      label: "Explorer",
      detail: s && s.unitInstalled === false
        ? "Not set up. Run " + Logic.SETUP_PATH + " once"
        : (exploring ? "Running" : "Stopped"),
      checked: explorerPending ? action === "start" : exploring === true,
      actionable: true
    })
    push("actions", "Explorer", {
      kind: "openUi",
      label: "Open explorer",
      detail: explored >= 0 ? (explored + " items in the local index") : "",
      actionable: true
    })
    push("actions", "Explorer", {
      kind: "openPeer",
      label: "Open peer UI",
      detail: up ? "Local dashboard" : "The node is not accepting connections",
      actionable: true
    })
    push("actions", "Explorer", {
      kind: "openKept",
      label: "Open kept files",
      detail: s && !s.keptExists
        ? "The kept folder " + s.keptDir + " does not exist yet. The explorer creates it on the first Keep."
        : (s && s.kept >= 0 ? (s.kept + " kept") : ""),
      actionable: true
    })

    if (queryText !== "") {
      var onlyActions = true
      for (var n = 0; n < list.length; n++) {
        if (list[n].section !== "actions")
          onlyActions = false
      }
      if (onlyActions) {
        list.push({
          kind: "note",
          label: "",
          detail: "Nothing matches",
          actionable: false,
          header: "",
          section: "none"
        })
      }
    }
    var idx
    for (idx = 0; idx < list.length; idx++)
      list[idx].index = idx
    return list
  }

  // Apps are one run of tile rows. Everything above and below stays a list.
  function splitRows(list) {
    var lead = []
    var apps = []
    var tail = []
    var phase = 0
    var rowsIn = list || []
    var i
    for (i = 0; i < rowsIn.length; i++) {
      var row = rowsIn[i]
      var appRow = row.kind === "place" || row.kind === "aegis" || row.kind === "explorerApp" || row.kind === "peerApp"
      if (phase === 0 && appRow)
        phase = 1
      else if (phase === 1 && !appRow)
        phase = 2
      if (phase === 0)
        lead.push(row)
      else if (phase === 1)
        apps.push(row)
      else
        tail.push(row)
    }
    return { lead: lead, apps: apps, tail: tail }
  }

  function paintMark(canvas, mark) {
    var ctx = canvas.getContext("2d")
    if (!ctx)
      return
    var w = canvas.width
    var h = canvas.height
    ctx.reset()
    ctx.clearRect(0, 0, w, h)
    ctx.strokeStyle = root.foreground
    ctx.fillStyle = root.foreground
    ctx.lineWidth = Math.max(1.25, w / 14)
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    var cx = w / 2
    var cy = h / 2
    var r = w * 0.32
    if (mark === "atlas") {
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(cx, cy)
      ctx.lineTo(cx + r * 0.78, cy - r * 0.58)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(cx, cy, Math.max(1.5, w * 0.07), 0, Math.PI * 2)
      ctx.fill()
    } else if (mark === "river") {
      ctx.beginPath()
      ctx.arc(cx - r * 0.38, cy + r * 0.12, r * 0.62, 0, Math.PI * 2)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(cx + r * 0.42, cy - r * 0.32, r * 0.42, 0, Math.PI * 2)
      ctx.stroke()
    } else if (mark === "mail") {
      var x = cx - r
      var y = cy - r * 0.72
      var boxW = r * 2
      var boxH = r * 1.45
      ctx.strokeRect(x, y, boxW, boxH)
      ctx.beginPath()
      ctx.moveTo(x, y)
      ctx.lineTo(cx, cy + r * 0.18)
      ctx.lineTo(x + boxW, y)
      ctx.stroke()
    } else if (mark === "delta") {
      ctx.beginPath()
      ctx.moveTo(cx, cy - r)
      ctx.lineTo(cx + r * 0.95, cy + r * 0.78)
      ctx.lineTo(cx - r * 0.95, cy + r * 0.78)
      ctx.closePath()
      ctx.stroke()
    } else if (mark === "ghost") {
      ctx.beginPath()
      ctx.arc(cx - r * 0.28, cy - r * 0.12, r * 0.42, 0, Math.PI * 2)
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(cx + r * 0.02, cy + r * 0.02)
      ctx.lineTo(cx + r, cy + r * 0.02)
      ctx.moveTo(cx + r * 0.62, cy + r * 0.02)
      ctx.lineTo(cx + r * 0.62, cy + r * 0.38)
      ctx.moveTo(cx + r, cy + r * 0.02)
      ctx.lineTo(cx + r, cy + r * 0.28)
      ctx.stroke()
    } else if (mark === "aegis") {
      var body = r * 0.72
      ctx.strokeRect(cx - body, cy - body * 0.15, body * 2, body * 1.35)
      ctx.beginPath()
      ctx.arc(cx, cy - body * 0.15, body * 0.62, Math.PI, 0)
      ctx.stroke()
    } else if (mark === "freenet") {
      var dots = [cx - r * 0.72, cx, cx + r * 0.72]
      var d
      for (d = 0; d < dots.length; d++) {
        ctx.beginPath()
        ctx.arc(dots[d], cy, Math.max(1.5, w * 0.075), 0, Math.PI * 2)
        ctx.fill()
      }
    } else if (mark === "peer") {
      var px = cx - r * 0.95
      var py = cy - r * 0.82
      var pw = r * 1.9
      var ph = r * 1.65
      ctx.strokeRect(px, py, pw, ph)
      ctx.beginPath()
      ctx.moveTo(px, py + ph * 0.28)
      ctx.lineTo(px + pw, py + ph * 0.28)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(px + pw * 0.16, py + ph * 0.14, Math.max(1.2, w * 0.04), 0, Math.PI * 2)
      ctx.fill()
    }
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
    if (row.kind === "explorerSwitch") {
      if (s.explorerUp)
        s.stopExplorer()
      else
        s.startExplorer()
    } else if (row.kind === "openUi")
      s.openUi()
    else if (row.kind === "openPeer")
      s.openPeer()
    else if (row.kind === "openKept")
      s.openKept()
    else if (row.kind === "togglePeers")
      root.peersOpen = !root.peersOpen
    else if (row.kind === "toggleHosted")
      root.hostedOpen = !root.hostedOpen
    else if (row.kind === "self")
      s.openPeer()
    else if (row.kind === "place")
      s.openPlace(row.path)
    else if (row.kind === "aegis")
      s.openAegis()
    else if (row.kind === "explorerApp")
      s.openUi()
    else if (row.kind === "peerApp")
      s.openPeer()
    else if (row.kind === "peer")
      s.openPeerAddr(row.copy)
    else if (row.kind === "contract")
      s.openContract(row.copy)
    else if (row.kind === "startNode")
      s.startNode()
  }

  function copyCurrent() {
    var row = root.rows[root.current]
    var s = root.service
    if (!s)
      return
    if (!row || !row.copy) {
      s.message = "Nothing to copy on this row"
      return
    }
    s.copyText(row.copy)
  }

  function startFilter() {
    root.filtering = true
    Qt.callLater(function() { filterField.forceActiveFocus() })
  }

  function stopFilter() {
    root.query = ""
    root.filtering = false
    keyCatcher.forceActiveFocus()
  }

  onOpenedChanged: {
    if (opened) {
      current = 0
      query = ""
      filtering = false
      peersOpen = false
      hostedOpen = false
      scroller.contentY = 0
      Qt.callLater(function() {
        if (root.rows[root.current] && !root.rows[root.current].actionable)
          root.move(1)
      })
    }
  }

  onRowsChanged: {
    if (filtering) {
      // A dashboard refresh rebuilds this list about every 10 seconds. Keep
      // the highlight when that row still matches; jump only when it does not.
      var q = String(query || "").trim().toLowerCase()
      var held = rows[current]
      var hay = held ? ((held.label || "") + " " + (held.detail || "") + " " + (held.copy || "")).toLowerCase() : ""
      var still = held && held.actionable && held.section !== "actions" && q !== "" && hay.indexOf(q) >= 0
      if (!still) {
        var match = -1
        var i
        for (i = 0; i < rows.length; i++) {
          if (rows[i].actionable && rows[i].section !== "actions") {
            match = i
            break
          }
        }
        current = match >= 0 ? match : 0
      }
    } else if (current >= rows.length) {
      current = 0
    }
    if (rows[current] && !rows[current].actionable)
      move(1)
  }

  Component {
    id: listRow

    Column {
      id: row
      required property var modelData
      required property int index
      readonly property bool highlighted: modelData.actionable && root.current === modelData.index
      readonly property bool switchRow: modelData.kind === "explorerSwitch"
      width: rowColumn.width
      spacing: Style.space(4)

      onHighlightedChanged: if (highlighted) scroller.reveal(row)

      Item {
        visible: row.modelData.header !== "" && row.modelData.index > 0
        width: 1
        height: Style.space(8)
      }

      PanelSeparator {
        visible: row.modelData.header !== "" && row.modelData.index > 0
        foreground: root.foreground
      }

      PanelSectionHeader {
        visible: row.modelData.header !== ""
        text: row.modelData.header
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item {
        visible: row.switchRow
        width: parent.width
        height: visible ? option.implicitHeight : 0

        Toggle {
          id: option
          width: parent.width
          label: row.modelData.label
          description: row.modelData.detail || ""
          checked: row.modelData.checked === true
          hasCursor: row.highlighted
          foreground: root.foreground
          fontFamily: root.fontFamily
          titleSize: Style.font.body
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: root.current = row.modelData.index
          onClicked: root.activate(row.modelData.index)
        }
      }

      CursorSurface {
        id: surface
        visible: !row.switchRow
        width: parent.width
        implicitHeight: Math.max(Style.space(28), rowText.implicitHeight + Style.space(10))
        hasCursor: row.highlighted
        foreground: root.foreground

        Column {
          id: rowText
          x: Style.space(8)
          width: parent.width - Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            visible: text !== ""
            text: row.modelData.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: row.modelData.detail
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: row.modelData.actionable
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          // onEntered also fires when a row scrolls under a still
          // cursor, which yanks the keyboard highlight. Movement only.
          onPositionChanged: root.current = row.modelData.index
          onClicked: root.activate(row.modelData.index)
        }
      }
    }
  }

  Component {
    id: appTile

    CursorSurface {
      id: tile
      required property var modelData
      required property int index
      readonly property bool highlighted: modelData.actionable && root.current === modelData.index
      readonly property string markName: modelData.kind === "explorerApp" ? "explorer"
        : (modelData.kind === "peerApp" ? "peer" : Logic.appMark(modelData.label))
      readonly property string localSvg: markName === "aegis" ? "aegis.svg"
        : (markName === "explorer" ? "icon.svg" : "")
      readonly property string letter: Logic.monogram(modelData.label)
      readonly property int tileWidth: {
        var gap = appFlow.spacing
        var full = appFlow.width
        if (full <= gap)
          return Math.max(1, full)
        return Math.floor((full - gap) / 2)
      }
      width: tileWidth
      implicitHeight: tileBody.implicitHeight + Style.space(16)
      height: implicitHeight
      hasCursor: highlighted
      bordered: true
      foreground: root.foreground

      onHighlightedChanged: if (highlighted) scroller.reveal(tile)

      Column {
        id: tileBody
        x: Style.space(8)
        y: Style.space(8)
        width: parent.width - Style.space(16)
        spacing: Style.space(4)

        Item {
          id: well
          width: Style.space(40)
          height: Style.space(40)
          // Column children cannot use anchors, so the well is centered by x.
          x: Math.max(0, (parent.width - width) / 2)

          Rectangle {
            anchors.fill: parent
            radius: Style.space(8)
            color: root.track
          }

          Image {
            id: localMark
            anchors.fill: parent
            anchors.margins: Style.space(6)
            source: tile.localSvg !== "" ? Qt.resolvedUrl(tile.localSvg) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            sourceSize.width: 64
            sourceSize.height: 64
            visible: false
          }

          MultiEffect {
            anchors.fill: localMark
            source: localMark
            visible: tile.localSvg !== "" && localMark.status === Image.Ready
            colorization: 1
            colorizationColor: root.foreground
          }

          Canvas {
            id: markCanvas
            anchors.fill: parent
            anchors.margins: Style.space(8)
            antialiasing: true
            visible: localMark.status !== Image.Ready && tile.markName !== "" && tile.markName !== "explorer"
            property color ink: root.foreground
            property string shownMark: tile.markName
            onPaint: root.paintMark(markCanvas, shownMark)
            onInkChanged: requestPaint()
            onShownMarkChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: if (visible) requestPaint()
          }

          Text {
            anchors.centerIn: parent
            visible: localMark.status !== Image.Ready && tile.markName === ""
            text: tile.letter
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        Text {
          width: parent.width
          height: Math.ceil(font.pixelSize * 2.5)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: tile.modelData.label
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          height: Math.ceil(font.pixelSize * 1.35)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: tile.modelData.detail
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: tile.modelData.actionable
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPositionChanged: root.current = tile.modelData.index
        onClicked: root.activate(tile.modelData.index)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(Style.space(520), Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      focus: !root.filtering

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          root.move(dy > 0 ? 1 : -1)
      }
      onActivateRequested: root.activate(root.current)
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.hostWidget, direction)
      }
      onTextKey: function(text) {
        if (text === "/" || text === "?")
          root.startFilter()
        else if (text === "c" || text === "C")
          root.copyCurrent()
        else if (text === "r" || text === "R") {
          if (root.service)
            root.service.requestRefresh()
        } else if (text === "e" || text === "E") {
          if (root.service)
            root.service.openUi()
        } else if (text === "u" || text === "U") {
          if (root.service)
            root.service.openPeer()
        }
      }

      Column {
        id: headerColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

          Item {
            id: heroBlock
            width: parent.width
            implicitHeight: hero.implicitHeight
            // trailingControl is instantiated inside PanelHero, whose own id is
            // root. Reach this panel through heroBlock.
            readonly property string hostDetail: root.heroDetail
            function openHost() {
              if (root.service)
                root.service.openPeer()
            }

            PanelHero {
              id: hero
              width: parent.width
              title: "Freenet"
              meta: root.heroMeta
              detail: ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.nodeUp ? 1 : 0.55
              iconComponent: Component {
                Rectangle {
                  width: Style.space(12)
                  height: Style.space(12)
                  radius: width / 2
                  color: !root.nodeUp ? root.urgent
                    : (root.service && root.service.peerCount > 0 ? root.foreground : root.dim)
                }
              }

              trailingControl: Component {
                BorderSurface {
                  id: hostPill
                  readonly property bool hot: hostArea.containsMouse
                  visible: heroBlock.hostDetail !== ""
                  implicitWidth: hostPillText.implicitWidth + Style.space(10)
                  implicitHeight: hostPillText.implicitHeight + Style.space(4)
                  color: "transparent"
                  borderSpec: Border.controlSpec(hot ? "hover-cursor" : "normal", hero.foreground, Color.accent)
                  radius: Style.cornerRadius

                  Text {
                    id: hostPillText
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: heroBlock.hostDetail
                    color: Qt.darker(hero.foreground, 1.4)
                    font.family: hero.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  MouseArea {
                    id: hostArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: heroBlock.openHost()
                  }
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: root.messageText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            id: metricRow
            width: parent.width
            spacing: Style.space(10)
            visible: root.metrics.length > 0

            Repeater {
              model: root.metrics

              delegate: Column {
                required property var modelData
                width: {
                  var n = Math.max(1, root.metrics.length)
                  return Math.max(Style.space(72), (metricRow.width - metricRow.spacing * (n - 1)) / n)
                }
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: modelData.value
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }

                Text {
                  width: parent.width
                  text: modelData.caption
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.nodeUp && root.dash.statePct >= 0

            Rectangle {
              width: parent.width
              height: Style.space(4)
              radius: height / 2
              color: root.track

              Rectangle {
                width: Math.max(height, parent.width * (root.dash.statePct / 100))
                height: parent.height
                radius: parent.radius
                color: root.dash.statePct >= 90 ? root.urgent : root.foreground
              }
            }

            Text {
              width: parent.width
              text: root.dash.state || ""
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            visible: text !== ""
            text: root.factText
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: filterField
            visible: root.filtering
            height: visible ? implicitHeight : 0
            width: parent.width
            placeholderText: "Filter peers, apps, contracts"
            text: root.query
            foreground: root.foreground
            font.family: root.fontFamily
            verticalPadding: Style.space(4)
            onTextChanged: root.query = text
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.stopFilter()
                event.accepted = true
              } else if (event.key === Qt.Key_Up) {
                root.move(-1)
                event.accepted = true
              } else if (event.key === Qt.Key_Down) {
                root.move(1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.activate(root.current)
                event.accepted = true
              }
            }
          }
      }

      Flickable {
        id: scroller
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerColumn.bottom
        anchors.bottom: legend.top
        anchors.topMargin: Style.space(8)
        contentWidth: width
        contentHeight: rowColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        function reveal(item) {
          var top = 0
          var node = item
          while (node && node !== rowColumn) {
            top += node.y
            node = node.parent
          }
          if (!node)
            return
          // Keep the Apps heading in view when the highlight enters the grid.
          if (item.parent === appFlow && item.y < Style.space(8))
            top = appBlock.y
          if (top < contentY)
            contentY = top
          else if (top + item.height > contentY + height)
            contentY = top + item.height - height
        }

        Column {
            id: rowColumn
            width: parent.width
            spacing: Style.space(2)

            Repeater {
              model: root.leadRows
              delegate: listRow
            }

            Column {
              id: appBlock
              width: parent.width
              visible: root.appRows.length > 0
              spacing: Style.space(4)

              Item {
                visible: root.leadRows.length > 0
                width: 1
                height: Style.space(8)
              }

              PanelSeparator {
                visible: root.leadRows.length > 0
                foreground: root.foreground
              }

              PanelSectionHeader {
                readonly property string sectionTitle: {
                  var apps = root.appRows
                  return apps.length > 0 ? (apps[0].header || "") : ""
                }
                visible: sectionTitle !== ""
                text: sectionTitle
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Flow {
                id: appFlow
                width: parent.width
                spacing: Style.space(8)

                Repeater {
                  model: root.appRows
                  delegate: appTile
                }
              }
            }

            Repeater {
              model: root.tailRows
              delegate: listRow
            }
          }
      }

      Text {
        id: legend
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: root.legendText
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
