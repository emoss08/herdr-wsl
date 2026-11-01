<#
.SYNOPSIS
  Make a WSL 2 distro a Herdr machine, so Herdr's spaces can run in Linux.

.DESCRIPTION
  Herdr's core on Windows reaches other machines over ssh, so the distro gets an
  ssh server that only this PC can reach:

    1. In the distro, as root (through `wsl -u root`): install an OpenSSH server
       (apt, dnf, zypper or pacman) and run it on 127.0.0.1:<Port> only, key
       login only.
    2. On Windows: a key for it, ~/.ssh/herdr_wsl_ed25519 (no passphrase, so
       Herdr connects unattended), authorized in the distro for connections
       from 127.0.0.1 only, and a `Host <Machine>` entry in ~/.ssh/config.
    3. `hc machine add <Machine> --install`: herdr-core inside the distro.
    4. Run from the herdr-wsl folder: installs its Herdr files (mods/wsl,
       mods/wsl-spaces, layouts/main-wsl.json, the ctrl-shift-n key), writes
       mods/wsl/config.json, checks the mods and switches to the layout.

  Steps already done are skipped; each other step is asked first unless -Yes.
  -Uninstall undoes them (the OpenSSH server stays installed in the distro).

.EXAMPLE
  .\setup.ps1
.EXAMPLE
  .\setup.ps1 -Distro Debian -Port 2223 -Yes
.EXAMPLE
  .\setup.ps1 -Uninstall
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "Yes", Justification = "Read by Ask, in script scope")]
[CmdletBinding()]
param(
  [string]$Distro,
  [int]$Port = 2222,
  [string]$Machine = "wsl",
  [switch]$Yes,
  [switch]$Uninstall
)

$env:WSL_UTF8 = "1" # wsl.exe prints UTF-8 instead of UTF-16
$KeyFile = Join-Path $HOME ".ssh\herdr_wsl_ed25519"
$SshConfig = Join-Path $HOME ".ssh\config"
$Begin = "# >>> herdr-wsl"
$End = "# <<< herdr-wsl"
$HerdrHome = if ($env:HERDR_APP_HOME) { $env:HERDR_APP_HOME } else { Join-Path $HOME ".config\herdr-app" }

