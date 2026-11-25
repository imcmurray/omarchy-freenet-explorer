# Freenet Explorer for Omarchy

Omarchy shell plugin `io.mcmurray.freenet-explorer`. It adds a bar glyph and
a popup for the local Freenet Explorer checkout at
`~/Development/freenet-explorer`, which serves http://127.0.0.1:8787/.

The glyph has three states, refreshed every 10 seconds:

| State | Meaning | Glyph |
| --- | --- | --- |
| node down | nothing accepts `127.0.0.1:7509` | dim hollow ring |
| node up, explorer stopped | 7509 accepts, 8787 does not | urgent-colored ring with a dot |
| both running | 7509 and 8787 accept | three linked dots in the bar color |

A left click opens the popup: Start explorer, Stop explorer, Open UI, Open
kept files, and a node row. Up and Down move, Enter activates, Esc closes.

The implementation contract is
[docs/PLUGIN-CONTRACT.md](docs/PLUGIN-CONTRACT.md).

## Install

From this machine's local checkout:

```bash
omarchy plugin add file:///home/ianm/Development/omarchy-freenet-explorer --enable --yes
```

From any git URL:

```bash
omarchy plugin add <git-url> --enable --yes
```

If hot-reload does not pick the plugin up, run `omarchy-restart-shell`.

## One-time setup

Plugins cannot ship a systemd unit, so run this once:

```bash
~/.config/omarchy/plugins/io.mcmurray.freenet-explorer/bin/setup
```

If the file is not executable, run it with `bash` followed by the same path.

It writes `~/.config/systemd/user/freenet-explorer.service`, which runs the
explorer's `run.sh`, and reloads systemd. It does not enable or start the
unit. It needs no root access and does not download anything.

- `FREENET_EXPLORER_DIR` points it at a checkout other than
  `~/Development/freenet-explorer`.
- `bin/setup --check` reports what is present and changes nothing.
- `bin/setup --remove` stops and deletes the unit it wrote.

A unit file that this script did not write is never overwritten or removed.

Optionally, to start the explorer at login:

```bash
systemctl --user enable --now freenet-explorer
```

The popup's Start button does not need this.

"Open kept files" opens `~/.local/share/freenet-explorer/kept`, or
`$FREENET_EXPLORER_KEPT` when that variable is set in the shell's environment.
The explorer creates the folder on the first Keep.

## Freenet node

The explorer needs a Freenet node. The Linux install, from
https://freenet.org/quickstart/, is:

```bash
curl -fsSL https://freenet.org/install.sh | sh
```

This is information only: the plugin never runs it. The AUR package named
`freenet` is the old Java client and must not be used. When the installer's
`freenet.service` user unit is present, the popup offers "Start Freenet node".

For a server there is also a Docker image:
https://freenet.org/quickstart/docker/.

## IPC

```bash
omarchy-shell io.mcmurray.freenet-explorer start
omarchy-shell io.mcmurray.freenet-explorer stop
omarchy-shell io.mcmurray.freenet-explorer open
omarchy-shell io.mcmurray.freenet-explorer status
```

`status` prints one line:

```text
node=down explorer=stopped hosted=unknown
node=up explorer=stopped hosted=unknown
node=up explorer=running hosted=12
```

`hosted` is `unknown` unless the explorer reported a count.

`start`, `stop`, and `open` print `ok` or `error: …`. For `start` and `stop`,
`ok` means `systemctl` was launched; a later failure shows in the popup. `open`
opens the explorer UI and does not start the explorer.

To open the bar popup instead:

```bash
omarchy-shell shell summon io.mcmurray.freenet-explorer
```

## Launcher

While the plugin is enabled, its service keeps
`~/.local/share/applications/io.mcmurray.freenet-explorer.desktop`. "Freenet
Explorer" then appears in the SUPER+SPACE menu and the SUPER+ALT+SPACE app
grid. A file at that path that the plugin did not write is left alone.

## Example keybinding

Not installed by the plugin. To add one, put this in
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + F", "Freenet Explorer", "omarchy-shell io.mcmurray.freenet-explorer open")
```

## Uninstall

1. Remove the unit:

   ```bash
   ~/.config/omarchy/plugins/io.mcmurray.freenet-explorer/bin/setup --remove
   ```

2. Remove the plugin:

   ```bash
   omarchy plugin remove io.mcmurray.freenet-explorer
   ```

3. If the shell was not running during removal, delete
   `~/.local/share/applications/io.mcmurray.freenet-explorer.desktop` by hand.
4. The explorer's data under `~/.local/share/freenet-explorer/` is left alone.

## Security

The plugin must not weaken Freenet Explorer.

- It never listens on a port, never proxies 8787 or 7509, never changes the
  firewall, and never passes the explorer a port or bind address.
- Its only HTTP request to the explorer is a GET of
  `http://127.0.0.1:8787/api/summary` with the default Host header.
- It never calls the explorer endpoints that make the node act.
- It never shows contract bytes, HTML from the node, or kept-file contents. It
  shows a count and runs local commands.
- It does not read or write the explorer database. It only checks that the kept
  folder exists and opens it. The child-safety quarantine lives in that
  database and is left alone.
- Commands run as argument lists. Shell scripts are fixed text, and paths are
  passed to them as arguments.
- It never asks for root access or shows a permission prompt.
