# Freenet Explorer for Omarchy

Omarchy shell plugin `io.mcmurray.freenet-explorer`. A bar glyph and popup
for the local [Freenet Explorer](https://github.com/) checkout at
`~/Development/freenet-explorer`, which serves http://127.0.0.1:8787/.

This checkout is a stub. The implementation contract is
[docs/PLUGIN-CONTRACT.md](docs/PLUGIN-CONTRACT.md). The README sections
below are the ones the finished plugin must fill in. They are empty on
purpose until that work lands.

## Install

Not written yet.

## One-time setup

Not written yet. Plugins cannot ship a systemd unit. `bin/setup` will be
that step.

## IPC

Not written yet. Planned calls:

```bash
omarchy-shell io.mcmurray.freenet-explorer start
omarchy-shell io.mcmurray.freenet-explorer stop
omarchy-shell io.mcmurray.freenet-explorer open
omarchy-shell io.mcmurray.freenet-explorer status
```

## Example keybinding

Not installed. The finished README will show a `bindings.lua` example.

## Uninstall

Not written yet. `omarchy plugin remove` deletes the checkout only.
Anything `bin/setup` wrote has its own removal step.

## Security

The plugin must not weaken Freenet Explorer: localhost only, no firewall
changes, no proxy, no extra explorer endpoints. Details are in the contract.
