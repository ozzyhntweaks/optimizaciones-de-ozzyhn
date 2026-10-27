<#
    Tests CLEAN UP FILES (TOOLS page) in ozzyhn.ps1 on a real Windows machine.
    Up to 1.2.0 the old Quick clean emptied folders with Remove-Item -Recurse, which in Windows
    PowerShell 5.1 can follow a junction or symbolic link and delete the files it points to on
    another drive. It also trusted TEMP / TMP even when they pointed at another drive, and emptied
    every drive's Recycle Bin without asking. These checks make sure none of that can come back:
      1-2. emptying and measuring folders never goes through a link
      3-4. which folders may be emptied at all
      5.   the catalog: every item is a known Windows cache with a Spanish text
      6.   the scan reads only, and offers only the Recycle Bin on other drives
      7.   cleaning rebuilds and re-checks every folder, and refuses anything unexpected
      8.   the code: Recycle Bins only by drive letter, no recursive delete of files
    GitHub's Windows runner runs as administrator, like the app. Test folders are made under a new
    folder on the Windows drive; the runner is thrown away afterwards, so nothing is cleaned up.
#>
param([string]$Path = 'ozzyhn.ps1')
$ErrorActionPreference = 'Stop'
# Show failures as annotations on the GitHub run, not only in the log
trap { Write-Host ('::error::Test script stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

# Load only the cleanup functions from the app (the full script would open its window)
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path, [ref]$tokens, [ref]$errors)
$want = 'T', 'Get-OzWindowsDrive', 'Get-OzCleanProtected', 'Test-OzCleanPath', 'Clear-OzFolder', 'Get-OzFolderSize', 'Format-OzBytes',
        'New-OzCleanFolder', 'Get-OzLongPath', 'Get-OzCleanCatalog', 'Get-OzCleanDrive', 'Get-OzRecycleBinPath', 'Get-OzRecycleBinSize',
        'Get-OzDeliveryCacheSize', 'Get-OzCleanScan', 'Invoke-OzCleanRun'
$defs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $want }, $true))
if ($defs.Count -ne $want.Count) { throw "Expected $($want.Count) functions in $Path, found $($defs.Count)" }
foreach ($d in $defs) { . ([scriptblock]::Create($d.Extent.Text)) }
$Oz = @{ Lang = 'en'; Es = New-Object 'System.Collections.Generic.Dictionary[string,string]' }

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
$tempTail = '\\Temp(\\\d+)?$'

# 1. Links inside a folder being emptied are never followed or deleted
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

$measured = Get-OzFolderSize $temp
$freed = Clear-OzFolder $temp
Check 'links: files behind a junction or symbolic link are kept' ((Exists (Join-Path $keep 'work.txt')) -and (Exists (Join-Path $keep 'sub\more.txt')))
Check 'links: the links themselves are left alone' ((Exists (Join-Path $temp 'junction')) -and (Exists (Join-Path $temp 'a\b\dirlink')) -and (Exists (Join-Path $temp 'filelink.txt')))
Check 'files: normal, read-only and hidden files are deleted' (-not ((Exists (Join-Path $temp 'one.tmp')) -or (Exists (Join-Path $temp 'a\b\two.tmp')) -or (Exists (Join-Path $temp 'a\readonly.txt')) -or (Exists (Join-Path $temp 'hidden.txt'))))
Check 'folders: empty ones are removed, ones still holding a link stay' ((-not (Exists (Join-Path $temp 'empty'))) -and (Exists (Join-Path $temp 'a\b')))
Check "freed space is counted ($freed bytes)" ($freed -ge 6144)
Check "the scan measured what was freed, not what is behind the links ($measured = $freed)" ($measured -eq $freed)
Check 'after cleaning, nothing is left to measure' ((Get-OzFolderSize $temp) -eq 0)

$jt = Join-Path $base 'JunctionAsTemp'
New-Item -ItemType Junction -Path $jt -Target $keep | Out-Null
Check 'a folder that is itself a junction is not emptied' (((Clear-OzFolder $jt) -eq 0) -and (Exists (Join-Path $keep 'work.txt')))
Check 'a folder that is itself a junction measures 0' ((Get-OzFolderSize $jt) -eq 0)
Check 'a missing folder frees and measures nothing' (((Clear-OzFolder (Join-Path $base 'missing')) -eq 0) -and ((Get-OzFolderSize (Join-Path $base 'missing')) -eq 0))

