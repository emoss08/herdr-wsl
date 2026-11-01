# WSL

Herdr on Windows, working in Linux. Your WSL 2 distro becomes a Herdr machine and
the place spaces go: a new space runs your Linux shell, git and agents natively,
and Herdr follows its Linux folders (new tabs, the Files and Changes panels, git
status). The sidebar's "This computer" group disappears while it has no spaces,
the Spaces `+` and a WSL row open WSL spaces, and the row shows whether WSL is
connected and reconnects it when it isn't.

![WSL](preview.png)

## What you see

The `main-wsl` layout: Herdr's own `main` layout with two changes in the sidebar.

- **Spaces** (`wsl-spaces`, Herdr's spaces list with two changes): spaces grouped by
  machine as usual, but no "This computer" group while this computer has no spaces.
  The header's `+` makes a space on WSL.
- **The WSL row**, 34px tall, between the agents list and Settings / Add machine, on
  the sidebar's `chrome` background, 12.5px text, 14px side padding, 8px gaps:
  - a 7px round status dot,
  - "WSL" in `foreground`,
  - the distro and the connection, truncated: `Ubuntu · connected` in `dim`
    (`blocked` while offline),
  - at the right end, `+` while connected or `↻` while offline (15px, `muted`,
    `hover` background and `foreground` on hover).
- When the sidebar is folded to a rail (narrower than 160px): only the dot, centered,
  in a 6px-padded hover target.
- Tooltips: "New WSL space"; while offline, "Offline: <hc's reason>. Click to
  reconnect."; "Connecting to WSL…"; before setup, "Run setup.ps1 from the herdr-wsl
  folder".

## How it behaves

- The dot and word follow Herdr's view of the machine (`machines()[].layout`):
  `ready` → `ansi2` "connected", `loading` → `ansi3` "connecting", `unavailable` →
  `blocked` "offline". With no such machine: "not set up: run setup.ps1" in `dim`, no
  button.
- Connected: the row's `+`, the Spaces `+` and `ctrl-shift-n` (in this layout) run
  `space.new {machine: "wsl"}`, a space whose terminal is the distro's login shell in
  your Linux home.
- Offline: clicking the word or `↻` (or `wsl.reconnect`) starts the distro and makes
  hc dial the machine at once. The mod also does this by itself every 15s while the
  machine is offline.
- It keeps the distro running: WSL stops a distro with no Windows-side session after a
  short idle, which would take the machine offline. One hidden local hc terminal,
  `wsl-keepalive`, runs `wsl.exe -d <distro> -- sleep infinity`; it is checked every
  5s and started again if it ended (after `wsl --shutdown`, say). No Herdr labels, so
  it shows in no space.
- `"redirect_local": true` in `mods/wsl/config.json` (off by default): a space made
  on this computer that is still a bare shell 2.5s later (the palette's New space,
  Herdr's own `ctrl-shift-n` elsewhere) is closed and a WSL space opens instead.
  Spaces that start an agent or a program, and those already there when the mod
  starts, are left alone. Only while WSL is connected.
- "This computer" comes back as soon as a local space exists, so nothing is hidden
  that is still running.
- Agent statuses (working, blocked, done, idle) are Herdr's own: agents in WSL spaces
  show in the agents list like local ones.

## Built from

- **`setup.ps1`** (Windows PowerShell 5.1 or PowerShell 7) does everything, asking
  before each step (`-Yes`: don't ask). Herdr's core on Windows reaches other machines
  only over ssh: `hc machine add --via <command>` is refused there ("one line, run by
  sh here"; herdr-app#172). So:
  1. in the distro, as root through `wsl -u root` (no password): installs an OpenSSH
     server (apt, dnf, zypper or pacman), runs `ssh-keygen -A`, makes sure the main
     config includes `sshd_config.d/` (openSUSE keeps it in `/usr/etc/ssh`; Arch's may
     lack the Include, which is added with a `# herdr-wsl` line), writes
     `/etc/ssh/sshd_config.d/herdr-wsl.conf` (`Port 2222`, `ListenAddress 127.0.0.1`,
     `PasswordAuthentication no`, `ChallengeResponseAuthentication no`), validates
     with `sshd -t`, disables `<svc>.socket` and enables/restarts `<svc>` (`ssh` on
     Debian/Ubuntu, `sshd` elsewhere);
  2. on Windows: makes `~/.ssh/herdr_wsl_ed25519` (ed25519, no passphrase, comment
     `herdr-wsl`), adds it to the distro user's `authorized_keys` as
     `from="127.0.0.1,::1" ssh-ed25519 … herdr-wsl`, and appends a `Host wsl` entry
     (127.0.0.1, port, user, that key, `IdentitiesOnly yes`,
     `StrictHostKeyChecking accept-new`) between `# >>> herdr-wsl` / `# <<< herdr-wsl`;
  3. `hc machine add wsl --name wsl --install` (copies hc into the distro);
  4. from the repo folder: copies `mods/wsl` and `mods/wsl-spaces` (each `mod.json`
     first), `layouts/main-wsl.json` (+ `.png`) unless one exists, adds the
     `layout:main-wsl` section to `keys.json` as text (backup
     `keys.json.bak-herdr-wsl`), merges `{machine, distro}` into `mods/wsl/config.json`,
     runs `herdr-app check` on both mods and `layout.switch main-wsl`.
  Options: `-Distro` (default: WSL's default), `-Port` (2222), `-Machine` (`wsl`),
  `-Uninstall` (only that machine's Host entry; the key and the Herdr files go with
  the last machine). Steps already done are skipped; a key from an earlier setup gets
  the `from=` restriction.
- **`layouts/main-wsl.json`**: a clone of Herdr's `main` (0.1.11). The `spaces` block's
  mod is `wsl-spaces`; a block between `sidebar-lists` and `sidebar-footer`:
  `{ "id": "wsl", "type": "block", "content": { "mod": "wsl" }, "size": { "px": 34 } }`;
  root `"preview": "layouts/main-wsl.png"`.
- **`mods/wsl`** (`place: "none"`): reads `config.json` (`machine`, `distro`,
  `redirect_local`) with `readTextFile(appHome() + "/mods/wsl/config.json")`; without
  a distro, the `*` row of `wsl.exe -l -v` (UTF-16: strip NULs and the BOM). Uses
  `machines()`, `spaces()`, `panes()`, `terminals()`, `run("space.new")`,
  `run("space.close", {confirmed: true})`, `nextCommand()` (`new-space`,
  `reconnect`), `hc(["run", …])` for the keepalive, `hc(["exec", "--on", machine,
  "true"])` to make hc dial, `hc(["machine", "ls", "--json"])` for `why`,
  `cx.timer.every(5000)` (health) and `every(1000)` + `after(2500)` (redirect).
- **`mods/wsl-spaces`**: `mod.clone` of Herdr's `spaces` (Apache-2.0, its LICENSE
  alongside), changes marked `herdr-wsl:` — `machineNames` leaves out `null` when no
  row is local; the header `+` runs `space.new {machine}` with the machine from
  `mods/wsl/config.json`.
- Programs: `wsl.exe`, `hc`. No network access.

## Watch out

- If `main.js` is saved before `mod.json` exists, Herdr docks the mod with default
  placement (a 320px column on the right). Write `mod.json` first.
- The mods only run (and keep WSL alive) in layouts that contain them; `<mod>.<command>`
  keys reach shown copies only. On Herdr's own `main` layout WSL may idle out.
- `hc machine login` can't be used to reconnect from a mod: it needs a terminal. The
  mod sends a no-op `hc exec --on <machine> true` instead; hc also retries on its
  own, and it hasn't been measured which of the two wins.
- Tested with NAT and mirrored networking (`networkingMode=mirrored`): loopback
  reaches the distro's 127.0.0.1 and passes the key's `from=` in both.
- `hc connect` (JSON-RPC on stdin) answered every request with `parse_error` here; not
  used.
- Ubuntu 22.10+ starts sshd from `ssh.socket`; the script runs `ssh.service`. sshd
  comes back on its own after `wsl --terminate`.
- All WSL 2 distros share one network: each set-up distro needs its own `-Port` and
  `-Machine`. A port taken on Windows breaks localhost forwarding; the script says so.
- Distros need systemd (`[boot] systemd=true` in `/etc/wsl.conf`; the default on
  current Ubuntu, Fedora, openSUSE and Arch images). The script stops and says how.
- PowerShell 5.1 gotchas handled in the script: `` "`uFEFF" `` isn't an escape there
  (use `'﻿'` in regex); `""` isn't passed to programs before PowerShell 7.3
  (`'""'` for `ssh-keygen -N`); `\"` in arguments differs between 5.1 and 7.3+
  (use `herdr-app do <cmd> --name x`); `wsl.exe -- '<line>'` passes the line as one
  word (scripts go through a temp file and `wslpath`); a FileInfo stringifies to its
  bare name in 5.1 (use `.FullName`).
- The key has no passphrase so Herdr connects unattended; `from=` and sshd's
  `ListenAddress` keep it to this PC.

## Done when

- `setup.ps1` finishes with `ssh wsl` connecting without a prompt, `hc machine ls`
  showing `wsl` connected, both mods passing `herdr-app check`, and Herdr on
  `main-wsl`; running it again changes nothing.
- The sidebar shows no "This computer" (with no local spaces), and the WSL row reads
  `Ubuntu · connected` with a green dot.
- The row's `+` and the Spaces `+` open a space under `wsl` in `/home/<user>`.
- With `redirect_local`, `herdr-app do space.new` ends up as a WSL space within ~3s,
  while `space.new {argv: ["claude"]}` stays local.
- After `wsl --shutdown` a new `wsl-keepalive` starts and the machine is connected
  again without a click (about 20–30s here, NAT and mirrored networking alike).
- `setup.ps1 -Uninstall` removes that machine, its Host entry and known_hosts line,
  its authorized key, stops sshd, and (last machine) the key and the Herdr files.
