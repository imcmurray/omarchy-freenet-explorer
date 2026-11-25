#!/usr/bin/env bash
# Static gate for the Freenet Explorer plugin. No node, no display, no network.
# node, shellcheck, qmllint and xmllint checks run only when the tool is present.
# shellcheck disable=SC2016,SC2317,SC2329
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

fail() {
  echo "tests/run.sh: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

manifest=$root/manifest.json
[[ -f $manifest ]] || fail "missing manifest.json"
jq -e . "$manifest" >/dev/null || fail "manifest.json is not valid JSON"

jq -e '.schemaVersion == 1' "$manifest" >/dev/null \
  || fail "schemaVersion must be the number 1"

jq -e '
  .id == "io.mcmurray.freenet-explorer"
  and (.name | type == "string" and length > 0)
  and (.version | type == "string" and length > 0)
  and (.kinds | type == "array" and length > 0)
  and (.entryPoints | type == "object")
' "$manifest" >/dev/null || fail "manifest is missing id, name, version, kinds, or entryPoints"

jq -e '
  if ((.barWidget? | type) == "object" and (.barWidget | has("defaultSection"))) then
    .barWidget.defaultSection as $section
    | ($section | type) == "string"
      and (["left", "centerBegin", "center", "centerEnd", "tray", "right"] | index($section)) != null
  else
    true
  end
' "$manifest" >/dev/null || fail "barWidget.defaultSection is not a known bar section"

while IFS= read -r ep; do
  [[ -n $ep ]] || fail "entry point path is empty"
  [[ $ep != /* ]] || fail "entry point must be relative: $ep"
  [[ $ep != *..* ]] || fail "entry point must not contain ..: $ep"
  [[ -f $root/$ep ]] || fail "entry point file not found: $ep"
done < <(jq -r '.entryPoints | to_entries[] | .value' "$manifest")

# ---------------------------------------------------------------------------
# Feature checks. Each failure is recorded so that one run reports all of them.
# ---------------------------------------------------------------------------

failures=0
bad() {
  echo "FAIL $*" >&2
  failures=$((failures + 1))
}
t() { # name command...
  local name=$1
  shift
  if ! "$@" >/dev/null 2>&1; then
    bad "$name"
  fi
}
no() { ! "$@"; }
has() { grep -qF -- "$2" "$1"; }
has_re() { grep -qE -- "$2" "$1"; }
has_line() { grep -qxF -- "$2" "$1"; }
count_is() { [[ $(grep -cE -- "$2" "$1" || true) == "$3" ]]; }

if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  t "C1 omarchy-plugin-validate" omarchy-plugin-validate "$root"
fi
if command -v qmllint >/dev/null 2>&1; then
  t "C1 qmllint" qmllint "$root"/*.qml
else
  echo "skip: qmllint not present" >&2
fi
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$root"/tests/run.sh || bad "C1 shellcheck tests/run.sh"
  if [[ -f $root/bin/setup ]]; then
    shellcheck "$root"/bin/setup || bad "C1 shellcheck bin/setup"
  fi
else
  echo "skip: shellcheck not present" >&2
fi

for f in Service.qml BarWidget.qml Panel.qml Logic.js icon.svg bin/setup README.md; do
  [[ -f $f ]] || fail "missing $f"
done

qml_js=(Service.qml BarWidget.qml Panel.qml Logic.js)
code=("${qml_js[@]}" bin/setup)

work=$(mktemp -d)
work=$(cd "$work" && pwd -P)
trap 'rm -rf -- "$work"' EXIT

# --- C2 manifest -----------------------------------------------------------
t "C2 manifest kinds, entry points, no keepLoaded/activation" jq -e '
  (.kinds | index("service") != null and index("bar-widget") != null and index("panel") == null)
  and (.entryPoints.service | type == "string" and (startswith("/") | not))
  and (.entryPoints.barWidget | type == "string" and (startswith("/") | not))
  and (has("keepLoaded") | not) and (has("activation") | not)
' manifest.json

# --- C3/C4 IPC -------------------------------------------------------------
t "C3 exactly one IpcHandler in Service.qml" count_is Service.qml 'IpcHandler[[:space:]]*\{' 1
awk '/IpcHandler[[:space:]]*\{/{on=1}
     on{print; d+=gsub(/\{/,"{"); d-=gsub(/\}/,"}"); if(d==0) exit}' Service.qml >"$work/ipc"
t "C3 IpcHandler target" has_re "$work/ipc" 'target:[[:space:]]*"io\.mcmurray\.freenet-explorer"'
for m in start stop open status; do
  t "C3 IpcHandler function $m(): string" has_re "$work/ipc" "function $m\(\)[[:space:]]*:[[:space:]]*string"
done
t "C3 IpcHandler declares exactly four functions" count_is "$work/ipc" 'function ' 4
t "C4 no IpcHandler in BarWidget.qml" no has BarWidget.qml IpcHandler
t "C4 no IpcHandler in Panel.qml" no has Panel.qml IpcHandler

# --- C5 bar widget ---------------------------------------------------------
t "C5 moduleName" has BarWidget.qml 'moduleName: "io.mcmurray.freenet-explorer"'
first_type() { grep -vE '^[[:space:]]*(//|import|pragma|$)' "$1" | head -n1; }
t "C5 root type is BarWidget" grep -qE '^BarWidget[[:space:]]*\{' <<<"$(first_type BarWidget.qml)"
for fn in open close toggle closeForPopoutSwitch; do
  t "C5 function $fn(" has BarWidget.qml "function $fn("
done
t "C5 declares opened" has_re BarWidget.qml 'property bool opened'
t "C5 declares popoutSwitchClosing" has_re BarWidget.qml 'property bool popoutSwitchClosing'
t "C5 Loader" has_re BarWidget.qml 'Loader[[:space:]]*\{'
t "C5 loads Panel.qml" has BarWidget.qml 'Qt.resolvedUrl("Panel.qml")'
for p in bar settings anchorItem service; do
  t "B4.5 widget assigns panel.$p" has_re BarWidget.qml "\.$p = "
done
t "B4.2 glyph uses no Image" no has_re BarWidget.qml '(^|[^A-Za-z])(Image|AnimatedImage)[[:space:]]*\{'
t "B4.4 widget never starts or stops anything" no has_re BarWidget.qml '(startExplorer|stopExplorer|startNode|systemctl|execDetached)'

# --- C6 polling ------------------------------------------------------------
t "C6 exactly one Timer in Service.qml" count_is Service.qml '(^|[^A-Za-z])Timer[[:space:]]*\{' 1
t "C6 no Timer in BarWidget.qml" no has_re BarWidget.qml '(^|[^A-Za-z])Timer[[:space:]]*\{'
t "C6 no Timer in Panel.qml" no has_re Panel.qml '(^|[^A-Za-z])Timer[[:space:]]*\{'
t "C6 interval literal present" has_re Service.qml 'interval:[[:space:]]*[0-9]+'
t "C6 repeat: true" has Service.qml 'repeat: true'
t "C6 running: true" has Service.qml 'running: true'
while IFS= read -r v; do
  ((v >= 10000)) || bad "C6 interval below 10000: $v"
done < <(grep -ohE 'interval:[[:space:]]*[0-9]+' ./*.qml | grep -oE '[0-9]+$')
completed=$(awk '/Component.onCompleted/{on=1} on{print} on && /^  }/{exit}' Service.qml)
t "C6 Component.onCompleted refreshes" grep -qF 'refresh()' <<<"$completed"

# --- C7-C11 network and forbidden strings ----------------------------------
while IFS= read -r u; do
  case $u in
    /dev/tcp/127.0.0.1/7509 | /dev/tcp/127.0.0.1/8787) ;;
    *) bad "C7 unexpected tcp target: $u" ;;
  esac
done < <(grep -ohE "/dev/tcp/[^\"' )]*" "${code[@]}")
while IFS= read -r u; do
  [[ $u == http://127.0.0.1:8787/* ]] || bad "C8 unexpected http URL: $u"
done < <(grep -ohE "http://[^\"' )]*" "${qml_js[@]}")
t "C9 api/summary present" grep -qF 'api/summary' "${qml_js[@]}"
t "C9 exact curl argv" has Service.qml '["curl", "-sS", "--max-time", "2", "--proto", "=http", Logic.SUMMARY_URL]'
# Real calls only: Panel.qml shows the node installer command as display text.
curl_calls=$(grep -hE "[\"']curl[\"']" "${qml_js[@]}" || true)
t "C9 no -L/--location/-X/-H/--data on curl calls" no grep -qE -- '"(-L|--location|-X|-H|--header|--data[a-z-]*)"' <<<"$curl_calls"
for ep in fetch regather auto keep unkeep mine; do
  t "C10 no /api/$ep" no grep -qF -- "/api/$ep" "${code[@]}"
done
for w in sudo pkexec firewall-cmd iptables ufw 0.0.0.0 --port; do
  t "C11 no '$w' in code" no grep -qF -- "$w" "${code[@]}"
done
for w in pacman yay curl wget 'git clone' nft; do
  t "C11 no '$w' in bin/setup" no grep -qwF -- "$w" bin/setup
done

# --- Service command argv (spec Behaviour 1, 2, 3) --------------------------
for lit in \
  '["timeout", "1", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/7509"]' \
  '["timeout", "1", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8787"]' \
  '["systemctl", "--user", "cat", "freenet-explorer.service"]' \
  '["systemctl", "--user", "cat", "freenet.service"]' \
  '["test", "-f", root.homeDir + "/.config/systemd/user/freenet.service"]' \
  '["bash", "-c", "command -v freenet >/dev/null 2>&1 || test -x \"$HOME/.local/bin/freenet\""]' \
  '["test", "-d", root.keptDir]' \
  '["omarchy-launch-webapp", "http://127.0.0.1:8787/"]' \
  '["xdg-open", root.keptDir]' \
  '["bash", "-c", root.desktopScript, "freenet-explorer-desktop", root.desktopPath, root.iconPath]' \
  '["bash", "-c", root.cleanupScript, "freenet-explorer-desktop-cleanup",' \
  'Quickshell.env("FREENET_EXPLORER_KEPT")'; do
  t "B1-3 Service.qml has $lit" has Service.qml "$lit"
done
t "B1.7 fdev is never run from QML" no grep -qE "[\"']fdev[\"']" "${qml_js[@]}"
t "B5.3 Panel uses PanelKeyCatcher" has Panel.qml 'PanelKeyCatcher'
t "B5.3 Panel uses KeyboardPanel" has Panel.qml 'KeyboardPanel'
texts=$(grep -cE '^[[:space:]]*Text[[:space:]]*\{' Panel.qml || true)
plain=$(grep -cF 'textFormat: Text.PlainText' Panel.qml || true)
[[ $texts == "$plain" ]] || bad "B5.6 Text items ($texts) without PlainText ($plain plain)"
t "B5.5 node install command shown" has Panel.qml 'curl -fsSL https://freenet.org/install.sh | sh'
t "B5.5 popup does not mention Docker" no grep -qi docker Panel.qml

# --- Source must parse: U+2028/U+2029 end a line inside JS source -----------
for f in "${qml_js[@]}"; do
  t "C19 $f has no raw U+2028/U+2029 (line terminators; break regex literals)" \
    no env LC_ALL=C grep -qE $'\xe2\x80(\xa8|\xa9)' "$f"
done

# --- C12 unit text ----------------------------------------------------------
marker='# io.mcmurray.freenet-explorer user service. Safe to delete; bin/setup rewrites it.'
t "C12 bash shebang" has_line bin/setup '#!/usr/bin/env bash'
t "C12 set -euo pipefail" has_line bin/setup 'set -euo pipefail'
t "C12 marker" has bin/setup "$marker"
t "C12 ExecStart ends in /run.sh" has_re bin/setup '^ExecStart=.*/run\.sh$'
t "C12 Restart=on-failure" has bin/setup 'Restart=on-failure'
t "C12 no AmbientCapabilities" no has bin/setup AmbientCapabilities

# --- C13-C18 bin/setup behaviour --------------------------------------------
stub=$work/stub
mkdir -p "$stub"
cat >"$stub/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$STUB_LOG"
exit "${STUB_RC:-0}"
EOF
chmod +x "$stub/systemctl"

n=0
new_case() { # sets h (HOME), unit, STUB_LOG, ex (fake explorer)
  n=$((n + 1))
  h=$work/home$n
  ex=$work/explorer$n
  unit=$h/.config/systemd/user/freenet-explorer.service
  log=$work/log$n
  mkdir -p "$h" "$ex"
  : >"$log"
  printf '#!/bin/sh\n' >"$ex/run.sh"
  chmod +x "$ex/run.sh"
}
setup_run() { # explorer-dir-or-empty args...; sets rc, writes $work/out and $work/err
  local dir=$1
  shift
  local envs=("HOME=$h" "PATH=$stub:$PATH" "STUB_LOG=$log" "STUB_RC=${stub_rc:-0}")
  if [[ -n $dir ]]; then
    envs+=("FREENET_EXPLORER_DIR=$dir")
  fi
  rc=0
  env -u XDG_CONFIG_HOME -u FREENET_EXPLORER_DIR "${envs[@]}" \
    bash "$root/bin/setup" "$@" >"$work/out" 2>"$work/err" || rc=$?
}
rc_is() { [[ $rc == "$1" ]] || bad "$2 (exit $rc, wanted $1; stderr: $(head -c 300 "$work/err"))"; }
expected_unit() {
  printf '%s\n' "$marker" '[Unit]' 'Description=Freenet Explorer (localhost only)' \
    'After=default.target' '' '[Service]' 'Type=simple' "WorkingDirectory=$1" \
    "ExecStart=$1/run.sh" 'Restart=on-failure' 'RestartSec=2' '' '[Install]' \
    'WantedBy=default.target'
}
empty_tree() { [[ -z $(find "$1" -mindepth 1 -print -quit) ]]; }

new_case
setup_run "" --check
rc_is 0 "C13 --check with empty HOME"
t "C13 --check creates nothing" empty_tree "$h"
t "C13 --check never calls systemctl" no test -s "$log"
t "C13 --check fdev line" has_re "$work/out" '^fdev: '
t "C13 --check node line" has_re "$work/out" '^node 127\.0\.0\.1:7509: (not )?listening$'
t "C13 --check explorer not found" has_line "$work/out" 'explorer: run.sh not found'
t "C13 --check unit not installed" has_line "$work/out" 'unit: not installed'
setup_run "$ex" --check
t "C13 --check reports explorer dir" has_line "$work/out" "explorer: $ex"

new_case
setup_run "$ex"
rc_is 0 "C14 install"
expected_unit "$ex" >"$work/want"
t "C14 unit text matches the contract" cmp "$work/want" "$unit"
t "C14 unit mode 644" test "$(stat -c %a "$unit" 2>/dev/null)" = 644
t "C14 daemon-reload called" has "$log" '--user daemon-reload'
t "C14 no enable/start" no grep -qwE 'enable|start' "$log"
t "C14 summary names the unit path" has "$work/out" "$unit"
cp "$unit" "$work/first" 2>/dev/null || true
setup_run "$ex"
rc_is 0 "C14 second install"
t "C14 second run byte-identical" cmp "$work/first" "$unit"
t "C14 no temp files left" test "$(find "$(dirname "$unit")" -mindepth 1 | wc -l)" = 1
setup_run "$ex" --check
t "C13 --check managed unit" has_line "$work/out" 'unit: installed (managed by bin/setup)'

new_case
mkdir -p "$h/Development/freenet-explorer"
printf '#!/bin/sh\n' >"$h/Development/freenet-explorer/run.sh"
setup_run "$work/does-not-exist"
rc_is 0 "B6.1/B6.3 falls back to ~/Development and installs a non-executable run.sh"
t "B6.1 fallback ExecStart" has_line "$unit" "ExecStart=$h/Development/freenet-explorer/run.sh"
t "B6.3 warns run.sh not executable" has "$work/err" 'not executable'

new_case
setup_run ""
rc_is 1 "C15 no explorer, variable unset"
t "C15 no unit written (unset)" no test -e "$unit"
t "C15 error names the override" has "$work/err" FREENET_EXPLORER_DIR
mkdir -p "$work/norun"
setup_run "$work/norun"
rc_is 1 "C15 variable points to dir without run.sh"
t "C15 no unit written (bad var)" no test -e "$unit"

i=0
for name in 'a b' 'a%b' 'a$b' 'a"b' "a'b" 'a\b' $'a\nb' $'trail\n'; do
  new_case
  i=$((i + 1))
  d=$work/unsafe$i/$name
  mkdir -p "$d"
  printf '#!/bin/sh\n' >"$d/run.sh"
  setup_run "$d"
  rc_is 1 "B6.2 unsafe path #$i"
  t "B6.2 no unit for unsafe path #$i" no test -e "$unit"
done

new_case
mkdir -p "$(dirname "$unit")"
printf '[Unit]\nDescription=mine\n' >"$unit"
cp "$unit" "$work/foreign"
setup_run "$ex"
rc_is 1 "C16 install over unmarked unit"
t "C16 unmarked unit unchanged" cmp "$work/foreign" "$unit"
setup_run "$ex" --check
t "C13 --check unmanaged unit" has_line "$work/out" 'unit: installed (not managed)'
: >"$log"
setup_run "$ex" --remove
rc_is 1 "C16 remove unmarked unit"
t "C16 unmarked unit still unchanged" cmp "$work/foreign" "$unit"
t "C16 nothing stopped" no test -s "$log"

new_case
mkdir -p "$(dirname "$unit")"
expected_unit "$ex" >"$work/linked"
cp "$work/linked" "$work/linked.orig"
ln -s "$work/linked" "$unit"
setup_run "$ex"
rc_is 1 "B6.4 install refuses a symlink"
t "B6.4 symlink kept" test -L "$unit"
: >"$log"
setup_run "$ex" --remove
rc_is 1 "B6.6 remove refuses a symlink"
t "B6.6 symlink still there" test -L "$unit"
t "B6.6 link target unchanged" cmp "$work/linked" "$work/linked.orig"
t "B6.6 nothing stopped for symlink" no test -s "$log"

new_case
setup_run "$ex"
mkdir -p "$h/.local/share/applications"
: >"$h/.local/share/applications/io.mcmurray.freenet-explorer.desktop"
: >"$log"
setup_run "$ex" --remove
rc_is 0 "C17 remove"
t "C17 unit deleted" no test -e "$unit"
t "C17 stop logged" has_line "$log" '--user stop freenet-explorer.service'
t "C17 reload logged" has_line "$log" '--user daemon-reload'
t "B6.6 desktop file untouched" test -e "$h/.local/share/applications/io.mcmurray.freenet-explorer.desktop"
setup_run "$ex" --remove
rc_is 0 "C17 second remove"
t "C17 says not installed" has "$work/out" 'not installed'

new_case
stub_rc=1
setup_run "$ex"
rc_is 0 "B6.5 failing daemon-reload is only a warning"
t "B6.5 warning tells the user to reload" has "$work/err" 'daemon-reload'
setup_run "$ex" --remove
rc_is 0 "B6.6 remove ignores systemctl failures"
t "B6.6 unit deleted despite failures" no test -e "$unit"
stub_rc=0

new_case
setup_run "$ex" --bogus
rc_is 2 "C18 --bogus"
t "C18 usage on stderr" has "$work/err" 'usage'
t "C18 --bogus writes nothing" empty_tree "$h"
for a in -h --help; do
  setup_run "$ex" "$a"
  rc_is 0 "C18 $a"
  t "C18 $a usage on stdout" has "$work/out" 'usage'
done
setup_run "$ex" --check extra
rc_is 2 "C18 extra argument"

# --- C19 Logic.js ------------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  cat >"$work/logic.js" <<'EOF'
const fs = require("fs"), vm = require("vm");
const src = fs.readFileSync(process.argv[2], "utf8").replace(/^\.pragma library[^\n]*$/m, "");
const L = {};
try { vm.runInNewContext(src, L, { filename: "Logic.js" }); }
catch (e) { console.error("FAIL C19 Logic.js does not load: " + e.name + ": " + e.message); process.exit(1); }
let bad = 0;
function eq(name, got, want) {
  if (got !== want) { console.error(`FAIL C19 ${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`); bad++; }
}
eq("status down", L.statusLine(false, false, -1), "node=down explorer=stopped hosted=unknown");
eq("status node only", L.statusLine(true, false, -1), "node=up explorer=stopped hosted=unknown");
eq("status running", L.statusLine(true, true, 12), "node=up explorer=running hosted=12");
eq("status zero", L.statusLine(true, true, 0), "node=up explorer=running hosted=0");
eq("status unknown", L.statusLine(true, true, -1), "node=up explorer=running hosted=unknown");
eq("status stale", L.statusLine(true, false, 5), "node=up explorer=stopped hosted=unknown");
eq("status explorer without node", L.statusLine(false, true, 3), "node=down explorer=running hosted=3");
eq("parse 12", L.parseHosted('{"node":{"hosted":12},"total":{"n":99}}'), 12);
eq("parse 0", L.parseHosted('{"node":{"hosted":0}}'), 0);
for (const s of ["not json", "", "{}", "null", "5", "[]", '{"node":null}', '{"node":5}', '{"node":{}}',
  '{"node":{"hosted":"12"}}', '{"node":{"hosted":-1}}', '{"node":{"hosted":1.5}}',
  '{"node":{"hosted":1e999}}', '{"node":{"hosted":null}}', '{"total":{"n":4}}'])
  eq("parse " + JSON.stringify(s), L.parseHosted(s), -1);
const dot = "·";
eq("tip down", L.tooltipText(false, false, -1), `Freenet Explorer ${dot} node down`);
eq("tip explorer without node", L.tooltipText(false, true, 3), `Freenet Explorer ${dot} node down`);
eq("tip node only", L.tooltipText(true, false, -1), `Freenet Explorer ${dot} node up, explorer stopped`);
eq("tip hosted", L.tooltipText(true, true, 12), `Freenet Explorer ${dot} 12 hosted`);
eq("tip running", L.tooltipText(true, true, -1), `Freenet Explorer ${dot} explorer running`);
eq("glyph down", L.glyphState(false, false), "down");
eq("glyph explorer without node", L.glyphState(false, true), "down");
eq("glyph undefined", L.glyphState(undefined, undefined), "down");
eq("glyph nodeOnly", L.glyphState(true, false), "nodeOnly");
eq("glyph running", L.glyphState(true, true), "running");
const joined = L.oneLine("  a\r\nb\nc\rd  \n");
eq("oneLine has no CR/LF", /[\r\n]/.test(joined), false);
eq("oneLine newlines become spaces, trimmed", joined.replace(/ +/g, " "), "a b c d");
eq("oneLine long", L.oneLine("x".repeat(500)).length <= 200, true);
eq("PLUGIN_ID", L.PLUGIN_ID, "io.mcmurray.freenet-explorer");
eq("SETUP_PATH", L.SETUP_PATH, "~/.config/omarchy/plugins/io.mcmurray.freenet-explorer/bin/setup");
eq("UI_URL", L.UI_URL, "http://127.0.0.1:8787/");
eq("SUMMARY_URL", L.SUMMARY_URL, "http://127.0.0.1:8787/api/summary");
process.exit(bad ? 1 : 0);
EOF
  node "$work/logic.js" "$root/Logic.js" || bad "C19 Logic.js unit checks"
else
  echo "skip: node not present, Logic.js unit checks not run" >&2
fi

# --- C20 icon ----------------------------------------------------------------
if command -v xmllint >/dev/null 2>&1; then
  t "C20 icon.svg well-formed" xmllint --noout --nonet icon.svg
else
  echo "skip: xmllint not present" >&2
fi
t "C20 no <image" no has icon.svg '<image'
# The SVG namespace is the only allowed http URL. Anything else is a remote reference.
if grep -v -F 'xmlns="http://www.w3.org/2000/svg"' icon.svg | grep -qF 'http'; then
  bad "C20 http outside the SVG namespace"
fi
t "C20 no URL href" no has_re icon.svg 'href=["'\''][[:space:]]*([a-z]+:|//)'
t "B glyph is an iconComponent" has BarWidget.qml 'iconComponent:'
t "B panel switch uses switchPanelFrom" has Panel.qml 'switchPanelFrom'
t "B no switchPanelPopout" no has Panel.qml 'switchPanelPopout'

# --- C21 README --------------------------------------------------------------
for hd in Install 'One-time setup' IPC 'Example keybinding' Uninstall Security; do
  t "C21 heading $hd" has_re README.md "^#+ $hd\$"
done
for s in 'bin/setup --remove' 'omarchy plugin remove' \
  '~/.local/share/applications/io.mcmurray.freenet-explorer.desktop' \
  'https://freenet.org/quickstart/docker/' \
  'omarchy plugin add file:///home/ianm/Development/omarchy-freenet-explorer --enable --yes' \
  'omarchy plugin add <git-url>' 'omarchy-restart-shell' 'FREENET_EXPLORER_DIR' 'FREENET_EXPLORER_KEPT' \
  'systemctl --user enable --now freenet-explorer' \
  'omarchy-shell shell summon io.mcmurray.freenet-explorer' \
  'node=down explorer=stopped hosted=unknown' 'node=up explorer=stopped hosted=unknown' \
  'node=up explorer=running hosted=12'; do
  t "C21 README has $s" has README.md "$s"
done
for m in start stop open status; do
  t "C21 README IPC $m" has_line README.md "omarchy-shell io.mcmurray.freenet-explorer $m"
done
t "C21 keybinding line" has_line README.md 'o.bind("SUPER + CTRL + F", "Freenet Explorer", "omarchy-shell io.mcmurray.freenet-explorer open")'
t "C21 no 'Not written yet'" no has README.md 'Not written yet'
t "C21 no bogus github link" no has_re README.md 'https://github\.com/([^A-Za-z0-9]|$)'

# --- C23 launcher scripts, extracted from Service.qml and run in a sandbox ---
extract() { awk -v start="property string $1: \`" '
  index($0, start) {on=1; next} on && $0 == "`" {exit} on {print}' Service.qml; }
write_script=$(extract desktopScript)
clean_script=$(extract cleanupScript)
t "C23 desktopScript extracted" test -n "$write_script"
t "C23 cleanupScript extracted" test -n "$clean_script"
t "C23 scripts are fixed literals" no grep -qE '\$\{|\\' <<<"$write_script$clean_script"

apps="$work/desk home/.local/share/applications"
desk=$apps/io.mcmurray.freenet-explorer.desktop
icon='/opt/plug in/$(touch pwned)/icon.svg'
write() { (cd "$work" && bash -c "$write_script" freenet-explorer-desktop "$desk" "$icon"); }
printf '%s\n' '[Desktop Entry]' 'Type=Application' 'Name=Freenet Explorer' \
  "Comment=Local browser for what this machine's Freenet node is hosting" \
  'Exec=omarchy-shell io.mcmurray.freenet-explorer open' "Icon=$icon" 'Terminal=false' \
  'Categories=Network;' 'Keywords=freenet;explorer;' 'X-Freenet-Explorer-Managed=true' >"$work/desk.want"
t "C23 write succeeds" write
t "C23 content matches the contract" cmp "$work/desk.want" "$desk"
t "C23 mode 0644" test "$(stat -c %a "$desk" 2>/dev/null)" = 644
t "C23 rewrite succeeds" write
t "C23 rewrite identical" cmp "$work/desk.want" "$desk"
t "C23 no temp files left" test "$(find "$apps" -mindepth 1 2>/dev/null | wc -l)" = 1
t "C23 icon path is not evaluated" no test -e "$work/pwned"
printf 'mine\n' >"$desk"
t "C23 refuses unmanaged file" no write
t "C23 unmanaged file unchanged" test "$(cat "$desk")" = mine
rm -f -- "$desk"
cp "$work/desk.want" "$work/desk.target"
ln -s "$work/desk.target" "$desk"
t "C23 refuses symlink" no write
t "C23 symlink kept" test -L "$desk"

cfg=$work/shell.json
clean() { bash -c "$clean_script" freenet-explorer-desktop-cleanup "$desk" "$cfg" io.mcmurray.freenet-explorer; }
cleanup_case() { # name keep|delete [shell.json content]
  rm -f -- "$desk" "$cfg"
  cp "$work/desk.want" "$desk"
  if (($# > 2)); then printf '%s' "$3" >"$cfg"; fi
  clean >/dev/null 2>&1 || true
  if [[ $2 == keep ]]; then
    [[ -f $desk ]] || bad "B3.3 cleanup should keep: $1"
  else
    [[ ! -e $desk ]] || bad "B3.3 cleanup should delete: $1"
  fi
}
cleanup_case "no shell.json" delete
cleanup_case "id not listed" delete '{"bar":{"layout":{"right":[{"id":"other"}]}},"plugins":["x"]}'
cleanup_case "empty object" delete '{}'
cleanup_case "id only outside bar.layout/plugins" delete '{"disabled":["io.mcmurray.freenet-explorer"]}'
cleanup_case "string in bar layout" keep '{"bar":{"layout":{"right":["io.mcmurray.freenet-explorer"]}}}'
cleanup_case "object in bar layout" keep '{"bar":{"layout":{"right":[{"id":"io.mcmurray.freenet-explorer"}]}}}'
cleanup_case "listed in plugins" keep '{"plugins":[{"id":"io.mcmurray.freenet-explorer"}]}'
cleanup_case "unparsable shell.json" keep '{"bar":'
cleanup_case "empty shell.json" keep ''
rm -f -- "$desk" "$cfg"
printf 'mine\n' >"$desk"
clean >/dev/null 2>&1 || true
t "B3.3 cleanup keeps unmanaged file" test -f "$desk"
rm -f -- "$desk"
ln -s "$work/desk.target" "$desk"
clean >/dev/null 2>&1 || true
t "B3.3 cleanup keeps symlink" test -L "$desk"
rm -f -- "$desk"
cp "$work/desk.want" "$desk"
mkdir -p "$work/nojq"
ln -s "$(command -v grep)" "$work/nojq/grep"
ln -s "$(command -v rm)" "$work/nojq/rm"
PATH="$work/nojq" "$BASH" -c "$clean_script" cleanup "$desk" "$cfg" io.mcmurray.freenet-explorer >/dev/null 2>&1 || true
t "B3.3 cleanup keeps file without jq" test -f "$desk"

if ((failures > 0)); then
  fail "$failures check(s) failed"
fi

echo "ok"