# 2. The thumbnail filter applies to the top level only
$exp = Join-Path $base 'Explorer'
New-Item -ItemType Directory -Path (Join-Path $exp 'sub') -Force | Out-Null
foreach ($f in 'thumbcache_32.db', 'iconcache_32.db', 'sub\thumbcache_64.db') { Set-Content -LiteralPath (Join-Path $exp $f) -Value 'x' }
Check 'filter: only matching files are measured' ((Get-OzFolderSize $exp 'thumbcache_*.db') -eq (Get-Item -LiteralPath (Join-Path $exp 'thumbcache_32.db')).Length)
[void](Clear-OzFolder $exp 'thumbcache_*.db')
Check 'filter: only matching files are deleted' ((-not (Exists (Join-Path $exp 'thumbcache_32.db'))) -and (Exists (Join-Path $exp 'iconcache_32.db')) -and (Exists (Join-Path $exp 'sub\thumbcache_64.db')))

# 3. Folders that must be refused
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

# 4. Folders that may be emptied
Check 'allows the Windows temp folder' ((Test-OzCleanPath "$env:SystemRoot\Temp" '\\Temp$') -eq '')
Check 'allows a Temp folder on the Windows drive' ((Test-OzCleanPath $temp $tempTail) -eq '')
Check 'allows a Remote Desktop session temp folder (Temp\2)' ((Test-OzCleanPath (Join-Path $temp '2') $tempTail) -eq '')

