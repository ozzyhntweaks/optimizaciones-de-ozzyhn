<#
    Tests QUICK CLEAN in ozzyhn.ps1 on a real Windows machine.
    Up to 1.2.0 it emptied folders with Remove-Item -Recurse, which in Windows PowerShell 5.1 can
    follow a junction or symbolic link and delete the files it points to on another drive. It also
    trusted TEMP / TMP even when they pointed at another drive, and emptied every drive's Recycle Bin.
    These checks make sure none of that can come back. GitHub's Windows runner runs as administrator,
    like the app. Everything is made under a new folder on the Windows drive; the runner is thrown
    away afterwards, so nothing is cleaned up.
#>
param([string]$Path = 'ozzyhn.ps1')
$ErrorActionPreference = 'Stop'
# Show failures as annotations on the GitHub run, not only in the log
trap { Write-Host ('::error::Test script stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

# Load only the cleanup functions from the app (the full script would open its window)
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path, [ref]$tokens, [ref]$errors)
$want = 'Get-OzWindowsDrive', 'Get-OzCleanProtected', 'Test-OzCleanPath', 'Clear-OzFolder', 'Get-OzCleanTarget'
$defs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $want }, $true))
if ($defs.Count -ne $want.Count) { throw "Expected $($want.Count) functions in $Path, found $($defs.Count)" }
foreach ($d in $defs) { . ([scriptblock]::Create($d.Extent.Text)) }

$script:Failures = 0
function Check([string]$Name, [bool]$Ok) {
    if ($Ok) { Write-Host "PASS  $Name" -ForegroundColor Green }
    else { Write-Host "::error::FAIL  $Name"; $script:Failures++ }
}
function Exists([string]$P) { [IO.File]::Exists($P) -or [IO.Directory]::Exists($P) }

$drive = Get-OzWindowsDrive
Check "Windows drive found ($drive)" ($drive -match '^[A-Z]:$')
$other = if ($drive -eq 'C:') { 'D:' } else { 'C:' }
$base = Join-Path "$drive\" ('oz-clean-test-' + (Get-Date -Format 'HHmmssfff'))

# 1. Links inside a folder being cleaned are never followed or deleted
$keep = Join-Path $base 'keep'      # stands for the files on a work drive
$temp = Join-Path $base 'Temp'
New-Item -ItemType Directory -Path (Join-Path $keep 'sub'), (Join-Path $temp 'a\b'), (Join-Path $temp 'empty\deeper') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $keep 'work.txt') -Value 'work'
Set-Content -LiteralPath (Join-Path $keep 'sub\more.txt') -Value 'more'
[IO.File]::WriteAllBytes((Join-Path $temp 'one.tmp'), (New-Object byte[] 4096))
[IO.File]::WriteAllBytes((Join-Path $temp 'a\b\two.tmp'), (New-Object byte[] 2048))
Set-Content -LiteralPath (Join-Path $temp 'a\readonly.txt') -Value 'ro'
(Get-Item -LiteralPath (Join-Path $temp 'a\readonly.txt')).IsReadOnly = $true
Set-Content -LiteralPath (Join-Path $temp 'hidden.txt') -Value 'h'
(Get-Item -LiteralPath (Join-Path $temp 'hidden.txt') -Force).Attributes = 'Hidden'
New-Item -ItemType Junction -Path (Join-Path $temp 'junction') -Target $keep | Out-Null
New-Item -ItemType SymbolicLink -Path (Join-Path $temp 'a\b\dirlink') -Target $keep | Out-Null
New-Item -ItemType SymbolicLink -Path (Join-Path $temp 'filelink.txt') -Target (Join-Path $keep 'work.txt') | Out-Null

$freed = Clear-OzFolder $temp
Check 'links: files behind a junction or symbolic link are kept' ((Exists (Join-Path $keep 'work.txt')) -and (Exists (Join-Path $keep 'sub\more.txt')))
Check 'links: the links themselves are left alone' ((Exists (Join-Path $temp 'junction')) -and (Exists (Join-Path $temp 'a\b\dirlink')) -and (Exists (Join-Path $temp 'filelink.txt')))
Check 'files: normal, read-only and hidden files are deleted' (-not ((Exists (Join-Path $temp 'one.tmp')) -or (Exists (Join-Path $temp 'a\b\two.tmp')) -or (Exists (Join-Path $temp 'a\readonly.txt')) -or (Exists (Join-Path $temp 'hidden.txt'))))
Check 'folders: empty ones are removed, ones still holding a link stay' ((-not (Exists (Join-Path $temp 'empty'))) -and (Exists (Join-Path $temp 'a\b')))
Check 'freed space is counted' ($freed -ge 6144)

$jt = Join-Path $base 'JunctionAsTemp'
New-Item -ItemType Junction -Path $jt -Target $keep | Out-Null
Check 'a folder that is itself a junction is not emptied' (((Clear-OzFolder $jt) -eq 0) -and (Exists (Join-Path $keep 'work.txt')))
Check 'a missing folder frees nothing' ((Clear-OzFolder (Join-Path $base 'missing')) -eq 0)

