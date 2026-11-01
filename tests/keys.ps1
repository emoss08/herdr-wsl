# Loads Add-KeySection / Remove-KeySection from setup.ps1 (without running it) and tests them.
param([string]$Setup = (Join-Path $PSScriptRoot "..\setup.ps1"))
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Setup, [ref]$null, [ref]$null)
foreach ($name in "Add-KeySection", "Remove-KeySection") {
  $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true) | Select-Object -First 1
  . ([scriptblock]::Create($fn.Extent.Text))
}
$HerdrHome = Join-Path $env:TEMP ("keys-test-" + [guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory $HerdrHome | Out-Null
$KeySection = "layout:main-wsl"
$file = Join-Path $HerdrHome "keys.json"
$fails = 0
function Check([string]$what, [bool]$ok) { if ($ok) { "  ok   $what" } else { "  FAIL $what"; $script:fails++ } }
function Valid { try { $null = [IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop; $true } catch { $false } }
function Count { ([regex]::Matches([IO.File]::ReadAllText($file), '"layout:main-wsl"')).Count }

"1. empty keys.json"
[IO.File]::WriteAllText($file, "")
$r = Add-KeySection; Check "add -> '$r'" ($r -eq "created")
Check "valid, one section" ((Valid) -and (Count) -eq 1)

"2. keys.json with // comments (not plain JSON)"
$commented = "{`n  // mine`n  `"global`": { `"ctrl-1`": `"tab.select:1`" }`n}`n"
[IO.File]::WriteAllText($file, $commented)
$r1 = Add-KeySection; $r2 = Add-KeySection
Check "add -> '$r1'" ($r1 -like "left alone*")
Check "second add -> '$r2'" ($r2 -like "left alone*")
Check "file untouched" ([IO.File]::ReadAllText($file) -eq $commented)

"3. normal keys.json"
[IO.File]::WriteAllText($file, "{`n  `"global`": {`n    `"ctrl-left`": `"send:\u001bb`"`n  }`n}`n")
$r1 = Add-KeySection; $r2 = Add-KeySection
Check "add -> '$r1'" ($r1 -like "added*")
Check "again -> '$r2'" ($r2 -eq "already there")
Check "valid, one section, escape kept" ((Valid) -and (Count) -eq 1 -and [IO.File]::ReadAllText($file).Contains('\u001bb'))

"4. ours first, another section after it"
[IO.File]::WriteAllText($file, "{`n  `"layout:main-wsl`": {`n    `"ctrl-shift-n`": `"wsl.new-space`"`n  },`n  `"layout:main`": { `"f2`": `"tab.rename`" }`n}`n")
$r = Remove-KeySection; Check "remove -> '$r'" ($r -eq "removed")
Check "valid, ours gone, other kept" ((Valid) -and (Count) -eq 0 -and [IO.File]::ReadAllText($file).Contains('"layout:main"'))

"5. ours last"
[IO.File]::WriteAllText($file, "{`n  `"global`": { `"f2`": `"tab.rename`" },`n  `"layout:main-wsl`": {`n    `"ctrl-shift-n`": `"wsl.new-space`"`n  }`n}`n")
$r = Remove-KeySection; Check "remove -> '$r'" ($r -eq "removed")
Check "valid, ours gone" ((Valid) -and (Count) -eq 0)

"6. ours alone"
[IO.File]::WriteAllText($file, "{`n  `"layout:main-wsl`": {`n    `"ctrl-shift-n`": `"wsl.new-space`"`n  }`n}`n")
$r = Remove-KeySection; Check "remove -> '$r'" ($r -eq "removed")
Check "valid, empty object" ((Valid) -and (Count) -eq 0)

"7. remove from a file without it"
$r = Remove-KeySection; Check "remove -> '$r'" ($r -eq "no section")

Remove-Item $HerdrHome -Recurse -Force
"failures: $fails"
exit $fails