# The texts the user can see must all have a Spanish line
$pairsAst = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Oz.SpanishPairs' }, $true)
$pairsText = $pairsAst.Right.Find({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value
$es = @{}
$block = New-Object System.Collections.Generic.List[string]
foreach ($raw in (($pairsText -replace "`r", '') -split "`n") + @('')) {
    $line = $raw.TrimEnd()
    if ($line) { $block.Add($line); continue }
    if ($block.Count -ge 2) { $es[$block[0]] = $true }
    $block.Clear()
}
function Test-Spanish([string]$Text) { $es.ContainsKey($Text) }
$testFn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-OzCleanPath' }, $true)
foreach ($m in [regex]::Matches($testFn.Extent.Text, "return '([^']+)'")) {
    Check ("Spanish line for the reason '{0}'" -f $m.Groups[1].Value) (Test-Spanish $m.Groups[1].Value)
}

$short = $env:SystemRoot.Substring(0, 3) + 'PROGRA~1'
if (Test-Path -LiteralPath $short) {
    $long = Get-OzLongPath $short
    Check "long path: a short 8.3 name is expanded ($short -> $long)" ($long -notmatch '~' -and [IO.Directory]::Exists($long))
} else { Write-Host '::notice::SKIP  this drive has no 8.3 short names' }
Check 'long path: a normal path is kept' ((Get-OzLongPath $env:SystemRoot) -eq $env:SystemRoot)
Check 'long path: a missing path is kept' ((Get-OzLongPath "$base\NOPE~1\x") -eq "$base\NOPE~1\x")

# 5. The catalog
$catalog = @(Get-OzCleanCatalog)
Check ('catalog has {0} items with unique ids' -f $catalog.Count) ($catalog.Count -ge 9 -and @($catalog | ForEach-Object Id | Select-Object -Unique).Count -eq $catalog.Count)
foreach ($c in $catalog) {
    Check ("catalog '{0}': name and description have Spanish lines" -f $c.Id) ((Test-Spanish $c.Name) -and (Test-Spanish $c.Desc))
    Check ("catalog '{0}': kind is known" -f $c.Id) ($c.Kind -in 'Folders', 'DeliveryOpt')
    foreach ($f in @($c.Folders)) {
        if (-not $f.Path) { continue }
        $why = Test-OzCleanPath $f.Path $f.Tail
        $onWin = ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($f.Path)).TrimEnd('\')) -eq $drive
        if ($c.Id -eq 'temp' -and -not $onWin) { Check ("TEMP on another drive is refused: {0}" -f $f.Path) ($why -eq 'not on the Windows drive') }
        else { Check ("catalog '{0}' folder accepted: {1}{2}" -f $c.Id, $f.Path, $(if ($why) { " - $why" } else { '' })) ($why -eq '') }
    }
}
Check 'catalog: TEMP is listed by its long name' (@($catalog | Where-Object Id -EQ 'temp' | ForEach-Object Folders | Where-Object { $_.Path -match '~' }).Count -eq 0)
foreach ($t in 'Recycle Bin', 'Files you deleted on this drive. Check it first: after this they cannot be brought back.') { Check "Spanish line for '$t'" (Test-Spanish $t) }

# 6. The scan reads only
$drives = @(Get-OzCleanDrive)
Check ('local drives found: {0}' -f (($drives | ForEach-Object Drive) -join ', ')) (@($drives | Where-Object { $_.Drive -eq $drive -and $_.IsWindows }).Count -eq 1)
$probe = Join-Path $env:SystemRoot 'Temp\oz-scan-probe.tmp'
Set-Content -LiteralPath $probe -Value 'probe'
$scan = @(Get-OzCleanScan -Drives @($drive))
Check ('Windows drive scan lists {0} items' -f $scan.Count) ($scan.Count -ge 3)
Check 'the scan deletes nothing' (Exists $probe)
Check 'scan keys are unique' (@($scan | ForEach-Object Key | Select-Object -Unique).Count -eq $scan.Count)
Check 'the Recycle Bin of the Windows drive is offered, not pre-selected' (@($scan | Where-Object { $_.Key -eq "bin|$drive" -and -not $_.Rec }).Count -eq 1)
foreach ($i in $scan) {
    Check ("scan '{0}': size {1}" -f $i.Key, $i.Bytes) ($i.Bytes -ge -1)
    if ($i.Kind -eq 'Folders') { foreach ($p in @($i.Paths)) { Check ("scan '{0}' lists an allowed folder: {1}" -f $i.Key, $p) (@(Get-OzCleanCatalog | Where-Object Id -EQ $i.Id | ForEach-Object Folders | Where-Object { $_.Path -eq $p -and (Test-OzCleanPath $_.Path $_.Tail) -eq '' }).Count -eq 1) } }
}
$second = @($drives | Where-Object { -not $_.IsWindows } | Select-Object -First 1)
if ($second.Count) {
    $s2 = @(Get-OzCleanScan -Drives @($second[0].Drive))
    Check ("other drive {0}: only its Recycle Bin is offered" -f $second[0].Drive) ($s2.Count -eq 1 -and $s2[0].Id -eq 'bin')
} else { Write-Host '::notice::SKIP  no second local drive on this machine' }
Check 'odd drive names are ignored' (@(Get-OzCleanScan -Drives @('', 'C', '\\server\share', 'C:\Windows', '1:')).Count -eq 0)

# 7. Cleaning: folders are rebuilt from the catalog and checked again right before deleting
$runTemp = Join-Path $base 'run\Temp'
New-Item -ItemType Directory -Path $runTemp -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $runTemp 'x.tmp'), (New-Object byte[] 1024))
function Get-OzCleanCatalog {
    # Test catalog: one normal folder, one Temp folder that is really a junction to the "work" files
    @(
        [pscustomobject]@{ Id = 'faketemp'; Kind = 'Folders'; Rec = $true; Services = [string[]]@(); Folders = @((New-OzCleanFolder $runTemp '\\Temp$')); Name = 'Your temp folder'; Desc = 'x' }
        [pscustomobject]@{ Id = 'fakelink'; Kind = 'Folders'; Rec = $true; Services = [string[]]@(); Folders = @((New-OzCleanFolder $jTemp '\\Temp$')); Name = 'Windows temp'; Desc = 'x' }
    )
}
$used = @($drives | ForEach-Object Drive)
$missing = @([char[]](90..68) | ForEach-Object { "$($_):" } | Where-Object { $_ -notin $used } | Select-Object -First 1)[0]
$out = @(Invoke-OzCleanRun -Picks @("faketemp|$drive", "fakelink|$drive", "faketemp|$other", "bin|$missing", 'nonsense', "unknown|$drive", "faketemp|$drive|x"))
$lines = @($out | Where-Object { $_ -is [string] })
$result = @($out | Where-Object { $_ -isnot [string] }) | Select-Object -First 1
$lines | ForEach-Object { Write-Host "      log: $_" }
Check 'run: the picked folder is emptied' (-not (Exists (Join-Path $runTemp 'x.tmp')))
Check 'run: a folder that turned into a link is refused and logged' ((Exists (Join-Path $keep 'work.txt')) -and @($lines | Where-Object { $_ -match 'skipped \(it is a link to another place\)' }).Count -eq 1)
Check "run: a missing drive's Recycle Bin is left alone ($missing)" (@($lines | Where-Object { $_ -match "Drive $missing is not a local drive" }).Count -eq 1)
Check 'run: folders are never cleaned for a pick on another drive' (@($lines | Where-Object { $_ -match 'Your temp folder' }).Count -eq 1)
Check ("run: freed bytes reported ({0})" -f $result.FreedBytes) ($result -and $result.FreedBytes -ge 1024)

