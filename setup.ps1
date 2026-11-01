<#
.SYNOPSIS
  Make a WSL 2 distro a Herdr machine, so Herdr's spaces can run in Linux.

.DESCRIPTION
  Herdr's core on Windows reaches other machines over ssh, so the distro gets an
  ssh server that only this PC can reach:

    1. In the distro, as root (through `wsl -u root`): install openssh-server
       (apt) and run it on 127.0.0.1:<Port> only, key login only.
    2. On Windows: a key for it, ~/.ssh/herdr_wsl_ed25519 (no passphrase, so
       Herdr connects unattended), authorized in the distro, and a
       `Host <Machine>` entry in ~/.ssh/config.
    3. `hc machine add <Machine> --install`: herdr-core inside the distro.
    4. mods/wsl/config.json, so the wsl mod keeps that distro running.

  Steps already done are skipped; each other step is asked first unless -Yes.
  -Uninstall undoes them (openssh-server stays installed in the distro).

.EXAMPLE
  .\setup.ps1
.EXAMPLE
  .\setup.ps1 -Distro Debian -Port 2223 -Yes
.EXAMPLE
  .\setup.ps1 -Uninstall
#>
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
  return ($out | ForEach-Object { $_ -replace '[\x00﻿]', '' })
}

# Run a POSIX sh script in the distro (as root with -Root), from a temp file with LF endings.
function Invoke-DistroScript([string]$Script, [string[]]$ScriptArgs = @(), [switch]$Root) {
  $tmp = Join-Path $env:TEMP ("herdr-wsl-" + [guid]::NewGuid().ToString("n") + ".sh")
  [IO.File]::WriteAllText($tmp, $Script.Replace("`r`n", "`n"))
  try {
    $path = (Wsl @("-d", $Distro, "--", "wslpath", "-a", ($tmp -replace '\\', '/')) | Select-Object -First 1).Trim()
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

$SshdScript = @'
set -e
port="$1"
command -v apt-get >/dev/null 2>&1 || { echo "only apt distros (Ubuntu, Debian) are set up by this script: run an sshd on 127.0.0.1:$port yourself, then run setup.ps1 again" >&2; exit 3; }
[ "$(ps -p 1 -o comm=)" = systemd ] || { echo "systemd is off in this distro: add [boot] systemd=true to /etc/wsl.conf, run 'wsl --shutdown', then run setup.ps1 again" >&2; exit 4; }
if [ ! -x /usr/sbin/sshd ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq openssh-server
fi
grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config || { echo "/etc/ssh/sshd_config doesn't include sshd_config.d/" >&2; exit 5; }
conf=/etc/ssh/sshd_config.d/herdr-wsl.conf
want="# herdr-wsl: this distro as a Herdr machine, reachable from Windows only
Port $port
ListenAddress 127.0.0.1
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes"
changed=
if [ "$(cat "$conf" 2>/dev/null)" != "$want" ]; then printf '%s\n' "$want" > "$conf"; changed=1; fi
# Ubuntu 22.10+ starts sshd from ssh.socket by default; run the plain service instead.
systemctl disable --now ssh.socket >/dev/null 2>&1 || true
systemctl enable ssh >/dev/null 2>&1
if [ -n "$changed" ] || ! systemctl is-active -q ssh; then systemctl restart ssh; fi
sleep 1
ss -ltn | grep -q "127.0.0.1:$port " || { echo "sshd is not listening on 127.0.0.1:$port" >&2; exit 6; }
'@

$AuthorizeScript = @'
set -e
key=$(tr -d '\r' < "$1")
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -qxF "$key" ~/.ssh/authorized_keys || printf '%s\n' "$key" >> ~/.ssh/authorized_keys
'@

$UnsshdScript = @'
rm -f /etc/ssh/sshd_config.d/herdr-wsl.conf
systemctl disable --now ssh ssh.socket >/dev/null 2>&1 || true
'@

$UnauthorizeScript = @'
[ -f ~/.ssh/authorized_keys ] && sed -i '/ herdr-wsl$/d' ~/.ssh/authorized_keys || true
'@

# ---------------------------------------------------------------- the distro

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { Fail "WSL isn't installed (wsl --install)." }
$rows = Wsl @("-l", "-v") | Where-Object { $_.Trim() } | Select-Object -Skip 1
if (-not $Distro) {
  $def = $rows | Where-Object { $_.Trim().StartsWith("*") } | Select-Object -First 1
  if (-not $def) { Fail "No default WSL distro. Pass -Distro <name> (wsl -l -v lists them)." }
  $Distro = ($def.Trim().TrimStart("*").Trim() -split '\s+')[0]
}
$row = $rows | Where-Object { (($_.Trim().TrimStart("*").Trim()) -split '\s+')[0] -eq $Distro } | Select-Object -First 1
if (-not $row) { Fail "No WSL distro named '$Distro' (wsl -l -v lists them)." }
if ((($row.Trim().TrimStart("*").Trim()) -split '\s+')[-1] -ne "2") { Fail "'$Distro' is WSL 1; convert it with: wsl --set-version $Distro 2" }
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
    Note "sshd stopped; openssh-server stays installed (sudo apt remove openssh-server)"
  }
  if ((Test-Path $SshConfig) -and (Select-String -Path $SshConfig -SimpleMatch $Begin -Quiet)) {
    if (Ask "Remove the herdr-wsl Host entry from ~/.ssh/config?") {
      $text = [IO.File]::ReadAllText($SshConfig)
      $text = [regex]::Replace($text, "(?s)\r?\n?" + [regex]::Escape($Begin) + ".*?" + [regex]::Escape($End) + "\r?\n?", "`n")
      [IO.File]::WriteAllText($SshConfig, $text)
      & ssh-keygen.exe -R "[127.0.0.1]:$Port" *> $null
      Note "removed Host $Machine and its known_hosts line"
    }
  }
  if ((Test-Path $KeyFile) -and (Ask "Delete the key ~/.ssh/herdr_wsl_ed25519 and unauthorize it in $Distro?")) {
    Invoke-DistroScript $UnauthorizeScript | Out-Null
    Remove-Item "$KeyFile", "$KeyFile.pub" -ErrorAction SilentlyContinue
    Note "key deleted"
  }
  Remove-Item (Join-Path $HerdrHome "mods\wsl\config.json") -ErrorAction SilentlyContinue
  Say "Done. Delete mods/wsl and its layout block to remove the mod itself."
  exit 0
}

# ---------------------------------------------------------------- 1. sshd

Say "1/4 sshd in $Distro"
if (Ask "Install/configure openssh-server in $Distro as root, listening on 127.0.0.1:$Port, keys only?") {
  $code = Invoke-DistroScript $SshdScript @("$Port") -Root
  if ($code -ne 0) { Fail "sshd setup in $Distro failed (exit $code)." }
  Note "sshd listening on 127.0.0.1:$Port"
} else { Fail "Herdr needs an ssh server in the distro; stopped." }

# ---------------------------------------------------------------- 2. key and Host entry

Say "2/4 ssh from Windows"
if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
  Fail "The Windows OpenSSH client is missing (Settings > System > Optional features > OpenSSH Client)."
}
if (Test-Ssh) {
  Note "'ssh $Machine' already works; key and Host entry left as they are"
} else {
  $hasHost = (Test-Path $SshConfig) -and (Select-String -Path $SshConfig -Pattern "^\s*Host\s+(.*\s)?$([regex]::Escape($Machine))(\s|$)" -Quiet)
  if ($hasHost -and -not (Select-String -Path $SshConfig -SimpleMatch $Begin -Quiet)) {
    Fail "~/.ssh/config already has a 'Host $Machine' that doesn't connect. Fix or rename it, or pass -Machine <other name>."
  }
  if (-not (Ask "Create ~/.ssh/herdr_wsl_ed25519 (no passphrase), authorize it in $Distro and add 'Host $Machine' to ~/.ssh/config?")) {
    Fail "Herdr needs to reach the distro over ssh; stopped."
  }
  New-Item -ItemType Directory -Force (Split-Path $KeyFile) | Out-Null
  if (-not (Test-Path $KeyFile)) {
    # PowerShell before 7.3 drops "" when calling programs; '""' reaches them as an empty argument.
    $empty = if ($PSVersionTable.PSVersion -ge [version]"7.3") { "" } else { '""' }
    & ssh-keygen.exe -q -t ed25519 -N $empty -C "herdr-wsl" -f $KeyFile
    if ($LASTEXITCODE -ne 0) { Fail "ssh-keygen failed." }
  }
  $pub = (Wsl @("-d", $Distro, "--", "wslpath", "-a", ("$KeyFile.pub" -replace '\\', '/')) | Select-Object -First 1).Trim()
  if ((Invoke-DistroScript $AuthorizeScript @($pub)) -ne 0) { Fail "Couldn't authorize the key in $Distro." }
  $user = (Wsl @("-d", $Distro, "--", "whoami") | Select-Object -First 1).Trim()
  if (-not $hasHost) {
    $block = @(
      "", $Begin,
      "Host $Machine",
      "  HostName 127.0.0.1",
      "  Port $Port",
      "  User $user",
      "  IdentityFile ~/.ssh/herdr_wsl_ed25519",
      "  IdentitiesOnly yes",
      "  StrictHostKeyChecking accept-new",
      $End, ""
    ) -join "`n"
    [IO.File]::AppendAllText($SshConfig, $block)
  }
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

# ---------------------------------------------------------------- 4. the mod's config

Say "4/4 wsl mod"
$modDir = Join-Path $HerdrHome "mods\wsl"
if (Test-Path $modDir) {
  $cfg = @{ machine = $Machine; distro = $Distro } | ConvertTo-Json -Compress
  [IO.File]::WriteAllText((Join-Path $modDir "config.json"), $cfg + "`n")
  Note "mods/wsl/config.json: $cfg"
} else {
  Note "mods/wsl isn't installed yet; it will use machine 'wsl' and the default distro"
}

Say "Done. In Herdr: the + on the WSL row, or space.new with machine '$Machine'."
