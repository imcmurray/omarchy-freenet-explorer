# Omarchy plugin contract (verified on this machine)

Verified 2026-11-25 on Omarchy 4.5.0 (`BUILD_ID=4.5.0`). This is the contract the
Freenet Explorer plugin must follow. It was read off this PC, not copied from
the task brief. Sources are named below. Where the brief and the machine
disagree, the machine wins.

## What a plugin is

A third-party plugin is a git checkout of a folder whose `manifest.json` sits
at the top. It installs with `omarchy plugin add <git-url>` (alias
`omarchy plugin install`), which clones into
`~/.config/omarchy/plugins/<id>/`. Enable with
`omarchy plugin enable <id> [--section <section>]`. Remove with
`omarchy plugin remove <id>` (alias `rm`). Update with
`omarchy plugin update <id>`. List with `omarchy plugin list [--json]`.
Validate with `omarchy plugin validate <folder>`.

`omarchy plugin add` refuses a URL that is a git transport helper
(`/usr/bin/omarchy-git-url-check`). Allowed URL schemes include `https`,
`http`, `file`, `ssh`, `git`. A bare filesystem path is also allowed. A local
checkout therefore installs as:

```bash
omarchy plugin add file:///home/ianm/Development/omarchy-freenet-explorer --enable --yes
```

`--yes` skips the interactive "this plugin is unsandboxed code" confirm.
Without a TTY, add refuses to continue unless `--yes` is passed. After the
clone, add runs `omarchy plugin validate` and `omarchy-shell shell rescanPlugins`.
`--enable` then calls `omarchy plugin enable`.

There are no install hooks. Add/remove/update only clone, validate, enable or
disable, and delete the checkout. They do not install packages, write systemd
units, or copy files outside `~/.config/omarchy/plugins/<id>/`. Packages,
systemd units, and desktop launchers have to be installed by something the
plugin runs itself, or by a script the user runs. `omarchy plugin remove`
deletes only the checkout (git checkouts are `rm -rf`'d; non-git folders are
moved to a hidden backup). It does not undo files the plugin wrote elsewhere.

First-party plugins live under `/usr/share/omarchy/shell/plugins` and use the
same manifest. Their ids are reserved: anything starting with `omarchy.` is
rejected. Third-party plugins live one directory deep in
`~/.config/omarchy/plugins/<id>/`. Hidden directories are ignored. A symlink
anywhere in the folder except inside `.git` fails validation.

The shell loads plugin QML inside the long-lived `omarchy-shell` process.
Plugins are unsandboxed. `omarchy-shell` does not start the shell; the shell
is already running. Restart it with `omarchy-restart-shell` after a plugin
change that hot-reload does not pick up. The registry watches the plugins
directory with `inotifywait`, so a file edit is noticed, but a freshly added
plugin still needs `rescanPlugins` (add does this) and a shell that reloads
QML.

## manifest.json

Enforced by both `/usr/bin/omarchy-plugin-validate` and
`/usr/share/omarchy/shell/services/PluginRegistry.qml` `validateManifest`.
`schemaVersion` must be the JSON number `1`, not the string `"1"`.

Required fields: `id`, `name`, `version`, `kinds`, `entryPoints`.

`id` matches `^[A-Za-z0-9][A-Za-z0-9._-]*$`, is non-empty, contains no `..`,
and does not start with `omarchy.`. Reverse-DNS ids are the usual third-party
shape (`io.github.honeyspoons.localsend`, `com.windscribe.vpn`,
`io.github.andressm415.omaprox`). This plugin's id is
`io.mcmurray.freenet-explorer`.

`kinds` is a non-empty array. A kind the validator knows about must have a
matching entry point:

| kind | entryPoints key | loaded as |
| --- | --- | --- |
| `bar` | `bar` | replaces the whole bar |
| `bar-widget` | `barWidget` | a slot in the bar |
| `menu` | `menu` | on-demand menu |
| `overlay` | `overlay` | on-demand overlay |
| `panel` | `panel` | on-demand panel (`omarchy-shell shell summon <id>`) |
| `service` | `service` | headless object, created when the plugin is enabled |

