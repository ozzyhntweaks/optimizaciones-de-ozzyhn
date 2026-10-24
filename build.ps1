<#
    Compiles /src into the single file ozzyhn.ps1 that users launch with:
        irm https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1 | iex
    Users get it from a GitHub release: bump $Oz.Version, push to main, and
    .github/workflows/release.yml checks, hashes and publishes the new version.
    Checks: ASCII-only, XAML well-formed, PowerShell syntax.
#>
param(
    [string]$Out = (Join-Path $PSScriptRoot 'ozzyhn.ps1'),
    # Your GitHub username, if it is not "ozzyhn". Rewrites every launch URL, then builds.
    [string]$Owner
)
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'src'

if ($Owner) {
    foreach ($rel in @(@('src', '00-header.ps1'), @('src', '10-core.ps1'), @('README.md'), @('Run-Ozzyhn.cmd'))) {
        $f = $PSScriptRoot
        foreach ($part in $rel) { $f = Join-Path $f $part }
        $t = [IO.File]::ReadAllText($f)
        $t = $t -replace 'githubusercontent\.com/[^/\s]+/optimizaciones-de-ozzyhn', "githubusercontent.com/$Owner/optimizaciones-de-ozzyhn"
        $t = $t -replace 'github\.com/[^/\s]+/optimizaciones-de-ozzyhn', "github.com/$Owner/optimizaciones-de-ozzyhn"
        $t = $t -replace "\`$Oz\.RepoOwner = '[^']*'", "`$`$Oz.RepoOwner = '$Owner'"
        [IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Host "GitHub owner set to '$Owner'." -ForegroundColor Cyan
}

$order = @('00-header.ps1', '10-core.ps1', '20-hardware.ps1', '30-tweaks.ps1', '40-profiles.ps1', '50-actions.ps1', '60-ui.xaml', '70-ui.ps1', '99-main.ps1')
$parts = New-Object System.Collections.Generic.List[string]
foreach ($name in $order) {
    $path = Join-Path $src $name
    $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n").TrimEnd()
    if ($name -like '*.xaml') {
        [void]([xml]$text)   # throws if not well-formed
        if ($text -match "(?m)^'@") { throw "$name contains a line starting with '@ which would break the here-string." }
        $text = "#region ============================ XAML ============================`n`$Oz.Xaml = @'`n$text`n'@`n#endregion"
    }
    $parts.Add($text)
}
$parts.Add("`n# ---- launch ----`nStart-Ozzyhn")
$all = ($parts -join "`n`n") + "`n"

$bad = [regex]::Matches($all, '[^\x09\x0A\x0D\x20-\x7E]')
if ($bad.Count) {
    $first = $bad[0]
    $line = ($all.Substring(0, $first.Index) -split "`n").Count
    throw ("Non-ASCII character U+{0:X4} at line {1}. Use [char]0x.... in PowerShell or &#x....; in XAML." -f [int][char]$first.Value, $line)
}

$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($all, [ref]$tokens, [ref]$errors)
if ($errors.Count) {
    $errors | ForEach-Object { Write-Host ("{0} (line {1})" -f $_.Message, $_.Extent.StartLineNumber) -ForegroundColor Red }
    throw "Syntax errors: $($errors.Count)"
}

$crlf = $all.Replace("`n", "`r`n")
[IO.File]::WriteAllText($Out, $crlf, (New-Object System.Text.UTF8Encoding($false)))
$lines = ($crlf -split "`r`n").Count
Write-Host ("Built {0}  ({1:N0} lines, {2:N0} KB)" -f $Out, $lines, ((Get-Item $Out).Length / 1KB)) -ForegroundColor Green
