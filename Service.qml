import QtQuick
import Quickshell
import Quickshell.Io
import "Logic.js" as Logic

// Headless service: polls the node and explorer, owns IPC and the launcher.
// The shell parents this object to null. It is an Item, not a QtObject,
// because IpcHandler, Timer, and Process are child objects and QtObject has
// no default property to hold them. Nothing parents it into a window.
Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string pluginId: "io.mcmurray.freenet-explorer"

  property bool nodeUp: false
  property bool explorerUp: false
  property int hosted: -1                 // -1 = unknown
  property int kept: -1
  property int explored: -1
  property int peerCount: -1              // -1 unknown, 0 up but not connected
  property var places: []
  property var dashboard: ({})
  // path -> validated icon URL, or "" when this contract publishes none.
  property var iconFor: ({})
  property string iconJob: ""
  property int panelsOpen: 0
  property var unitInstalled: null        // null unknown, true/false after first check
  property bool nodeUnitAvailable: false
  property bool nodeBinaryPresent: false
  readonly property string homeDir: String(Quickshell.env("HOME") || "")
  readonly property string aegisPathFile: homeDir + "/.config/freenet/aegis-web.path"
  property string aegisPath: ""
  readonly property string keptDir: String(Quickshell.env("FREENET_EXPLORER_KEPT") || "")
    || (homeDir + "/.local/share/freenet-explorer/kept")
  property bool keptExists: false
  property string message: ""             // last action result or error, one line
  property bool busy: false               // a start/stop/startNode process is running

  readonly property string desktopPath: homeDir + "/.local/share/applications/io.mcmurray.freenet-explorer.desktop"
  readonly property string shellConfigPath: homeDir + "/.config/omarchy/shell.json"
  readonly property string iconPath: decodeURIComponent(String(Qt.resolvedUrl("icon.svg")).replace(/^file:\/\//, ""))
  readonly property string setupNeeded: "explorer unit not installed; run " + Logic.SETUP_PATH + " once"

  // The action in flight: "start", "stop", or "startNode".
  property string action: ""
  property string actionError: ""

  // Fixed scripts. Paths arrive only as positional arguments.
  readonly property string desktopScript: `
set -eu
target=$1
icon=$2
dir=$(dirname -- "$target")
mkdir -p -- "$dir"
if [ -L "$target" ]; then
  echo "refusing to replace a symlink: $target" >&2
  exit 1
fi
if [ -e "$target" ]; then
  if [ ! -f "$target" ] || ! grep -qxF 'X-Freenet-Explorer-Managed=true' -- "$target"; then
    echo "refusing to replace an unmanaged file: $target" >&2
    exit 1
  fi
fi
tmp=$(mktemp "$dir/.freenet-explorer.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp" <<EOF
[Desktop Entry]
Type=Application
Name=Freenet
Comment=Local entry point for this machine's Freenet peer, its apps, and Freenet Explorer
Exec=omarchy-shell io.mcmurray.freenet-explorer open
Icon=$icon
Terminal=false
Categories=Network;
Keywords=freenet;explorer;aegis;
X-Freenet-Explorer-Managed=true
EOF
chmod 0644 "$tmp"
mv -f -- "$tmp" "$target"
`

  readonly property string cleanupScript: `
set -eu
target=$1
config=$2
id=$3
if [ -L "$target" ] || [ ! -f "$target" ]; then exit 0; fi
grep -qxF 'X-Freenet-Explorer-Managed=true' -- "$target" || exit 0
command -v jq >/dev/null 2>&1 || exit 0
if [ -e "$config" ] || [ -L "$config" ]; then
  jq -e --arg id "$id" '[(.bar.layout?, .plugins?) | .. | strings] | index($id) == null' "$config" >/dev/null 2>&1 || exit 0
fi
rm -f -- "$target"
`

  // A Process that always reports once, including when the program cannot start.
  component Command: Process {
    id: cmd
    property bool pending: false
    signal done(int code)

    function run(argv) {
      cmd.command = argv
      cmd.pending = true
      cmd.running = true
    }
    function finish(code) {
      if (!cmd.pending)
        return
      cmd.pending = false
      cmd.done(code)
    }
    function checkFailedStart() {
      if (!cmd.running)
        cmd.finish(127)
    }

    onExited: (exitCode, exitStatus) => cmd.finish(exitCode)
    onRunningChanged: if (!cmd.running && cmd.pending) Qt.callLater(cmd.checkFailedStart)
  }

  function refreshing() {
    return nodeProbe.pending || explorerProbe.pending || summary.pending || unitCheck.pending
      || nodeUnitFile.pending || nodeUnitCat.pending || nodeBinary.pending || keptCheck.pending
  }

  function refresh(): void {
    if (root.refreshing())
      return
    nodeProbe.run(["timeout", "1", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/7509"])
    explorerProbe.run(["timeout", "1", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8787"])
    unitCheck.run(["systemctl", "--user", "cat", "freenet-explorer.service"])
    nodeUnitFile.run(["test", "-f", root.homeDir + "/.config/systemd/user/freenet.service"])
    nodeBinary.run(["bash", "-c", "test -x \"$HOME/.local/bin/freenet\" || test -x /usr/local/bin/freenet || test -x /usr/bin/freenet"])
    keptCheck.run(["test", "-d", root.keptDir])
  }

  function fail(reason) {
    return Logic.oneLine("error: " + reason)
  }

  function runAction(name, verb, unit) {
    root.action = name
    root.actionError = ""
    root.message = ""
    root.busy = true
    actionProcess.run(["systemctl", "--user", verb, unit])
    return "ok"
  }

  function explorerAction(verb) {
    if (root.busy)
      return root.fail("busy")
    if (root.unitInstalled === false) {
      root.message = root.setupNeeded
      return root.fail(root.setupNeeded)
    }
    return root.runAction(verb, verb, "freenet-explorer.service")
  }

  function startExplorer(): string {
    return root.explorerAction("start")
  }

  function stopExplorer(): string {
    return root.explorerAction("stop")
  }

  function openUi(): string {
    Quickshell.execDetached(["omarchy-launch-webapp", "http://127.0.0.1:8787/"])
    return "ok"
  }

  function openPeer(): string {
    Quickshell.execDetached(["omarchy-launch-webapp", Logic.PEER_UI_URL])
    return "ok"
  }

  // path is a dashboard contract path. placeUrl rejects anything else.
  function openPlace(path): string {
    var url = Logic.placeUrl(path)
    if (!url)
      return root.fail("refusing place link")
    Quickshell.execDetached(["omarchy-launch-webapp", url])
    return "ok"
  }

  // Local web container only. aegisLaunchUrl rejects every other string.
  function openAegis(): string {
    var url = Logic.aegisLaunchUrl(root.aegisPath)
    if (!url)
      return root.fail("refusing link")
    Quickshell.execDetached(["omarchy-launch-webapp", url])
    return "ok"
  }

  function loadAegisPath() {
    if (!root.homeDir || aegisPathRead.pending)
      return
    aegisPathRead.run(["head", "-c", "512", "--", root.aegisPathFile])
  }

  function panelOpened() {
    root.loadAegisPath()
    root.panelsOpen += 1
    if (root.refreshing()) {
      if (root.nodeUp)
        root.fetchDashboard()
    } else {
      root.refresh()
    }
    root.considerIcons()
  }

  function panelClosed() {
    root.panelsOpen = Math.max(0, root.panelsOpen - 1)
  }

  function fetchDashboard() {
    if (dashboard.pending || !root.nodeUp || root.panelsOpen <= 0)
      return
    dashboard.run(["curl", "-sS", "--max-time", "2", "--max-filesize", "262144", "--fail", "--proto", "=http", Logic.PEER_UI_URL])
  }

  function requestRefresh() {
    if (root.refreshing()) {
      if (root.nodeUp)
        root.fetchDashboard()
    } else {
      root.refresh()
    }
  }

  function openLocal(url) {
    if (typeof url !== "string" || url.indexOf("http://127.0.0.1:7509/") !== 0)
      return root.fail("refusing link")
    if (url.indexOf(" ") >= 0 || url.indexOf("@") >= 0 || url.indexOf("?") >= 0 || url.indexOf("#") >= 0)
      return root.fail("refusing link")
    Quickshell.execDetached(["omarchy-launch-webapp", url])
    return "ok"
  }

  function openPeerAddr(addr) {
    var url = Logic.peerPageUrl(addr)
    if (!url)
      return root.fail("refusing peer")
    return root.openLocal(url)
  }

  function openContract(key) {
    var url = Logic.contractPageUrl(key)
    if (!url)
      return root.fail("refusing contract")
    return root.openLocal(url)
  }

  function copyText(text) {
    var line = Logic.copyable(text)
    if (!line)
      return root.fail("nothing to copy")
    Quickshell.clipboardText = line
    root.message = "Copied " + (line.length > 28 ? line.slice(0, 24) + "..." : line)
    return "ok"
  }

  function openKept(): string {
    if (!root.keptExists) {
      root.message = "Kept folder does not exist yet. The explorer creates it on the first Keep."
      return root.fail("kept folder does not exist yet")
    }
    Quickshell.execDetached(["xdg-open", root.keptDir])
    return "ok"
  }

  function startNode(): string {
    if (!root.nodeUnitAvailable)
      return root.fail("no freenet user service")
    if (root.busy)
      return root.fail("busy")
    return root.runAction("startNode", "start", "freenet.service")
  }

  function statusLine(): string {
    return Logic.statusLine(root.nodeUp, root.explorerUp, root.hosted)
  }

  function failureMessage() {
    var prefix = root.action === "stop" ? "Stop failed: " : "Start failed: "
    return Logic.oneLine(prefix + Logic.oneLine(root.actionError))
  }

  function finishAction(text) {
    root.message = text
    root.busy = false
    root.refresh()
  }

  IpcHandler {
    target: "io.mcmurray.freenet-explorer"
    function start(): string { return root.startExplorer() }
    function stop(): string { return root.stopExplorer() }
    function open(): string { return root.openUi() }
    function status(): string { return root.statusLine() }
  }

  Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Command {
    id: nodeProbe
    onDone: code => {
      root.nodeUp = code === 0
      if (code !== 0) {
        root.peerCount = -1
        root.places = []
        root.dashboard = ({})
        root.iconFor = ({})
        root.iconJob = ""
        return
      }
      if (root.panelsOpen > 0)
        root.fetchDashboard()
    }
  }

  Command {
    id: explorerProbe
    onDone: code => {
      root.explorerUp = code === 0
      if (code === 0)
        summary.run(["curl", "-sS", "--max-time", "2", "--max-filesize", "65536", "--fail", "--proto", "=http", Logic.SUMMARY_URL])
      else {
        root.hosted = -1
        root.kept = -1
        root.explored = -1
      }
    }
  }

  Command {
    id: summary
    stdout: StdioCollector { id: summaryOut }
    onDone: code => {
      if (code !== 0) {
        root.hosted = -1
        root.kept = -1
        root.explored = -1
        return
      }
      var parsed = Logic.parseSummary(summaryOut.text)
      root.hosted = parsed.hosted
      root.kept = parsed.kept
      root.explored = parsed.total
    }
  }

  // Local dashboard only, and only while a popup is open. Places come from
  // its Freenet Links list. A failed read keeps the previous list.
  Command {
    id: dashboard
    stdout: StdioCollector { id: dashOut }
    onDone: code => {
      if (!root.nodeUp || code !== 0)
        return
      var parsed = Logic.parseDashboard(dashOut.text)
      root.peerCount = parsed.peerCount
      root.places = parsed.peerCount > 0 ? parsed.places : []
      root.dashboard = parsed.peerCount >= 0 ? parsed : ({})
      root.considerIcons()
    }
  }

  // One app page at a time, only while a panel is open. The URL is the
  // contract's own sandboxed page, and only a same-contract image link is kept.
  function rememberIcon(path, url) {
    var next = ({})
    var cur = root.iconFor || ({})
    var key
    for (key in cur)
      next[key] = cur[key]
    next[path] = url
    root.iconFor = next
  }

  function considerIcons() {
    if (iconFetch.pending || root.panelsOpen <= 0 || !root.nodeUp)
      return
    var places = root.places || []
    var known = root.iconFor || ({})
    var i
    for (i = 0; i < places.length; i++) {
      var path = places[i] && places[i].path
      var page = Logic.sandboxPageUrl(path)
      if (!page || known[path] !== undefined)
        continue
      root.iconJob = path
      iconFetch.run(["curl", "-sS", "--max-time", "2", "--max-filesize", "65536", "--fail", "--proto", "=http", page])
      return
    }
  }

  Command {
    id: iconFetch
    stdout: StdioCollector { id: iconOut }
    onDone: code => {
      var path = root.iconJob
      root.iconJob = ""
      if (Logic.sandboxPageUrl(path)) {
        var url = ""
        if (code === 0)
          url = Logic.iconUrlFromPage(iconOut.text, path)
        root.rememberIcon(path, url)
      }
      root.considerIcons()
    }
  }

  Command {
    id: unitCheck
    onDone: code => root.unitInstalled = code === 0
  }

  Command {
    id: nodeUnitFile
    onDone: code => {
      if (code === 0)
        root.nodeUnitAvailable = true
      else
        nodeUnitCat.run(["systemctl", "--user", "cat", "freenet.service"])
    }
  }

  Command {
    id: nodeUnitCat
    onDone: code => root.nodeUnitAvailable = code === 0
  }

  Command {
    id: nodeBinary
    onDone: code => root.nodeBinaryPresent = code === 0
  }

  Command {
    id: keptCheck
    onDone: code => root.keptExists = code === 0
  }

  Command {
    id: actionProcess
    stderr: StdioCollector { id: actionErr }
    onDone: code => {
      if (code === 0) {
        if (root.action === "startNode")
          root.finishAction("Freenet node started")
        else
          root.finishAction(root.action === "stop" ? "Explorer stopped" : "Explorer started")
        return
      }
      root.actionError = actionErr.text || ("systemctl exited with " + code)
      if (root.action === "startNode")
        root.finishAction(root.failureMessage())
      else
        actionUnitCheck.run(["systemctl", "--user", "cat", "freenet-explorer.service"])
    }
  }

  // Separate from unitCheck so a poll in flight cannot swallow the re-check.
  Command {
    id: actionUnitCheck
    onDone: code => {
      root.unitInstalled = code === 0
      root.finishAction(code === 0 ? root.failureMessage() : root.setupNeeded)
    }
  }

  Command {
    id: desktopWrite
    stderr: StdioCollector { id: desktopErr }
    onDone: code => {
      if (code !== 0)
        console.warn("freenet-explorer: could not write the launcher: " + Logic.oneLine(desktopErr.text))
    }
  }

  Command {
    id: aegisPathRead
    stdout: StdioCollector { id: aegisPathOut }
    onDone: code => {
      root.aegisPath = code === 0 ? Logic.aegisContractPath(aegisPathOut.text) : ""
    }
  }

  Component.onCompleted: {
    desktopWrite.run(["bash", "-c", root.desktopScript, "freenet-explorer-desktop", root.desktopPath, root.iconPath])
    root.loadAegisPath()
    root.refresh()
  }

  Component.onDestruction: {
    Quickshell.execDetached(["bash", "-c", root.cleanupScript, "freenet-explorer-desktop-cleanup",
      root.desktopPath, root.shellConfigPath, "io.mcmurray.freenet-explorer"])
  }
}