function Say([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Note([string]$m) { Write-Host "    $m" -ForegroundColor DarkGray }
function Fail([string]$m) { Write-Host "error: $m" -ForegroundColor Red; exit 1 }
function Ask([string]$m) {
  if ($Yes) { return $true }
  $a = Read-Host "    $m [Y/n]"
  return ($a -eq "" -or $a -match '^[yY]')
}

# wsl.exe's output, NULs stripped in case WSL_UTF8 isn't honored (older WSL).
function Wsl([string[]]$WslArgs) {
  $out = & wsl.exe @WslArgs
  return ($out | ForEach-Object { $_.Replace([string][char]0, "").Replace([string][char]0xFEFF, "") })
}

# A Windows path as the distro sees it.
function ConvertTo-WslPath([string]$Path) {
  return (Wsl @("-d", $Distro, "--", "wslpath", "-a", ($Path -replace '\\', '/')) | Select-Object -First 1).Trim()
}

# Run a POSIX sh script in the distro (as root with -Root), from a temp file with LF endings.
function Invoke-DistroScript([string]$Script, [string[]]$ScriptArgs = @(), [switch]$Root) {
  $tmp = Join-Path $env:TEMP ("herdr-wsl-" + [guid]::NewGuid().ToString("n") + ".sh")
  [IO.File]::WriteAllText($tmp, $Script.Replace("`r`n", "`n"))
  try {
    $path = ConvertTo-WslPath $tmp
    $user = if ($Root) { @("-u", "root") } else { @() }
    # To the console, not the pipeline: callers get only the exit code back.
    & wsl.exe -d $Distro @user -- sh $path @ScriptArgs | Out-Host
    return $LASTEXITCODE
  } finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
  }
}

function Test-Ssh {
  & ssh.exe -o BatchMode=yes -o ConnectTimeout=5 $Machine true *> $null
  return ($LASTEXITCODE -eq 0)
}

function Find-Hc {
  $c = Get-Command hc -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $p = Join-Path $env:LOCALAPPDATA "Programs\herdr-core\hc.exe"
  if (Test-Path $p) { return $p }
  Fail "hc (herdr-core) not found. Install the Herdr app first: https://herdr.dev"
}

function Find-HerdrApp {
  $c = Get-Command herdr-app -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  $p = Join-Path $env:LOCALAPPDATA "Programs\herdr-app\herdr-app.exe"
  if (Test-Path $p) { return $p }
  return $null
}

$Src = $PSScriptRoot
$Mods = @("wsl", "wsl-spaces")
$KeySection = "layout:main-wsl"

# A mod folder there is ours (an earlier install) when its main.js says so.
function Test-OurMod([string]$Dir) {
  $js = Join-Path $Dir "main.js"
  return (Test-Path $js) -and (Select-String -Path $js -SimpleMatch "herdr-wsl" -Quiet)
}

# Copy one mod: mod.json first (a main.js Herdr sees without it is docked with
# default placement), the person's config.json kept. Returns what happened.
function Install-Mod([string]$Name) {
  $from = Join-Path $Src "mods\$Name"
  $to = Join-Path $HerdrHome "mods\$Name"
  if ((Test-Path $to) -and -not (Test-OurMod $to)) { Fail "mods/$Name exists and isn't herdr-wsl's. Rename it, then run setup.ps1 again." }
  $same = (Test-Path (Join-Path $to "main.js")) -and
    ((Get-FileHash (Join-Path $from "main.js")).Hash -eq (Get-FileHash (Join-Path $to "main.js")).Hash)
  if ($same) { return "up to date" }
  New-Item -ItemType Directory -Force $to | Out-Null
  Copy-Item (Join-Path $from "mod.json") $to -Force
  Get-ChildItem $from -File | Where-Object { $_.Name -ne "mod.json" } | Copy-Item -Destination $to -Force
  return "installed"
}

# Add the ctrl-shift-n section to keys.json as text, so the person's formatting stays.
# Nothing is written unless the result parses; a file that isn't plain JSON is left alone.
function Add-KeySection {
  $file = Join-Path $HerdrHome "keys.json"
  $section = "  `"$KeySection`": {`n    `"ctrl-shift-n`": `"wsl.new-space`"`n  }"
  $text = if (Test-Path $file) { [IO.File]::ReadAllText($file) } else { "" }
  if (-not $text.Trim()) { [IO.File]::WriteAllText($file, "{`n$section`n}`n"); return "created" }
  try {
    $keys = $text | ConvertFrom-Json -ErrorAction Stop
    if ($keys.PSObject.Properties.Name -contains $KeySection) { return "already there" }
    $body = $text.Substring(0, $text.LastIndexOf("}")).TrimEnd()
    $new = $body + $(if ($body.EndsWith("{")) { "" } else { "," }) + "`n$section`n}`n"
    $null = $new | ConvertFrom-Json -ErrorAction Stop
  } catch {
    if ($text -match ('"' + [regex]::Escape($KeySection) + '"\s*:')) { return "already there" }
    return "left alone (keys.json isn't plain JSON): add `"$KeySection`": { `"ctrl-shift-n`": `"wsl.new-space`" } yourself"
  }
  Copy-Item $file "$file.bak-herdr-wsl" -Force
  [IO.File]::WriteAllText($file, $new)
  return "added (backup: keys.json.bak-herdr-wsl)"
}

