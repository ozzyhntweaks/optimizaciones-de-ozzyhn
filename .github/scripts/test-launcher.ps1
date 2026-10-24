<#
    Tests the PowerShell inside Run-Ozzyhn.cmd on Windows PowerShell 5.1 without starting the app:
      - online: it downloads the latest release and gets the real script
      - offline with a local copy: it runs the local copy
      - offline without a copy: it says so instead of failing silently
#>
param([string]$Cmd = 'Run-Ozzyhn.cmd')
$ErrorActionPreference = 'Stop'
trap { Write-Host ('::error::Test script stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

$line = @(Get-Content -LiteralPath $Cmd | Where-Object { $_ -match '^powershell .* -Command "' })
if ($line.Count -ne 1) { throw "Expected one powershell -Command line in $Cmd, found $($line.Count)" }
$ps = [regex]::Match($line[0], '-Command "(.*)"\s*$').Groups[1].Value
foreach ($part in 'Invoke-Expression $s', '& $env:OZ_LOCAL', "Read-Host 'Press Enter to close / Presiona Enter para cerrar'") {
    if (-not $ps.Contains($part)) { throw "Run-Ozzyhn.cmd no longer contains: $part" }
}
# Swap the parts that would start the app (or wait for Enter) for markers
$ps = $ps.Replace('Invoke-Expression $s', "Write-Output ('RAN-DOWNLOAD ' + `$s.Length)").
          Replace('& $env:OZ_LOCAL', "Write-Output 'RAN-LOCAL'").
          Replace("Read-Host 'Press Enter to close / Presiona Enter para cerrar'", "Write-Output 'NO-COPY'")

$fail = 0
function Invoke-Launcher([string]$Script, [string]$Local) {
    $env:OZ_LOCAL = $Local
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    (& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc 2>&1 | Out-String)
}
function Check([string]$Name, [bool]$Ok, [string]$Out) {
    if ($Ok) { Write-Host "PASS  $Name" -ForegroundColor Green } else { Write-Host "::error::FAIL  $Name -> $($Out.Trim())"; $script:fail++ }
}

$local = Join-Path ([IO.Path]::GetTempPath()) 'ozzyhn-local-copy.ps1'
Set-Content -LiteralPath $local -Value '# local copy'
$offline = $ps -replace "https://github\.com/[^']+", 'https://127.0.0.1:9/ozzyhn.ps1'

$out = Invoke-Launcher $ps $local
Check 'online: runs the latest release, not the local copy' ($out -match 'RAN-DOWNLOAD (\d+)' -and [int]$Matches[1] -gt 100000) $out
$out = Invoke-Launcher $offline $local
Check 'offline: falls back to the local copy' ($out -match 'RAN-LOCAL') $out
$out = Invoke-Launcher $offline (Join-Path ([IO.Path]::GetTempPath()) 'missing-ozzyhn.ps1')
Check 'offline, no copy: tells the user' ($out -match 'NO-COPY') $out

if ($fail) { exit 1 }
Write-Host 'Launcher tests passed' -ForegroundColor Green