# 7b. Emptying the Windows drive's Recycle Bin leaves the other drive's Recycle Bin alone
Add-Type -AssemblyName Microsoft.VisualBasic
function Send-ToBin([string]$P) {
    [IO.File]::WriteAllBytes($P, (New-Object byte[] 4096))
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($P, 'OnlyErrorDialogs', 'SendToRecycleBin')
}
Send-ToBin (Join-Path $base 'to-bin.tmp')
$beforeWin = Get-OzRecycleBinSize $drive
$binOther = $null; $beforeOther = 0
if ($second.Count) {
    $binOther = $second[0].Drive
    Send-ToBin (Join-Path "$($second[0].Drive)\" ('oz-bin-test-' + (Get-Date -Format 'HHmmssfff') + '.tmp'))
    $beforeOther = Get-OzRecycleBinSize $binOther
}
if ($beforeWin -gt 0) {
    $scanBin = @(Get-OzCleanScan -Drives @($drive) | Where-Object Id -EQ 'bin')
    Check ("scan: the Windows drive's Recycle Bin shows its size ({0} bytes)" -f $beforeWin) ($scanBin.Count -eq 1 -and $scanBin[0].Bytes -eq $beforeWin)
    $binOut = @(Invoke-OzCleanRun -Picks @("bin|$drive"))
    $binOut | Where-Object { $_ -is [string] } | ForEach-Object { Write-Host "      log: $_" }
    $afterWin = Get-OzRecycleBinSize $drive
    Check "run: the Recycle Bin of $drive is emptied ($beforeWin -> $afterWin bytes)" ($afterWin -eq 0)
    Write-Host ("::notice::Recycle Bin test ran: {0} {1} -> {2} bytes; other drive before {3} bytes, after {4}" -f $drive, $beforeWin, $afterWin, $beforeOther, $(if ($binOther) { Get-OzRecycleBinSize $binOther } else { 'n/a' }))
    if ($binOther -and $beforeOther -gt 0) { Check ("run: the Recycle Bin of {0} is left as it was" -f $binOther) ((Get-OzRecycleBinSize $binOther) -eq $beforeOther) }
    else { Write-Host '::notice::SKIP  no file could be put in a second drive''s Recycle Bin on this machine' }
} else { Write-Host '::notice::SKIP  this machine did not put the test file in the Recycle Bin' }

# 8. The code itself: Recycle Bins only by drive letter, and no recursive delete of files
$bins = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Clear-RecycleBin' }, $true))
Check 'a Recycle Bin can still be emptied' ($bins.Count -ge 1)
foreach ($b in $bins) { Check ("line {0}: Clear-RecycleBin names one drive" -f $b.Extent.StartLineNumber) ($b.Extent.Text -match '-DriveLetter\s') }
$del = 'Remove-Item', 'ri', 'rm', 'rmdir', 'rd', 'del', 'erase'
foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    if ([string]$c.GetCommandName() -notin $del) { continue }
    $recurse = @($c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -like 'r*' }).Count -gt 0
    if (-not $recurse) { continue }
    Check ("line {0}: recursive delete only on a fixed registry key" -f $c.Extent.StartLineNumber) ($c.Extent.Text -match "-LiteralPath\s+'HK(CU|LM):\\")
}

if ($script:Failures) { Write-Host "::error::$($script:Failures) cleanup check(s) failed"; exit 1 }
Write-Host 'All cleanup checks passed' -ForegroundColor Green