# Remove that section: with the comma before it, or (when it's first) the one after it.
function Remove-KeySection {
  $file = Join-Path $HerdrHome "keys.json"
  if (-not (Test-Path $file)) { return "no keys.json" }
  $text = [IO.File]::ReadAllText($file)
  $sec = '"' + [regex]::Escape($KeySection) + '"\s*:\s*\{[^{}]*\}'
  $new = [regex]::Replace($text, ',\s*' + $sec, "")
  if ($new -eq $text) { $new = [regex]::Replace($text, $sec + '\s*,?', "") }
  if ($new -eq $text) { return "no section" }
  try { $null = $new | ConvertFrom-Json -ErrorAction Stop }
  catch { return "left alone (the result wouldn't be valid JSON): remove `"$KeySection`" yourself" }
  [IO.File]::WriteAllText($file, $new)
  return "removed"
}

# The herdr-wsl Host blocks in ~/.ssh/config: machine, port and distro of each.
# (Blocks from 0.2.1 and earlier have no distro line: Distro is $null.)
function Get-HerdrBlock {
  $text = if (Test-Path $SshConfig) { [IO.File]::ReadAllText($SshConfig) } else { "" }
  $re = [regex]::Escape($Begin) + '\r?\nHost (\S+)\r?\n(.*?)' + [regex]::Escape($End)
  foreach ($m in [regex]::Matches($text, $re, "Singleline")) {
    $body = $m.Groups[2].Value
    [pscustomobject]@{
      Machine = $m.Groups[1].Value
      Port = if ($body -match '(?m)^\s*Port\s+(\d+)') { [int]$Matches[1] } else { 22 }
      Distro = if ($body -match '(?m)^\s*#\s*distro:\s*(\S+)') { $Matches[1] } else { $null }
    }
  }
}

# Drop this machine's herdr-wsl block (and its known_hosts line); other machines keep theirs.
function Remove-HostBlock([string]$Name, [int]$OldPort) {
  if (-not (Test-Path $SshConfig)) { return }
  $re = "(?s)\r?\n?" + [regex]::Escape($Begin) + "\r?\nHost " + [regex]::Escape($Name) + "\r?\n.*?" + [regex]::Escape($End) + "\r?\n?"
  $text = [IO.File]::ReadAllText($SshConfig)
  if (-not [regex]::IsMatch($text, $re)) { return }
  [IO.File]::WriteAllText($SshConfig, ([regex]::Replace($text, $re, "`n") -replace "(\r?\n){3,}", "`n`n"))
  & ssh-keygen.exe -R "[127.0.0.1]:$OldPort" *> $null
}

function Add-HostBlock([string]$User) {
  $block = @(
    "", $Begin,
    "Host $Machine",
    "  # distro: $Distro",
    "  HostName 127.0.0.1",
    "  Port $Port",
    "  User $User",
    "  IdentityFile ~/.ssh/herdr_wsl_ed25519",
    "  IdentitiesOnly yes",
    "  StrictHostKeyChecking accept-new",
    $End, ""
  ) -join "`n"
  [IO.File]::AppendAllText($SshConfig, $block)
}

# Merge keys into mods/wsl/config.json, keeping the person's own (redirect_local, ...).
function Set-ModConfig([hashtable]$Values) {
  $modDir = Join-Path $HerdrHome "mods\wsl"
  if (-not (Test-Path $modDir)) { return $null }
  $file = Join-Path $modDir "config.json"
  $cfg = [ordered]@{}
  if (Test-Path $file) {
    try { (Get-Content $file -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value } }
    catch { Note "mods/wsl/config.json wasn't valid JSON; writing a fresh one" }
  }
  foreach ($k in $Values.Keys) { $cfg[$k] = $Values[$k] }
  $json = [pscustomobject]$cfg | ConvertTo-Json -Compress
  [IO.File]::WriteAllText($file, $json + "`n")
  return $json
}

# Shared by the scripts below: the distro's sshd service name (ssh on Debian/Ubuntu).
$SvcLine = 'if systemctl cat ssh.service >/dev/null 2>&1; then svc=ssh; else svc=sshd; fi'

$SshdScript = @'
set -e
port="$1"
[ "$(cat /proc/1/comm)" = systemd ] || { echo "systemd is off in this distro: add [boot] systemd=true to /etc/wsl.conf, run 'wsl --shutdown', then run setup.ps1 again" >&2; exit 4; }
if [ ! -x /usr/sbin/sshd ] && [ ! -x /usr/bin/sshd ]; then
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq openssh-server
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q openssh-server
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive --quiet install openssh-server
  elif command -v pacman >/dev/null 2>&1; then
    # A distro never launched interactively has no pacman keyring yet.
    pacman-key --list-keys archlinux >/dev/null 2>&1 || { pacman-key --init && pacman-key --populate; }
    pacman -S --needed --noconfirm openssh || { pacman -Sy && pacman -S --needed --noconfirm openssh; }
  else
    echo "no apt, dnf, zypper or pacman here: install an OpenSSH server on 127.0.0.1:$port yourself, then run setup.ps1 again" >&2
    exit 3
  fi
fi
sshd=$(command -v sshd || echo /usr/sbin/sshd)
ssh-keygen -A >/dev/null
# The settings go in sshd_config.d/; make sure the main config reads it (openSUSE keeps
# its main config in /usr/etc, Arch's may lack the Include).
inc='^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/'
mkdir -p /etc/ssh/sshd_config.d
if [ -f /etc/ssh/sshd_config ]; then
  if ! grep -qE "$inc" /etc/ssh/sshd_config; then
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
    sed -i '1i # herdr-wsl: read sshd_config.d (setup.ps1)' /etc/ssh/sshd_config
  fi
elif ! grep -qsE "$inc" /usr/etc/ssh/sshd_config; then
  echo "neither /etc/ssh/sshd_config nor /usr/etc/ssh/sshd_config includes sshd_config.d/" >&2
  exit 5
fi
conf=/etc/ssh/sshd_config.d/herdr-wsl.conf
# ChallengeResponseAuthentication, not KbdInteractiveAuthentication: older OpenSSH knows only it.
want="# herdr-wsl: this distro as a Herdr machine, reachable from Windows only
Port $port
ListenAddress 127.0.0.1
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes"
changed=
if [ "$(cat "$conf" 2>/dev/null)" != "$want" ]; then printf '%s\n' "$want" > "$conf"; changed=1; fi
# Debian/Ubuntu's sshd won't even check its config before the service has made /run/sshd.
mkdir -p /run/sshd && chmod 755 /run/sshd
"$sshd" -t || { rm -f "$conf"; echo "sshd rejected the config; removed $conf" >&2; exit 6; }
@SVC@
# Ubuntu 22.10+ starts sshd from ssh.socket by default; run the plain service instead.
systemctl disable --now "$svc.socket" >/dev/null 2>&1 || true
systemctl enable "$svc" >/dev/null 2>&1
if [ -n "$changed" ] || ! systemctl is-active -q "$svc"; then systemctl restart "$svc"; fi
sleep 1
systemctl is-active -q "$svc" || { echo "$svc did not start: journalctl -u $svc" >&2; exit 7; }
if command -v ss >/dev/null 2>&1; then
  ss -ltn | grep -q "127.0.0.1:$port " || { echo "sshd is not listening on 127.0.0.1:$port" >&2; exit 8; }
fi
'@.Replace("@SVC@", $SvcLine)

# The key may log in only from this PC (loopback); a key already there gets the restriction.
$AuthorizeScript = @'
set -e
key=$(tr -d '\r' < "$1")
body=$(printf '%s\n' "$key" | cut -d' ' -f2) # cut, not awk: Fedora's WSL image has no awk
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
line="from=\"127.0.0.1,::1\" $key"
grep -qxF "$line" ~/.ssh/authorized_keys && exit 0
grep -vF "$body" ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.herdr-wsl || true
printf '%s\n' "$line" >> ~/.ssh/authorized_keys.herdr-wsl
mv ~/.ssh/authorized_keys.herdr-wsl ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
'@

$UnsshdScript = @'
rm -f /etc/ssh/sshd_config.d/herdr-wsl.conf
[ -f /etc/ssh/sshd_config ] && sed -i '/^# herdr-wsl: read sshd_config.d/{N;d}' /etc/ssh/sshd_config
@SVC@
systemctl disable --now "$svc" "$svc.socket" >/dev/null 2>&1 || true
'@.Replace("@SVC@", $SvcLine)

$UnauthorizeScript = @'
[ -f ~/.ssh/authorized_keys ] && sed -i '/ herdr-wsl$/d' ~/.ssh/authorized_keys || true
'@

# ---------------------------------------------------------------- the distro

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Fail "WSL isn't installed (wsl --install)." }
$Blocks = @(Get-HerdrBlock)
$Ours = $Blocks | Where-Object { $_.Machine -eq $Machine } | Select-Object -First 1
# Uninstall acts on the distro and port this machine was set up with, not the defaults.
if ($Uninstall -and $Ours) {
  if (-not $PSBoundParameters.ContainsKey("Port")) { $Port = $Ours.Port }
  if (-not $PSBoundParameters.ContainsKey("Distro")) {
    if ($Ours.Distro) { $Distro = $Ours.Distro }
    elseif ($Blocks.Count -gt 1) { Fail "The 'Host $Machine' entry predates 0.2.2 and doesn't record its distro, and other herdr-wsl machines exist. Pass -Distro <name>." }
  }
}
$rows = Wsl @("-l", "-v") | Where-Object { $_.Trim() } | Select-Object -Skip 1
$cols = { param($r) ($r.Trim().TrimStart("*").Trim()) -split '\s+' }
if (-not $Distro) {
  $def = $rows | Where-Object { $_.Trim().StartsWith("*") } | Select-Object -First 1
  if (-not $def) { Fail "No default WSL distro. Pass -Distro <name> (wsl -l -v lists them)." }
  $Distro = (& $cols $def)[0]
}
$row = $rows | Where-Object { (& $cols $_)[0] -eq $Distro } | Select-Object -First 1
if (-not $row) { Fail "No WSL distro named '$Distro' (wsl -l -v lists them)." }
if ((& $cols $row)[-1] -ne "2") { Fail "'$Distro' is WSL 1; convert it with: wsl --set-version $Distro 2" }
$hc = Find-Hc
Say "Distro $Distro, machine '$Machine', sshd on 127.0.0.1:$Port"