This plugin is `service` plus `bar-widget`. It is not a `panel` kind. A
bar-widget's popup is part of the widget, not a separate panel kind. Claiming
`panel` as well would route `summon` to the panel loader instead of the bar
(`shell.qml` `isBarWidgetPanelPlugin`).

`entryPoints` values are relative paths inside the plugin folder. They must
not be absolute, must not contain `..` or a newline, and the file must exist.
No other keys are required. Common optional fields that real plugins set and
the validator ignores: `author`, `license`, `description`, `keywords`,
`activation`, `keepLoaded`, `omarchy`.

Do not set `keepLoaded`. That flag is for lock-screen and similar services
that must survive a plugin reload. Do not set `activation`; the shell never
reads it.

`barWidget` is optional metadata. If `defaultSection` is present it must be
one of `left`, `centerBegin`, `center`, `centerEnd`, `tray`, `right`.
`center` is stored as `centerEnd` at enable time, beside the clock rather than
in the center box. This plugin uses `right`. Also set `displayName`,
`description`, `category` (`Network`), `aliases` (include `freenet` and
`explorer`), and `allowMultiple: false`. A settings `schema` is not required.
Do not add a refresh-interval setting below 10 seconds. The poll period is
fixed at 10 seconds in the service, so there is nothing to configure.

`omarchy plugin enable` writes a bar-widget into `bar.layout.<section>` of
`~/.config/omarchy/shell.json`. A third-party plugin that is only a service
goes into `plugins[]`. A plugin that has both kinds is enabled by its bar
slot: `PluginRegistry.isEnabled` is true when the id is in the bar layout, and
`shell.qml` `_syncServices` then creates the service. Disabling removes the
bar slot and destroys the service.

## QML entry points

