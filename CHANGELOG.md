# Changelog

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