# ---------------------------------------------------------------- uninstall

if ($Uninstall) {
  $known = (& $hc machine ls --json | ConvertFrom-Json).machines | Where-Object { $_.name -eq $Machine }
  if ($known -and (Ask "Remove the Herdr machine '$Machine'? Its spaces close.")) {
    & $hc machine rm $Machine | Out-Null
    Note "removed machine $Machine"
  }
  if (Ask "Stop and disable sshd in $Distro, and remove its herdr-wsl config?") {
    Invoke-DistroScript $UnsshdScript -Root | Out-Null
    Note "sshd stopped; the OpenSSH server stays installed"
  }
  if ($Ours -and (Ask "Remove the herdr-wsl 'Host $Machine' entry from ~/.ssh/config?")) {
    Remove-HostBlock $Machine $Port
    Note "removed Host $Machine and its known_hosts line"
  }
  # Other distros set up the same way keep their entries, the key and the mods.
  $others = @(Get-HerdrBlock)
  if ((Test-Path "$KeyFile.pub") -and (Ask "Unauthorize the herdr-wsl key in $($Distro)?")) {
    Invoke-DistroScript $UnauthorizeScript | Out-Null
    if (-not $others) {
      Remove-Item "$KeyFile", "$KeyFile.pub" -ErrorAction SilentlyContinue
      Note "key unauthorized and deleted"
    } else {
      Note "key unauthorized here; kept for your other herdr-wsl machines"
    }
  }
  $installed = $Mods | Where-Object { Test-OurMod (Join-Path $HerdrHome "mods\$_") }
  $layout = Join-Path $HerdrHome "layouts\main-wsl.json"
  if ($others) {
    # The mods may still point at this machine (the last one set up): move them to one that stays.
    $cfgFile = Join-Path $HerdrHome "mods\wsl\config.json"
    $cfg = $null
    if (Test-Path $cfgFile) { try { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $cfg = $null } }
    if (-not $cfg -or $cfg.machine -eq $Machine) {
      $next = $others[0]
      $json = Set-ModConfig @{ machine = $next.Machine; distro = $next.Distro }
      if ($json) { Note "mods/wsl/config.json now points at '$($next.Machine)': $json" }
    }
    Note "other herdr-wsl machines remain; mods and layout kept"
  } elseif (($installed -or (Test-Path $layout)) -and (Ask "Remove the herdr-wsl mods, the main-wsl layout and its key?")) {
    $app = Find-HerdrApp
    if ($app) { & $app do layout.switch --name main *> $null }
    foreach ($m in $installed) { Remove-Item (Join-Path $HerdrHome "mods\$m") -Recurse -Force }
    Remove-Item $layout, (Join-Path $HerdrHome "layouts\main-wsl.png") -ErrorAction SilentlyContinue
    Note ("keys.json ${KeySection}: {0}" -f (Remove-KeySection))
    Note "removed; the window is on Herdr's main layout"
  } else {
    Remove-Item (Join-Path $HerdrHome "mods\wsl\config.json") -ErrorAction SilentlyContinue
  }
  Say "Done."
  exit 0
}

