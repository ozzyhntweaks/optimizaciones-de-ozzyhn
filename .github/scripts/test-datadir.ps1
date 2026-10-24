<#
    Tests the data-folder lock in ozzyhn.ps1 (Protect-OzDataDir) on a real Windows machine.
    GitHub's Windows runner runs as administrator, like the app. Each case uses its own folder
    under C:\ProgramData. The runner is thrown away afterwards, so nothing is cleaned up.
#>
param([string]$Path = 'ozzyhn.ps1')
$ErrorActionPreference = 'Stop'
# Show failures as annotations on the GitHub run, not only in the log
trap { Write-Host ('::error::Test script stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

# Load only the data-folder functions from the app (the full script would open its window)
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path, [ref]$tokens, [ref]$errors)
$want = 'Get-OzAdminSids', 'Test-OzAdminOnly', 'New-OzDataDirAcl', 'Protect-OzDataDir'
$defs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $want }, $true))
if ($defs.Count -ne $want.Count) { throw "Expected $($want.Count) functions in $Path, found $($defs.Count)" }
foreach ($d in $defs) { . ([scriptblock]::Create($d.Extent.Text)) }

$script:Failures = 0
function Check([string]$Name, [bool]$Ok) {
    if ($Ok) { Write-Host "PASS  $Name" -ForegroundColor Green }
    else { Write-Host "::error::FAIL  $Name"; $script:Failures++ }
}
$stamp = Get-Date -Format 'HHmmssfff'
function New-Case([string]$Name) {
    $script:Oz = @{ DataDir = (Join-Path $env:ProgramData "oz-test-$Name-$stamp") }
    $script:Oz.DataDir
}
function Get-Old([string]$Dir) { @(Get-ChildItem -LiteralPath $env:ProgramData -Force -Filter ((Split-Path -Leaf $Dir) + '.old-*')) }
function Test-UsersReadOnly([string]$P) {
    foreach ($r in (Get-Acl -LiteralPath $P).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($r.IdentityReference.Value -notin 'S-1-5-18', 'S-1-5-32-544' -and ([int]$r.FileSystemRights -band 0x500D0156)) { return $false }
    }
    $true
}
$everyone = New-Object Security.Principal.SecurityIdentifier 'S-1-1-0'
$inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'

# 1. First run: no folder yet
$dir = New-Case 'fresh'
Check 'fresh: Protect-OzDataDir succeeds' (Protect-OzDataDir)
Check 'fresh: folder is locked' (Test-OzAdminOnly $dir)
Check 'fresh: nothing inherited from ProgramData' ((Get-Acl -LiteralPath $dir).AreAccessRulesProtected)
Check 'fresh: other accounts can only read' (Test-UsersReadOnly $dir)
Check 'fresh: no old folder made' ((Get-Old $dir).Count -eq 0)
Set-Content -LiteralPath (Join-Path $dir 'journal.json') -Value '{"x":1}'
New-Item -ItemType Directory -Path (Join-Path $dir 'logs') | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'logs\a.log') -Value 'log'
Check 'fresh: files written later are locked too' ((Test-OzAdminOnly (Join-Path $dir 'journal.json')) -and (Test-UsersReadOnly (Join-Path $dir 'logs\a.log')))
Check 'second run: succeeds without moving anything' ((Protect-OzDataDir) -and (Get-Old $dir).Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $dir 'journal.json')))

# 2. Upgrade from 1.1.0: folder made by an admin with the normal ProgramData permissions
$dir = New-Case 'upgrade'
New-Item -ItemType Directory -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'journal.json') -Value '{"tweak":{"Applied":"2026-10-01"}}'
Set-Content -LiteralPath (Join-Path $dir 'settings.json') -Value '{"Lang":"es"}'
New-Item -ItemType Directory -Path (Join-Path $dir 'logs') | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'logs\old.log') -Value 'old'
Check 'upgrade: old folder is not locked (standard accounts can add files)' (-not (Test-OzAdminOnly $dir))
Check 'upgrade: Protect-OzDataDir succeeds' (Protect-OzDataDir)
Check 'upgrade: new folder is locked' (Test-OzAdminOnly $dir)
Check 'upgrade: undo journal carried over unchanged' ((Get-Content -LiteralPath (Join-Path $dir 'journal.json') -Raw).Trim() -eq '{"tweak":{"Applied":"2026-10-01"}}')
Check 'upgrade: settings carried over' (Test-Path -LiteralPath (Join-Path $dir 'settings.json'))
$old = Get-Old $dir
Check 'upgrade: old folder kept with its logs' ($old.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $old[0].FullName 'logs\old.log')))
Check 'upgrade: reported as carried over' ($Oz.DataDirCarried -eq $true -and $Oz.DataDirOld -eq $old[0].FullName)