Imports used by every reference widget on this machine:

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
```

`qs.Commons` and `qs.Ui` resolve from `/usr/share/omarchy/shell`
(`Commons/qmldir`, `Ui/qmldir`). Theme colors come from the `Color` singleton
in `Commons/Color.qml`, which reloads `theme/colors.toml` and `theme/shell.toml`
when the theme changes. Use these, not a private palette:

- `Color.foreground`, `Color.background`, `Color.accent`, `Color.urgent`, `Color.muted`
- `Color.popups.background`, `Color.popups.text`, `Color.popups.border`
- `Color.bar.text`, `Color.bar.active`
- the bar host's `bar.foreground` / `bar.barForeground` for the glyph, so the
  icon matches the bar rather than the popup

Spacing and type come from `Style` (`Style.space`, `Style.bar.iconFont`,
`Style.bar.iconCanvas`, `Style.font.family`, `Style.duration`). Popups use
`KeyboardPanel` anchored to the bar button, with a `PanelKeyCatcher` for
arrows, Enter, Esc, and Tab-to-adjacent-panel. The bar button is a
`BarIconButton`. Reference implementations read in full for this contract:
`~/.config/omarchy/plugins/b.omadoro/` (service + bar widget + panel) and
`~/.config/omarchy/plugins/io.github.honeyspoons.localsend/` (panel, IPC,
status line). First-party shape is the same: `qs.Ui` `BarWidget` base in
`/usr/share/omarchy/shell/Ui/BarWidget.qml`.

The bar host injects `bar`, `moduleName`, and `settings` into the widget root.
Set `moduleName: "io.mcmurray.freenet-explorer"`. The root widget must be a
`BarWidget` and must expose `open()`, `close()`, `toggle()`, `opened`, and
`closeForPopoutSwitch()` / `popoutSwitchClosing`, because
`Bar.summonBarWidget` looks for those. Put the popup in `Panel.qml` and load
it with a `Loader` (`source: Qt.resolvedUrl("Panel.qml")`), then assign
`bar`, `settings`, `anchorItem`, and the service onto the loaded item. This
is the Omadoro / Aegis pattern (`ianm.aegis` `BarWidget.qml`).

The service root is an `Item` or `QtObject` with `property var shell: null`
and `property var manifest: null`. The shell sets both. For a third-party
service, `shell` is a `PluginShellApi` (`services/PluginShellApi.qml`), not
the host shell. It can `summon`, `hide`, `toggle`, and `serviceFor` its own
id. The service object is parented to `null` so it is not walked from the
host item tree. One service instance exists per enabled plugin. Bar widgets
exist once per monitor, so do not put the single `IpcHandler` on the widget.

## IPC

`omarchy-shell [-q] <target> <method> [args...]` forwards to the running
shell. Quickshell `IpcHandler` objects are the targets. The shell's own
socket answers handlers that use `ShellIpc` (first-party). A third-party
`IpcHandler` is reached through `qs ipc` when the fast socket replies `SKIP`.
`omarchy-shell <id> <method>` still works: the socket skips, then `qs ipc`
runs the handler. That is how `hass`, `com.windscribe.vpn`, and
`io.github.honeyspoons.localsend` expose methods.

Rules that the registry enforces (`Commons/IpcRegistry.qml` and qs ipc):

- One handler per target. The first enabled handler wins. A second handler
  with the same target is ignored, so the methods on it do not exist.
- Only functions declared on the handler are callable. `destroy` and other
  QObject methods are not.
- The call's argument count must equal the function's declared parameter
  count. A parameter cannot be omitted. Give `start`, `stop`, `open`, and
  `status` no parameters.
- Annotate each parameter and the return type. Use `string` for anything the
  command should print. `void` prints nothing.

Put the only `IpcHandler` on the service:

```qml
IpcHandler {
  target: "io.mcmurray.freenet-explorer"
  function start(): string { return root.startExplorer() }
  function stop(): string { return root.stopExplorer() }
  function open(): string { return root.openUi() }
  function status(): string { return root.statusLine() }
}
```

`omarchy-shell shell summon io.mcmurray.freenet-explorer` opens the bar
popup through the widget's `open()`, separate from the `open` IPC method.
The IPC `open` opens the explorer UI in a browser. Do not overload one to
mean the other.

`status` prints one line, no newline tricks:

```text
node=down explorer=stopped hosted=unknown
node=up explorer=stopped hosted=unknown
node=up explorer=running hosted=12
```

`hosted` is `unknown` unless the explorer answered `/api/summary` and the
JSON had a numeric `node.hosted`. Never print `0` for "we failed to ask".
`start`, `stop`, and `open` return `ok` or a short single-line error.

## Bar widget

A small painted glyph, not a network fetch and not a remote image. Draw it
in QML (`Canvas` or a few `Rectangle`s) and tint it with the bar foreground.
Three states, each visually distinct:

| State | Meaning | Glyph |
| --- | --- | --- |
| node down | TCP connect to `127.0.0.1:7509` failed | dim, `Color.muted` or about 0.4 opacity |
| node up, explorer stopped | 7509 accepts, `127.0.0.1:8787` does not | `Color.urgent` or `Color.bar.active` |
| both running | 7509 and 8787 accept | full `bar.foreground`, or `Color.accent` if the bar foreground is the accent |

Tooltip (the `BarIconButton.tooltipText`, which is the hover text):

- node down: `Freenet · node down`
- node up, explorer stopped: `Freenet · node up, explorer stopped`
- both running, count known: `Freenet · N hosted`
- both running, count unknown: `Freenet · explorer running`

Click toggles the popup. Do not start or stop anything on a bare left click.

## Status polling

Do this in the service, on one `Timer`, `interval: 10000`, `repeat: true`,
also once from `Component.onCompleted`. Do not poll faster while the popup
is open. Do not call `fdev`. A TCP connect is enough and does not wake the
node.

Node up means a client connection to `127.0.0.1` port `7509` succeeds within
about one second. Explorer up means the same for port `8787`. Implement the
probe as a `Quickshell.Io.Process` with an argument array, not a shell
string built from outside data:

```javascript
["timeout", "1", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/7509"]
```

Exit 0 means the port accepted. The same command with `8787` is the explorer
probe. Never probe any other host.

When 8787 is up, and only then, GET `http://127.0.0.1:8787/api/summary`
with a two-second timeout and a 64 KiB cap. curl's default `Host: 127.0.0.1:8787` is one of
the three hosts the explorer allows (`127.0.0.1:8787`, `localhost:8787`,
`[::1]:8787` in `explorer/server.py`). Do not set a different Host. Do not
follow a redirect to another host. Read `node.hosted` only. That field is
the count of contract keys the explorer last saw from the node
(`collector.py` stores `{"hosted": len(keys), ...}` under the `node` kv).
`total.n` is a different number (rows in the explorer database, including
items fetched on demand). Ignore it.

`/api/summary` is a GET. It is not in the POST-only `ACTIONS` set
(`fetch`, `regather`, `auto`, `keep`, `unkeep`, `mine`). Do not call those.
Do not add an endpoint to the explorer. The explorer checkout at
`~/Development/freenet-explorer` stays unmodified.

If the JSON is invalid or `node.hosted` is missing, leave the count unknown.

## Popup actions

Four rows, plus a fifth that depends on the node:

1. Explorer switch. On runs `systemctl --user start freenet-explorer.service`. Off runs `systemctl --user stop freenet-explorer.service`.
2. The same switch is the only start and stop control. There is no second row for the other verb.
3. Open UI. `omarchy-launch-webapp http://127.0.0.1:8787/`.
4. Open kept files. `xdg-open` the kept directory.
5. Node row. See below.

`omarchy-launch-webapp` is the Omarchy web-app convention
(`/usr/bin/omarchy-launch-webapp`). It runs the default Chromium-based
browser with `--app=<url>`. Use it. Do not invent a Firefox `--app` flag and
do not pass a browser name.

The kept directory is `$FREENET_EXPLORER_KEPT` when that variable is set,
otherwise `~/.local/share/freenet-explorer/kept`. If the directory does not
exist, say so in the popup. The explorer creates it on the first Keep. Do
not create it, and do not write into it.

If `systemctl --user start` fails because the unit is not installed, the
status text and the start row say to run `bin/setup` once. Quote the path
of the installed plugin: `~/.config/omarchy/plugins/io.mcmurray.freenet-explorer/bin/setup`.

Keyboard: Up/Down move, Enter activates, Esc closes. Match `PanelKeyCatcher`.

## Node not installed

Checked at runtime, not baked in from this machine. This PC, on 2026-11-25,
has no `freenet` or `fdev` binary, no `freenet*.service` user unit, and
nothing listening on 7509 or 8787. `pacman -Ss freenet` printed nothing.
The AUR package named `freenet` is the old Java Hyphanet client and is the
wrong program. Do not name it as an install target. Do not run `yay`,
`pacman`, or `curl | sh` from the plugin.

Offer "Start Freenet node" only when a user service is actually there:
`~/.config/systemd/user/freenet.service` exists, or
`systemctl --user cat freenet.service` succeeds. The official Linux
installer creates that user unit (see https://freenet.org/uninstall/).
Starting it is `systemctl --user start freenet.service` as an argument
array. Do not use sudo. Do not start a system unit.

Otherwise the node row is text, not a button that runs an installer:

- The Linux install from https://freenet.org/quickstart/ is
  `curl -fsSL https://freenet.org/install.sh | sh`. It installs the Rust
  node and `fdev` into `~/.local/bin` and starts a user service. Say that
  the AUR `freenet` package is the old Java client and must not be used.
- If `~/.local/bin/freenet` or `freenet` on `PATH` exists but the user unit
  does not, say the binary is present and the user service is not, and
  point at https://freenet.org/quickstart/ and https://freenet.org/uninstall/.
  Do not invent a `freenet service install` invocation.

A Docker image exists (`ghcr.io/freenet/freenet-core`) for a server. Do not
offer to start Docker from the popup. The README can mention it in one line
with the link https://freenet.org/quickstart/docker/.

## Running the explorer

The plugin cannot ship a systemd unit. `bin/setup` is the one-time step.
It is idempotent, uses no sudo, and installs nothing through pacman.

Behavior:

- Resolve the explorer checkout. `$FREENET_EXPLORER_DIR` if it contains
  `run.sh`, otherwise `$HOME/Development/freenet-explorer`. If `run.sh` is
  missing, exit 1 and say so. Do not clone or download the explorer.
- Warn, and continue, if `fdev` is not on `PATH` and not at
  `~/.local/bin/fdev`, or if nothing accepts TCP `127.0.0.1:7509`. The unit
  still gets installed. The explorer is useful to start later, and this
  machine has neither `fdev` nor a node.
- Write `~/.config/systemd/user/freenet-explorer.service` only when the
  file is absent or already contains the marker line
  `# io.mcmurray.freenet-explorer user service. Safe to delete; bin/setup rewrites it.`
  A unit without that marker is left untouched and setup exits 1.
- `systemctl --user daemon-reload`. Do not `enable` and do not `start`.
  The popup starts it.
- `bin/setup --remove` stops the unit, reloads, and deletes the unit file
  only when the marker is present. It does not remove the plugin checkout
  and it does not remove the desktop file (the service does that).
- `bin/setup --check` prints whether `fdev` and port 7509 are present, and
  whether the unit is installed, and exits 0. The tests call this.

Unit:

```ini
# io.mcmurray.freenet-explorer user service. Safe to delete; bin/setup rewrites it.
[Unit]
Description=Freenet Explorer (localhost only)
After=default.target

[Service]
Type=simple
WorkingDirectory=<absolute explorer directory>
ExecStart=<absolute path>/run.sh
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
```

`run.sh` is the explorer's own script. It creates `.venv` and execs
`python -m explorer`, which binds `127.0.0.1` only (`server.py` uses
`ThreadingHTTPServer(("127.0.0.1", app.port))`). Do not pass `--port`.
Do not set an environment variable that would move the bind. Do not add
`AmbientCapabilities`, `NoNewPrivileges` tricks, or a `User=` line. Do not
install the unit under `/etc/systemd/system`.

The `[Install]` section is unused because setup does not enable the unit.
Leave it so a person can `systemctl --user enable --now freenet-explorer`
themselves. The README says that is optional and that the plugin's Start
button does not need it.

## Launcher (SUPER+SPACE)

On this Omarchy, SUPER+SPACE is not a separate app launcher. The default
binding in `/usr/share/omarchy/default/hypr/bindings/utilities.lua` is:

```lua
o.bind("SUPER + SPACE", "Omarchy menu", { menu = "root" })
```

The menu's Apps rows come from `DesktopEntries`
(`/usr/share/omarchy/shell/services/AppLibrary.qml`, consumed by
`plugins/menu/Menu.qml` `mergeAppRows`). A `.desktop` file in
`~/.local/share/applications/` shows up there, and in the dock app grid
opened by SUPER+ALT+SPACE (`omarchy-shell omarchy.dock apps`). That is the
launcher entry. Searching "Freenet" from the menu finds it via
the desktop `Name` and `Keywords`.

Okomart (`b.okomart`, `~/.config` is not where it lives; the pattern is in
https://github.com/brianblakely/omarchy-plugins `Service.qml`) writes its
desktop file from the service when the service is created, and deletes it
on destruction only if `shell.json` no longer lists the plugin. Copy that
pattern. Do not write the desktop file from `bin/setup`, or it would
survive `omarchy plugin remove` as an extra leftover the brief does not
want. `plugin remove` disables the plugin first, which destroys the
service, which removes the desktop file while the shell is running.

Write `~/.local/share/applications/io.mcmurray.freenet-explorer.desktop`
with mode `0644`, via a temp file in the same directory and `mv`. Refuse
to replace the path if it is a symlink or if an existing regular file
lacks the marker `X-Freenet-Explorer-Managed=true`.

```ini
[Desktop Entry]
Type=Application
Name=Freenet
Comment=Local entry point for this machine's Freenet peer, its apps, and Freenet Explorer
Exec=omarchy-shell io.mcmurray.freenet-explorer open
Icon=<plugin dir>/icon.svg
Terminal=false
Categories=Network;
Keywords=freenet;explorer;aegis;
X-Freenet-Explorer-Managed=true
```

Ship `icon.svg` in the plugin: a small monochrome glyph, no embedded
raster, no remote href. `Icon` is an absolute path so it still works
before the icon theme is rebuilt. `Exec` calls the IPC `open` method,
which launches `omarchy-launch-webapp`. It does not itself start the
systemd unit. The popup's Start row does that. If the UI is down, the
webapp window will show a connection error; the popup already says how
to start the explorer. Do not make `open` start the unit. Starting a
service from a launcher click hides a failure inside a browser window.

On service destruction, a detached cleanup removes the desktop file only
when it is a regular file, contains the marker, and `~/.config/omarchy/shell.json`
does not still enable this plugin (bar layout or `plugins[]`). A shell
restart destroys the service too; the check keeps the launcher while the
plugin stays enabled. If the shell is not running during `plugin remove`,
the cleanup cannot run. The README says to delete that desktop file by
hand in that case.

Do not install a Hyprland binding. Document this example in the README,
matching `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + F", "Freenet", "omarchy-shell io.mcmurray.freenet-explorer open")
```

## Security

The plugin must not weaken Freenet or the explorer.

- Never listen on a port. Never proxy 8787 or 7509. Never call
  `firewall-cmd`, `iptables`, `nft`, or `ufw`. Never pass `--port` or a
  bind address.
- Talk to the explorer only at `http://127.0.0.1:8787/api/summary`, GET,
  default Host header.
- Do not call POST `/api/fetch`, `/api/regather`, `/api/auto`, `/api/keep`,
  `/api/unkeep`, or `/api/mine`. Those are the node-acting endpoints and
  they stay POST-only with `X-Explorer: 1` inside the explorer.
- Do not render contract bytes, HTML from the node, or kept-file contents.
  The explorer sandboxes untrusted bytes. The plugin only shows a count
  and runs local commands.
- Do not read or write the explorer database under
  `~/.local/share/freenet-explorer/` except to `xdg-open` the kept
  directory. The child-safety quarantine lives in that database. Leave it
  alone.
- Process commands are argument arrays. No string concatenation of paths
  into `bash -c`. The TCP probe's `bash -c` script is a fixed literal.
- No `sudo`, no `pkexec`, no polkit prompts.

## Tests

`bash tests/run.sh` is the gate. It must pass with no node and no `fdev`.
It already validates `manifest.json` with `jq` and, when
`omarchy-plugin-validate` is on `PATH`, runs it. Keep those. Extend the
script with static checks, still green on a machine with no node:

- `schemaVersion` is numeric 1, id is `io.mcmurray.freenet-explorer`, kinds
  contain `service` and `bar-widget`, entry points exist and stay relative.
- `Service.qml` contains one `IpcHandler` whose target is the plugin id and
  whose functions include `start`, `stop`, `open`, and `status`.
- `BarWidget.qml` does not declare an `IpcHandler`.
- The poll timer interval in `Service.qml` is `10000` or greater. No
  smaller literal used as a timer interval.
- `bin/setup` contains no `sudo` and no `pacman`.
- The unit text embedded in `bin/setup` contains `Restart=on-failure`,
  `ExecStart=` ending in `/run.sh`, and the marker comment. It does not
  contain `--port`, `0.0.0.0`, or `AmbientCapabilities`.
- `bash bin/setup --check` exits 0.
- `shellcheck` on `bin/setup` and `tests/run.sh` when `shellcheck` exists.
- `qmllint` on the QML files when `qmllint` exists. This machine has
  `qml6` but not `qmllint` (Qt 6.12 removed the standalone binary from
  `qt6-declarative`). Skipping when the binary is absent is correct.

Do not require a live node, a display, or `omarchy-shell` in the test
script. The dev-team sandbox can run this script and cannot curl the
network or talk to the session.

## Reference plugins read for this contract

Installed, read here: `b.omadoro` (manifest, `BarWidget.qml`, `Panel.qml`,
`Service.qml`, `bin` is a script at the root `flash-invert.sh`, tests),
`io.github.honeyspoons.localsend` (manifest, `Panel.qml`, `Service.qml`),
`ianm.aegis` (manifest, `BarWidget.qml` IPC shape; its IPC sits on the
widget, which this contract deliberately does not copy because of
per-monitor handlers), `ianm.tinnitus` (`bin/setup` unit install and
marker), `hass` and `robzolkos.github` (manifest schema, settings schema),
`vt.grok-usage` (service-only), `com.windscribe.vpn` manifest from
https://github.com/yegors/windscribe-omarchy, Okomart manifest and
`Service.qml` from https://github.com/brianblakely/omarchy-plugins
(desktop-file install and cleanup), and
https://github.com/tcballard/omarchy-plugin-template (starter manifest).

Catalog submission is a PR that adds a public git URL to
https://github.com/brianblakely/omarchy-plugins/blob/master/plugins.txt.
Do not open that PR. This repo has no public remote.