# ---------------------------------------------------------------- 1. sshd

Say "1/4 sshd in $Distro"
if (Ask "Install/configure an OpenSSH server in $Distro as root, listening on 127.0.0.1:$Port, keys only?") {
  $code = Invoke-DistroScript $SshdScript @("$Port") -Root
  if ($code -ne 0) { Fail "sshd setup in $Distro failed (exit $code)." }
  Note "sshd listening on 127.0.0.1:$Port"
} else { Fail "Herdr needs an ssh server in the distro; stopped." }

# ---------------------------------------------------------------- 2. key and Host entry

Say "2/4 ssh from Windows"
if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
  Fail "The Windows OpenSSH client is missing (Settings > System > Optional features > OpenSSH Client)."
}
# Our own block for this machine is rewritten when it names another port or distro (a
# re-run with -Port after a port clash) or predates the distro line.
$stale = $Ours -and ($Ours.Port -ne $Port -or $Ours.Distro -ne $Distro)
if (-not $stale -and (Test-Ssh)) {
  Note "'ssh $Machine' already works; Host entry left as it is"
  # A key from an earlier setup gets the from-loopback restriction.
  if (Test-Path "$KeyFile.pub") { Invoke-DistroScript $AuthorizeScript @(ConvertTo-WslPath "$KeyFile.pub") | Out-Null }
} else {
  $hasHost = (Test-Path $SshConfig) -and (Select-String -Path $SshConfig -Pattern "^\s*Host\s+(.*\s)?$([regex]::Escape($Machine))(\s|$)" -Quiet)
  if ($hasHost -and -not $Ours) {
    Fail "~/.ssh/config already has a 'Host $Machine' that doesn't connect. Fix or rename it, or pass -Machine <other name>."
  }
  $what = if ($stale) { "update 'Host $Machine' in ~/.ssh/config (port $Port, distro $Distro)" } else { "add 'Host $Machine' to ~/.ssh/config" }
  if (-not (Ask "Use ~/.ssh/herdr_wsl_ed25519 (no passphrase; made if missing), authorize it in $Distro (from this PC only) and $($what)?")) {
    Fail "Herdr needs to reach the distro over ssh; stopped."
  }
  New-Item -ItemType Directory -Force (Split-Path $KeyFile) | Out-Null
  if (-not (Test-Path $KeyFile)) {
    # PowerShell before 7.3 drops "" when calling programs; '""' reaches them as an empty argument.
    $empty = if ($PSVersionTable.PSVersion -ge [version]"7.3") { "" } else { '""' }
    & ssh-keygen.exe -q -t ed25519 -N $empty -C "herdr-wsl" -f $KeyFile
    if ($LASTEXITCODE -ne 0) { Fail "ssh-keygen failed." }
  }
  if ((Invoke-DistroScript $AuthorizeScript @(ConvertTo-WslPath "$KeyFile.pub")) -ne 0) { Fail "Couldn't authorize the key in $Distro." }
  $user = (Wsl @("-d", $Distro, "--", "whoami") | Select-Object -First 1).Trim()
  if ($Ours) { Remove-HostBlock $Machine $Ours.Port }
  Add-HostBlock $user
  if (-not (Test-Ssh)) { Fail "'ssh $Machine' still doesn't connect. Is port $Port taken on Windows? Try -Port <other>." }
  Note "'ssh $Machine' connects as $user"
}