# 2. The thumbnail filter applies to the top level only
$exp = Join-Path $base 'Explorer'
New-Item -ItemType Directory -Path (Join-Path $exp 'sub') -Force | Out-Null
foreach ($f in 'thumbcache_32.db', 'iconcache_32.db', 'sub\thumbcache_64.db') { Set-Content -LiteralPath (Join-Path $exp $f) -Value 'x' }
[void](Clear-OzFolder $exp 'thumbcache_*.db')
Check 'filter: only matching files are deleted' ((-not (Exists (Join-Path $exp 'thumbcache_32.db'))) -and (Exists (Join-Path $exp 'iconcache_32.db')) -and (Exists (Join-Path $exp 'sub\thumbcache_64.db')))

# 3. Folders Quick clean must refuse
$tempTail = '\\Temp(\\\d+)?$'
$refuse = @(
    @('empty path', '', $tempTail),
    @('relative path', 'Temp', $tempTail),
    @('network path', '\\server\share\Temp', $tempTail),
    @("another drive ($other\Temp)", "$other\Temp", $tempTail),
    @("another drive's root ($other\)", "$other\", '.*'),
    @("the Windows drive's root ($drive\)", "$drive\", '.*'),
    @('a path that climbs to the root', "$drive\Windows\Temp\..\..", '.*'),
    @('the user profile', $env:USERPROFILE, '.*'),
    @('the user profile as TEMP', $env:USERPROFILE, $tempTail),
    @('the Users folder', (Split-Path -Parent $env:USERPROFILE), '.*'),
    @('Documents', [Environment]::GetFolderPath('MyDocuments'), '.*'),
    @('Desktop', [Environment]::GetFolderPath('Desktop'), '.*'),
    @('the Windows folder', $env:SystemRoot, '.*'),
    @('Program Files', $env:ProgramFiles, '.*'),
    @('a folder holding the user profile', "$drive\Users", '.*')
)
foreach ($r in $refuse) {
    $why = Test-OzCleanPath $r[1] $r[2]
    Check ("refuses {0}: {1}" -f $r[0], $(if ($why) { $why } else { 'ALLOWED' })) ([bool]$why)
}
$jTemp = Join-Path $base 'jt\Temp'
New-Item -ItemType Directory -Path (Join-Path $base 'jt') -Force | Out-Null
New-Item -ItemType Junction -Path $jTemp -Target $keep | Out-Null
Check 'refuses a Temp folder that is a junction' ((Test-OzCleanPath $jTemp $tempTail) -eq 'it is a link to another place')
New-Item -ItemType Directory -Path (Join-Path $base 'real\Temp') -Force | Out-Null
New-Item -ItemType Junction -Path (Join-Path $base 'jp') -Target (Join-Path $base 'real') | Out-Null
Check 'refuses a Temp folder inside a junction' ((Test-OzCleanPath (Join-Path $base 'jp\Temp') $tempTail) -eq 'it is a link to another place')

# 4. Folders Quick clean may empty
Check 'allows the Windows temp folder' ((Test-OzCleanPath "$env:SystemRoot\Temp" '\\Temp$') -eq '')
Check 'allows a Temp folder on the Windows drive' ((Test-OzCleanPath $temp $tempTail) -eq '')
Check 'allows a Remote Desktop session temp folder (Temp\2)' ((Test-OzCleanPath (Join-Path $temp '2') $tempTail) -eq '')

# 5. Every built-in target is accepted on a standard Windows install
$targets = @(Get-OzCleanTarget)
Check ('{0} built-in targets' -f $targets.Count) ($targets.Count -ge 9)
foreach ($t in $targets) {
    $why = Test-OzCleanPath $t.Path $t.Tail
    $onWin = ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($t.Path)).TrimEnd('\')) -eq $drive
    if ($t.Label -eq 'Your temp folder' -and -not $onWin) { Check ("TEMP on another drive is skipped: {0}" -f $t.Path) ($why -eq 'not on the Windows drive') }
    else { Check ("target accepted: {0} ({1}){2}" -f $t.Label, $t.Path, $(if ($why) { " - $why" } else { '' })) ($why -eq '') }
}

# 6. The code itself: one Recycle Bin, and no recursive delete of files
$app = $ast
$bins = @($app.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Clear-RecycleBin' }, $true))
Check 'Quick clean still empties a Recycle Bin' ($bins.Count -ge 1)
foreach ($b in $bins) { Check ("line {0}: Clear-RecycleBin names the Windows drive only" -f $b.Extent.StartLineNumber) ($b.Extent.Text -match '-DriveLetter\s') }
$del = 'Remove-Item', 'ri', 'rm', 'rmdir', 'rd', 'del', 'erase'
foreach ($c in $app.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    if ([string]$c.GetCommandName() -notin $del) { continue }
    $recurse = @($c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -like 'r*' }).Count -gt 0
    if (-not $recurse) { continue }
    Check ("line {0}: recursive delete only on a fixed registry key" -f $c.Extent.StartLineNumber) ($c.Extent.Text -match "-LiteralPath\s+'HK(CU|LM):\\")
}

if ($script:Failures) { Write-Host "::error::$($script:Failures) cleanup check(s) failed"; exit 1 }
Write-Host 'All cleanup checks passed' -ForegroundColor Green
