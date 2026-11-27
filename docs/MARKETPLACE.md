# Marketplace listing

Not submitted. The public repository is https://github.com/imcmurray/omarchy-freenet-explorer. No listing issue has been opened. Do not file this until the owner has said to submit.

Intended repository: `https://github.com/imcmurray/omarchy-freenet-explorer`

Updates after the first listing use the marketplace verify form, not a second `[Plugin]:` issue.

## Listing metadata

- **Title:** `[Plugin]: omarchy-freenet-explorer`
- **Repository URL:** `https://github.com/imcmurray/omarchy-freenet-explorer`
- **Category:** `System`
- **Tags:** `bar`, `quickshell`, `system`
- **Preview:** root `preview.png` (the marketplace generates the card and detail sizes)

Category and tags are a suggestion. The form's categories are Appearance, Desktop, Developer Tools, Hardware, Kids, Productivity, System, Widgets, and Other. Tags are one to three of: ai, bar, education, games, hyprland, kids, launcher, media, power-management, quickshell, security, system, vpn, workspaces.

## Issue body

```markdown
### Repository URL

https://github.com/imcmurray/omarchy-freenet-explorer

### Category

System

### Tags

bar, quickshell, system

### Suggest a missing tag

_No response_

### Maintainer notes

Bar entry point for the local Rust Freenet peer (127.0.0.1:7509), the apps that peer lists, Aegis when `~/.config/freenet/aegis-web.path` holds its web-container path, and Freenet Explorer (127.0.0.1:8787). Plugin id `io.mcmurray.freenet-explorer`. The displayed name is Freenet. MIT. The panel reads the node's own dashboard only while it is open, and the explorer's GET /api/summary. It does not install packages, run the Freenet installer, publish a site, register the Aegis vault delegate, listen, proxy, or change the firewall. Browser opens stay on those two localhost origins. "Start Freenet node" starts the official user unit only, and only when that unit exists. One-time `bin/setup` writes a marked user unit for the explorer and will not overwrite an unmanaged unit. External dependencies: the Rust Freenet node, a Freenet Explorer checkout, and curl/systemctl which Omarchy already provides. The AUR package named freenet is the old Java client and is not used. The preview uses a sample peer id and 203.0.113.10.

### Submission checklist

- [ ] The repository is public and contains installation and removal instructions.
- [ ] I have documented the plugin license and any external dependencies.
- [ ] I confirm that I own or have permission to submit this plugin and its preview assets.
- [ ] The plugin does not overwrite user configuration without explicit consent.
- [ ] I understand that approval is for listing and is not a security review.
```

The license and the external dependencies are documented in the README. Install and removal instructions are there too. The ownership line is the owner's to confirm. The plugin writes a desktop file and, when the user runs `bin/setup`, a marked user unit. It refuses a symlink or an unmanaged file at those paths. It does not edit Hyprland or shell config.

## What review will still flag

These are not automatic rejections. They match the review of the other plugins in this account.

- `io.mcmurray.freenet-explorer` is not in the marketplace registry. `ianm.aegis` is, under a different id, so this id does not collide.
- The automated baseline treats a `bash` fence in the README as a script. The official Freenet install command is in a `text` fence, and the plugin does not run it. The panel still shows that command when no node is installed.
- `systemctl` and `bin/setup` will show up as service-management and installer capabilities. That asks for a maintainer look. The unit file is user-level, marked, and left alone when it was not written by this script.
- The summary fetch is capped at 64 KiB. The dashboard fetch is capped at 256 KiB. Contract tiles use a built-in mark or a monogram. The plugin does not download a contract icon body. The Aegis path file read is capped at 512 bytes. The node binary check looks only at `~/.local/bin/freenet`, `/usr/local/bin/freenet`, and `/usr/bin/freenet`.
- `preview.png` is a 471×563 crop with a sample peer id and `203.0.113.10`. `aegis.svg` has to be in the same commit as `Panel.qml`, or the Aegis tile has no icon.
- Publish one commit and leave that branch head still. A later commit invalidates the review, which is what happened on Aegis.

## Command

Only after the owner has approved this text and the repository is public:

```bash
gh issue create \
  --repo omacom/omarchy-plugin-marketplace \
  --title "[Plugin]: omarchy-freenet-explorer" \
  --body-file /tmp/omarchy-freenet-explorer-listing.md
```

Use the issue body section only, not this whole file. Every listing needs a fresh scan of the exact commit that was pushed.