# ---------------------------------------------------------------- 3. Herdr machine

Say "3/4 Herdr machine"
$known = (& $hc machine ls --json | ConvertFrom-Json).machines | Where-Object { $_.name -eq $Machine }
if ($known) {
  Note "machine '$Machine' already added ($($known.state))"
} elseif (Ask "Add '$Machine' as a Herdr machine (copies hc into $Distro)?") {
  & $hc machine add $Machine --name $Machine --install --json | Out-Null
  if ($LASTEXITCODE -ne 0) { Fail "hc machine add failed." }
  Note "machine '$Machine' added"
} else { Fail "Stopped before adding the machine." }

# ---------------------------------------------------------------- 4. Herdr files

Say "4/4 Herdr: mods, layout, key"
$app = Find-HerdrApp
if (Test-Path (Join-Path $Src "mods\wsl\main.js")) {
  if (Ask "Install the wsl and wsl-spaces mods, the main-wsl layout and ctrl-shift-n into $($HerdrHome)?") {
    foreach ($m in $Mods) { Note ("mods/{0}: {1}" -f $m, (Install-Mod $m)) }
    $layout = Join-Path $HerdrHome "layouts\main-wsl.json"
    if (Test-Path $layout) {
      Note "layouts/main-wsl.json: kept (yours, with your clicks)"
    } else {
      # The folder first: Copy-Item to a missing folder makes a file of that name.
      try {
        New-Item -ItemType Directory -Force (Join-Path $HerdrHome "layouts") -ErrorAction Stop | Out-Null
        Copy-Item (Join-Path $Src "layouts\main-wsl.png") (Join-Path $HerdrHome "layouts\main-wsl.png") -Force -ErrorAction Stop
        Copy-Item (Join-Path $Src "layouts\main-wsl.json") $layout -ErrorAction Stop
        Note "layouts/main-wsl.json: installed"
      } catch { Fail "couldn't install layouts/main-wsl.json: $($_.Exception.Message)" }
    }
    Note ("keys.json ${KeySection}: {0}" -f (Add-KeySection))
  }
} else {
  Note "run from the herdr-wsl folder to install the mods and layout; skipping"
}
$json = Set-ModConfig @{ machine = $Machine; distro = $Distro }
if ($json) { Note "mods/wsl/config.json: $json" }
if ($app) {
  foreach ($m in $Mods) {
    $dir = Join-Path $HerdrHome "mods\$m"
    if (-not (Test-Path $dir)) { continue }
    & $app check $dir *> $null
    if ($LASTEXITCODE -ne 0) { Fail "herdr-app check mods/$m failed: run 'herdr-app check $dir' to see why." }
    Note "mods/${m}: check passed"
  }
  if ((Test-Path (Join-Path $HerdrHome "layouts\main-wsl.json")) -and (Ask "Switch Herdr to the main-wsl layout now?")) {
    & $app do layout.switch --name main-wsl *> $null
    if ($LASTEXITCODE -eq 0) { Note "switched (ctrl-shift-l cycles layouts)" } else { Note "Herdr isn't running; pick main-wsl in Settings > Look later" }
  }
}

Say "Done. In Herdr: the + on the WSL row or in Spaces, or ctrl-shift-n."
