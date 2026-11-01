# Changelog

## 0.2.3

- Three prompts showed an empty name: PowerShell reads `"$Distro?"` as a variable called `Distro?`. They use `"$($Distro)?"` now.
- `Get-HerdrBlocks` is `Get-HerdrBlock` (PSScriptAnalyzer: singular nouns).

## 0.2.2

- **Fresh Ubuntu/Debian installs work again.** `sshd -t` (added in 0.2.0) failed
  before the ssh service had ever run, because `/run/sshd` didn't exist yet.
- **Re-running with `-Port`** (the fix the script suggests for a port clash) now
  rewrites the machine's Host entry instead of keeping the old port.
- **Uninstall acts on the right distro.** Host entries record their distro, and
  `-Uninstall` reads the distro and port back instead of using the defaults. The mod
  config is pointed at a remaining machine.
- **keys.json is never written broken.** Each step stops on error; an empty file is
  treated as new; a file with comments is left alone; removing the section when it
  comes first no longer leaves a stray comma.
- The layouts folder is created before the layout is copied.
- Mods: the redirect checks WSL is still connected before closing a local space; the
  Spaces `+` falls back to this computer while WSL is offline or missing; an unknown
  machine state no longer breaks the WSL row; the keepalive can't be launched twice
  at once.
## 0.2.1

- setup.ps1 is pure ASCII: Windows PowerShell 5.1 reads BOM-less files as ANSI, which garbled the BOM-stripping in distro detection.
- A broken mods/wsl/config.json is reported, then rewritten.

## 0.2.0

- **WSL is where spaces go.** `wsl-spaces` (Herdr's spaces list, changed) hides an
  empty "This computer" group and sends the Spaces `+` to WSL. Opt-in
  `redirect_local` swaps plain Windows shell spaces for WSL spaces.
- **One-step install.** `setup.ps1` run from this folder also installs the mods, the
  `main-wsl` layout and the key, checks the mods and switches the layout.
- **Recovery.** The WSL row reconnects the machine on its own while it's offline
  (every 15s), or on a click; its tooltip shows hc's reason. The keepalive is checked
  every 5s.
- **More distros.** dnf (Fedora), zypper (openSUSE) and pacman (Arch) besides apt;
  openSUSE's `/usr/etc` sshd config; a fresh Arch keyring; Fedora's image without awk.
  The sshd config is validated with `sshd -t` before restarting.
- **Tighter key.** Authorized with `from="127.0.0.1,::1"`; earlier setups are upgraded
  on the next run.
- **Several distros at once.** `-Uninstall` removes only that machine's Host entry;
  the key and the Herdr files go with the last one.
- CI: PSScriptAnalyzer, PowerShell 5.1/7 parse, JSON and module syntax checks.

## 0.1.0

- First release: `setup.ps1` (sshd on 127.0.0.1, key, Host entry, `hc machine add`)
  and the WSL row mod with its keepalive.