# 3. Folder that any account can modify (for example, created by a standard user)
$dir = New-Case 'openfolder'
New-Item -ItemType Directory -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'journal.json') -Value '{"planted":1}'
$acl = Get-Acl -LiteralPath $dir
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'Modify', $inherit, 'None', 'Allow')))
Set-Acl -LiteralPath $dir -AclObject $acl
Check 'open folder: Protect-OzDataDir succeeds' (Protect-OzDataDir)
Check 'open folder: new folder is locked' (Test-OzAdminOnly $dir)
Check 'open folder: journal NOT carried over' (-not (Test-Path -LiteralPath (Join-Path $dir 'journal.json')))
Check 'open folder: reported as not carried' ($Oz.DataDirCarried -eq $false -and $Oz.DataDirOld)

# 4. Normal folder, but the journal file itself can be changed by any account
$dir = New-Case 'openfile'
New-Item -ItemType Directory -Path $dir | Out-Null
$j = Join-Path $dir 'journal.json'
Set-Content -LiteralPath $j -Value '{"planted":1}'
Set-Content -LiteralPath (Join-Path $dir 'settings.json') -Value '{"Lang":"en"}'
$acl = Get-Acl -LiteralPath $j
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($everyone, 'Write', 'Allow')))
Set-Acl -LiteralPath $j -AclObject $acl
Check 'open file: Protect-OzDataDir succeeds' (Protect-OzDataDir)
Check 'open file: journal NOT carried over' (-not (Test-Path -LiteralPath $j))
Check 'open file: settings still carried over' (Test-Path -LiteralPath (Join-Path $dir 'settings.json'))

# 5. Folder owned by a non-admin group
$dir = New-Case 'owner'
New-Item -ItemType Directory -Path $dir | Out-Null
Set-Content -LiteralPath (Join-Path $dir 'journal.json') -Value '{"planted":1}'
& icacls.exe $dir /setowner '*S-1-5-32-545' | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'SKIP  non-admin owner: icacls could not change the owner' -ForegroundColor Yellow }
else {
    Check 'non-admin owner: Protect-OzDataDir succeeds' (Protect-OzDataDir)
    Check 'non-admin owner: journal NOT carried over' (-not (Test-Path -LiteralPath (Join-Path $dir 'journal.json')))
}

# 6. The data folder is a junction pointing somewhere else
$dir = New-Case 'junction'
$decoy = "$dir-target"
New-Item -ItemType Directory -Path $decoy | Out-Null
Set-Content -LiteralPath (Join-Path $decoy 'journal.json') -Value '{"planted":1}'
New-Item -ItemType Junction -Path $dir -Target $decoy | Out-Null
Check 'junction: is not trusted' (-not (Test-OzAdminOnly $dir))
Check 'junction: Protect-OzDataDir succeeds' (Protect-OzDataDir)
$it = Get-Item -LiteralPath $dir -Force
Check 'junction: data folder is now a real, locked folder' (-not ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) -and (Test-OzAdminOnly $dir))
Check 'junction: journal NOT carried over' (-not (Test-Path -LiteralPath (Join-Path $dir 'journal.json')))
Check 'junction: target folder permissions untouched' (-not (Get-Acl -LiteralPath $decoy).AreAccessRulesProtected)

# 7. The journal is a hard link to a file somewhere else
$dir = New-Case 'hardlink'
New-Item -ItemType Directory -Path $dir | Out-Null
$other = "$dir-other.json"
Set-Content -LiteralPath $other -Value '{"planted":1}'
New-Item -ItemType HardLink -Path (Join-Path $dir 'journal.json') -Target $other | Out-Null
Check 'hard link: Protect-OzDataDir succeeds' (Protect-OzDataDir)
Check 'hard link: journal NOT carried over' (-not (Test-Path -LiteralPath (Join-Path $dir 'journal.json')))

# 8. A file sits where the data folder should be
$dir = New-Case 'file'
Set-Content -LiteralPath $dir -Value 'not a folder'
Check 'file in the way: Protect-OzDataDir succeeds' (Protect-OzDataDir)
Check 'file in the way: replaced by a locked folder' ((Test-Path -LiteralPath $dir -PathType Container) -and (Test-OzAdminOnly $dir))

if ($script:Failures) { Write-Host "$($script:Failures) test(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All data-folder tests passed' -ForegroundColor Green
