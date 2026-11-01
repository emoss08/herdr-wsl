# herdr-wsl

A [Herdr](https://herdr.dev) mod for Windows: spaces that run in **WSL 2**.

Your distro becomes a Herdr machine, so a space there runs your Linux shell,
git and agents natively, and Herdr follows your Linux folders. A row in the
sidebar shows the connection and opens a new WSL space with one click.

![WSL](preview.png)

## Install

Ask your agent: *"Add the Herdr mod at github.com/emoss08/herdr-wsl"*. It
follows [`RECIPE.md`](RECIPE.md). Or by hand:

1. Run the one-time setup from this folder (it asks before each step):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   Options: `-Distro <name>`, `-Port 2222`, `-Machine wsl`, `-Yes`, `-Uninstall`.

2. Copy `mods/wsl` to `~/.config/herdr-app/mods/` (`mod.json` first).

3. Give it a place: clone a layout and add the block to its sidebar, between
   `sidebar-lists` and `sidebar-footer`:

   ```powershell
   herdr-app do layout.clone '{\"name\":\"main\",\"as\":\"main-wsl\"}'
   ```

   ```json
   { "id": "wsl", "type": "block", "content": { "mod": "wsl" }, "size": { "px": 34 } }
   ```

4. Optional: merge `keys.json` into `~/.config/herdr-app/keys.json` for
   `ctrl-shift-n` → new WSL space.

5. `herdr-app check ~/.config/herdr-app/mods/wsl`

## What the setup changes

Herdr's core on Windows reaches other machines only over ssh, so:

- **In the distro** (as root, via `wsl -u root`): installs `openssh-server`,
  listening on **127.0.0.1 only**, **key login only**
  (`/etc/ssh/sshd_config.d/herdr-wsl.conf`).
- **On Windows:** creates `~/.ssh/herdr_wsl_ed25519` (no passphrase, so Herdr
  connects unattended), authorizes it in the distro, and adds a marked
  `Host wsl` block to `~/.ssh/config`.
- Runs `hc machine add wsl --install`, which copies herdr-core into the distro.

The mod itself runs `wsl.exe` and `hc` only: it keeps one hidden
`wsl.exe -- sleep infinity` session open so WSL doesn't stop the idle distro.

`setup.ps1 -Uninstall` undoes all of it (openssh-server stays installed).

## Requirements

Herdr app with herdr-core, WSL 2, an apt distro (Ubuntu, Debian) with systemd,
the Windows OpenSSH client. Tested on herdr-app 0.1.11 / hc 0.1.16, WSL 3.0.3,
Ubuntu 24.04 and 26.04.

## License

MIT
