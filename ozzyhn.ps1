<#
    ===================================================================
     OPTIMIZACIONES DE OZZYHN  //  OZZYHN TWEAKS
     Hardware-aware optimizer for Windows 10 / 11
    ===================================================================
     Launch from an Administrator PowerShell:

         irm https://github.com/ozzyhntweaks/optimizaciones-de-ozzyhn/releases/latest/download/ozzyhn.ps1 | iex

     Only download it from that address. Each release lists SHA-256 hashes
     and a GitHub build attestation so you can check your copy (see README).

     What it does
       - Scans the PC (CPU, GPU, RAM, storage, board, battery, temps)
       - Detects Desktop / Laptop / VM, Windows 10 / 11, and the PC tier
         (CHEAP, BUDGET, MID-RANGE, FANCY)
       - 169 reversible tweaks. Each one detects its current state, so the
         switches show what is really ON in Windows right now.
       - One-click profiles, debloat, driver recommendations, cleanup,
         repair tools, startup manager, restore points and a full undo log.
       - Rainmeter desktop themes (clock that matches your wallpaper, status
         bar, dock, wallpaper picker). Rainmeter itself is never downloaded.
       - English / Espanol interface.

     Made by OZZYHN TWEAKS - https://github.com/ozzyhntweaks
     License: MIT
#>

#region ============================ STATE ============================
$Oz = [hashtable]::Synchronized(@{})
$Oz.Version   = '1.4.0'
$Oz.AppName   = 'Optimizaciones de Ozzyhn'
$Oz.Brand     = 'OZZYHN TWEAKS'
$Oz.RepoOwner = 'ozzyhntweaks'
$Oz.RepoName  = 'optimizaciones-de-ozzyhn'
# The exact released file for this version, used when the app relaunches itself as administrator.
# Releases are built and hashed by GitHub Actions, so a commit to main never reaches users by itself.
$Oz.ScriptUrl = 'https://github.com/{0}/{1}/releases/download/v{2}/ozzyhn.ps1' -f $Oz.RepoOwner, $Oz.RepoName, $Oz.Version
$Oz.RepoUrl   = 'https://github.com/{0}/{1}' -f $Oz.RepoOwner, $Oz.RepoName
$Oz.ProfileUrl = 'https://github.com/{0}' -f $Oz.RepoOwner
$Oz.RainmeterUrl = 'https://www.rainmeter.net/'
$__ozBase     = if ($env:ProgramData) { $env:ProgramData } else { [IO.Path]::GetTempPath() }
$Oz.DataDir   = Join-Path $__ozBase 'Ozzyhn'
$Oz.Journal   = Join-Path $Oz.DataDir 'journal.json'
$Oz.Settings  = Join-Path $Oz.DataDir 'settings.json'
$Oz.LogDir    = Join-Path $Oz.DataDir 'logs'
$Oz.LogFile   = Join-Path $Oz.LogDir ('ozzyhn-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
$Oz.LogQueue  = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$Oz.Lang      = 'en'
$Oz.Es        = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$Oz.Tweaks    = @()
$Oz.Profiles  = @()
$Oz.Bloat     = @()
$Oz.Rows      = @{}
$Oz.UI        = @{}
$Oz.Chips     = @{}
$Oz.CatHeaders = @{}
$Oz.TweakIndex = @{}
$Oz.States    = @{}
$Oz.Chip      = 'ALL'
$Oz.Sys       = $null
$Oz.Window    = $null
$Oz.Busy      = $false
$Oz.Closing   = $false
$Oz.JournalData = $null
$Oz.RestoreDone = $false
$Oz.Inv       = [Globalization.CultureInfo]::InvariantCulture

# Fixed GUIDs so the app can always find (and remove) its own power plans
$Oz.PlanBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
$Oz.PlanPowerSaver = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$Oz.PlanPerf  = '0ad20f00-0220-4a7e-8e00-00000a7e0001'
$Oz.PlanSmart = '0ad20f00-0220-4a7e-8e00-00000a7e0002'
$Oz.PlanCool  = '0ad20f00-0220-4a7e-8e00-00000a7e0003'
#endregion

#region ============================ LANGUAGE ============================
function T {
    # Translates an English UI string. Spanish lives in $Oz.Es (see the SPANISH region),
    # stored with HTML entities so this file stays plain ASCII. Extra arguments fill {0}, {1}...
    param([string]$Text)
    $s = $Text
    if ($Oz.Lang -eq 'es' -and $Text) {
        $v = $null
        if ($Oz.Es.TryGetValue($Text, [ref]$v) -and $v) { $s = $v }
    }
    if ($s.IndexOf('&') -ge 0 -and $s.IndexOf(';') -gt 0) { $s = [System.Net.WebUtility]::HtmlDecode($s) }
    if ($args.Count) { try { $s = $s -f $args } catch { } }
    $s
}

function Initialize-OzSpanish {
    # Pairs: English line, Spanish line, blank line. \n stands for a line break.
    param([string]$Pairs)
    $block = New-Object System.Collections.Generic.List[string]
    foreach ($raw in (($Pairs -replace "`r", '') -split "`n") + @('')) {
        $line = $raw.TrimEnd()
        if ($line) { $block.Add($line); continue }
        if ($block.Count -ge 2) {
            $en = $block[0].Replace('\n', "`n"); $es = $block[1].Replace('\n', "`n")
            $Oz.Es[$en] = $es
        }
        $block.Clear()
    }
}

function Get-OzDefaultLanguage {
    try {
        foreach ($c in @((Get-UICulture), (Get-Culture))) { if ($c.TwoLetterISOLanguageName -eq 'es') { return 'es' } }
    } catch { }
    'en'
}

function Read-OzSettings {
    $s = @{}
    try {
        if (Test-Path -LiteralPath $Oz.Settings) {
            $j = Get-Content -LiteralPath $Oz.Settings -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $s[$p.Name] = $p.Value }
        }
    } catch { }
    $s
}

function Save-OzSettings {
    try {
        if (-not (Test-Path -LiteralPath $Oz.DataDir)) { New-Item -ItemType Directory -Path $Oz.DataDir -Force | Out-Null }
        [pscustomobject]@{ Lang = $Oz.Lang; Version = $Oz.Version } | ConvertTo-Json | Set-Content -LiteralPath $Oz.Settings -Encoding UTF8
    } catch { }
}
#endregion

#region ============================ DATA FOLDER SECURITY ============================
# C:\ProgramData lets any account create folders and files. The undo journal tells this app,
# which runs as administrator, which registry values to write back on revert, so a journal
# planted by a standard account could make it change any setting on the PC. The data folder is
# therefore locked so that only SYSTEM and Administrators can write to it (anyone can read).

function Get-OzAdminSids {
    @('S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
}

function Test-OzAdminOnly {
    # True when the file or folder is owned by SYSTEM / Administrators (or the admin running this
    # app), no other account has the rights in -Mask, and it is not a link pointing elsewhere.
    # The default mask: write, append, attributes, delete, change permissions or owner, generic write / all.
    param([string]$Path, [int]$Mask = 0x500D0156, [switch]$SkipInheritOnly)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
        if (-not $item.PSIsContainer -and $item.LinkType) { return $false }
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $ok = Get-OzAdminSids
        if ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $ok) { return $false }
        foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($r.AccessControlType -ne 'Allow' -or $r.IdentityReference.Value -in $ok) { continue }
            if ($SkipInheritOnly -and ($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)) { continue }
            if ([int]$r.FileSystemRights -band $Mask) { return $false }
        }
        return $true
    } catch { return $false }
}

function New-OzDataDirAcl {
    # SYSTEM and Administrators: full control. Users: read. Nothing inherited from ProgramData.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544'))
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($a in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
        $sid = New-Object Security.Principal.SecurityIdentifier $a[0]
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, [Security.AccessControl.FileSystemRights]$a[1], $inherit, [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)))
    }
    $acl
}

function Protect-OzDataDir {
    # Run once at startup, before anything in the data folder is read. Returns $false when the
    # folder cannot be made safe, and the app then refuses to start.
    # A folder that is not locked yet (made by version 1.1.0 or older, or by someone else) is
    # renamed and kept. The new folder is created already locked. The undo journal and settings
    # are carried over only if an administrator made the old folder and wrote those files.
    $dir = $Oz.DataDir
    if ((Test-Path -LiteralPath $dir -PathType Container) -and (Test-OzAdminOnly $dir)) { return $true }
    try {
        $old = $null; $carry = $false
        if ([IO.Directory]::Exists($dir) -or [IO.File]::Exists($dir)) {
            # Made by an admin, and no one else can delete, rename or re-permission what is inside
            $carry = Test-OzAdminOnly $dir 0x500D0040 -SkipInheritOnly
            $old = '{0}.old-{1}' -f $dir, (Get-Date -Format 'yyyyMMdd-HHmmss')
            Rename-Item -LiteralPath $dir -NewName (Split-Path -Leaf $old) -ErrorAction Stop
        }
        [void][IO.Directory]::CreateDirectory($dir, (New-OzDataDirAcl))
        if (-not (Test-OzAdminOnly $dir)) { throw 'the new folder is not locked (another program may have created it first).' }
        if ($old) {
            $Oz.DataDirOld = $old
            $Oz.DataDirCarried = $carry
            if ($carry) {
                foreach ($name in 'journal.json', 'settings.json') {
                    $f = Join-Path $old $name
                    if ([IO.File]::Exists($f) -and (Test-OzAdminOnly $f)) { [IO.File]::WriteAllBytes((Join-Path $dir $name), [IO.File]::ReadAllBytes($f)) }
                }
            }
        }
        return $true
    } catch {
        Write-Host ('The data folder {0} could not be made safe: {1}' -f $dir, $_.Exception.Message) -ForegroundColor Red
        Write-Host ('No se pudo proteger la carpeta de datos {0}: {1}' -f $dir, $_.Exception.Message) -ForegroundColor Red
        Write-Host 'Delete or rename that folder, then run the app again. / Borra o renombra esa carpeta y vuelve a abrir la app.' -ForegroundColor Yellow
        return $false
    }
}

function Write-OzDataDirNote {
    if (-not $Oz.DataDirOld) { return }
    if ($Oz.DataDirCarried) {
        Write-OzLog (T 'Data folder locked so only administrators can change it. Your undo journal was kept; older logs are in {0}' $Oz.DataDirOld) 'INFO'
    } else {
        Write-OzLog (T 'The old data folder could have been changed by a non-administrator account, so it was set aside without reading it: {0}. The undo journal starts empty. Use the System Restore point to undo older changes.' $Oz.DataDirOld) 'WARN'
    }
}
#endregion

#region ============================ LOGGING / UI HELPERS ============================
function Write-OzLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1,-4}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    try {
        if (-not (Test-Path -LiteralPath $Oz.LogDir)) { New-Item -ItemType Directory -Path $Oz.LogDir -Force | Out-Null }
        Add-Content -LiteralPath $Oz.LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
    # Background runspaces must not touch WPF controls: the UI thread picks the line up from the queue.
    if ($OzWorker) { $Oz.LogQueue.Enqueue(@($line, $Message, $Level)); return }
    Show-OzLogLine $line $Message $Level
}

function Show-OzLogLine {
    param([string]$Line, [string]$Message, [string]$Level)
    if ($Oz.UI.LogBox) {
        $Oz.UI.LogBox.AppendText($Line + "`r`n")
        $Oz.UI.LogBox.ScrollToEnd()
    }
    if ($Oz.UI.StatusText) {
        $Oz.UI.StatusText.Text = $Message
        $color = switch ($Level) { 'OK' { '#2BFF9A' } 'WARN' { '#FFB020' } 'ERR' { '#FF3B5C' } 'STEP' { '#00E5FF' } default { '#8A9BBF' } }
        $Oz.UI.StatusText.Foreground = Get-OzBrush $color
    } else {
        $fg = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERR' { 'Red' } 'STEP' { 'Cyan' } default { 'Gray' } }
        Write-Host $Line -ForegroundColor $fg
    }
}

function Show-OzQueuedLog {
    # Shows log lines written by background runspaces
    $item = $null
    $n = 0
    while ($n -lt 200 -and $Oz.LogQueue.TryDequeue([ref]$item)) { Show-OzLogLine $item[0] $item[1] $item[2]; $n++ }
}

function Update-OzUI {
    # Lets WPF repaint and handle input (scrolling, clicks) while work runs on the UI thread
    if ($Oz.Window) {
        try { $Oz.Window.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background) } catch { }
    }
}

function Set-OzBusy {
    param([bool]$On, [string]$Text = '')
    $Oz.Busy = $On
    if ($Oz.UI.BusyBar) { $Oz.UI.BusyBar.Visibility = $(if ($On) { 'Visible' } else { 'Collapsed' }) }
    if ($On -and $Text) { Write-OzLog $Text 'STEP' }
    Update-OzUI
}

function Invoke-OzSafe {
    # Single entry point for every button: blocks re-entry while busy and logs errors
    param([string]$Label, [scriptblock]$Action)
    if ($Oz.Busy) { Write-OzLog (T 'Busy - wait for the current task to finish.') 'WARN'; return }
    try { & $Action }
    catch { Write-OzLog ((T '{0} failed: {1}') -f (T $Label), $_.Exception.Message) 'ERR' }
    finally { if ($Oz.Busy) { Set-OzBusy $false } }
}

function Open-OzLink {
    # Opens a web page or settings link. explorer.exe hands it to the normal (non-admin)
    # desktop, which is what makes links work from this elevated window.
    param([string]$Url)
    if (-not $Url) { return }
    $isWeb = $Url -match '^https?://'
    try {
        if ($isWeb) { Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"{0}"' -f $Url) -ErrorAction Stop }
        else { Start-Process $Url -ErrorAction Stop }
        return
    } catch { }
    try { Start-Process $Url -ErrorAction Stop; return } catch { }
    try { [System.Windows.Clipboard]::SetText($Url) } catch { }
    Write-OzLog ((T 'Could not open the link, so it was copied to the clipboard: {0}') -f $Url) 'WARN'
}
#endregion

#region ============================ BACKGROUND WORK ============================
# Heavy work runs on background runspaces inside THIS process. The old Start-Job approach
# launched a whole new powershell.exe every time, which cost seconds before any work began.
function New-OzPool {
    # Every app function and the shared $Oz state are copied into each background runspace
    param([bool]$Bypass)
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if ($Bypass) { $iss.ExecutionPolicy = [Microsoft.PowerShell.ExecutionPolicy]::Bypass }
    foreach ($f in @(Get-ChildItem -Path function: | Where-Object { $_.Name -like '*-Oz*' -or $_.Name -ceq 'T' })) {
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $f.Name, $f.Definition))
    }
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'Oz', $Oz, 'Shared app state'))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'OzWorker', $true, 'Running on a background runspace'))
    $pool = [runspacefactory]::CreateRunspacePool($iss)
    [void]$pool.SetMinRunspaces(1)
    [void]$pool.SetMaxRunspaces(4)
    $pool.Open()
    $pool
}

function Get-OzPool {
    if ($Oz.Pool) { return $Oz.Pool }
    # Bypass lets Windows' own modules load even when scripts are restricted; fall back without it
    try { $Oz.Pool = New-OzPool $true } catch { $Oz.Pool = New-OzPool $false }
    $Oz.Pool
}

function Start-OzWorker {
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList = @())
    $ps = [powershell]::Create()
    $ps.RunspacePool = Get-OzPool
    # Re-parse the text so the block is not tied to the UI runspace
    [void]$ps.AddScript($ScriptBlock.ToString())
    foreach ($a in $ArgumentList) { [void]$ps.AddArgument($a) }
    $in = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
    $in.Complete()
    $out = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
    $h = $ps.BeginInvoke($in, $out)
    [pscustomobject]@{ PS = $ps; Handle = $h; Out = $out; Read = 0; Started = [DateTime]::Now }
}

function Receive-OzWorker {
    # Streams new string output to the log and returns new objects
    param($W)
    $new = New-Object System.Collections.ArrayList
    while ($W.Read -lt $W.Out.Count) {
        $o = $W.Out[$W.Read]
        $W.Read++
        if ($null -eq $o) { continue }
        $b = $o.PSObject.BaseObject
        if ($b -is [string]) { Write-OzLog $b }
        elseif ($b -is [System.Management.Automation.PSCustomObject]) { [void]$new.Add($o) }
        else { [void]$new.Add($b) }
    }
    Show-OzQueuedLog
    , $new.ToArray()
}

function Wait-OzWorker {
    # Waits for a worker while keeping the window responsive. Shows elapsed seconds in the status bar.
    param($W, [string]$Activity)
    $results = New-Object System.Collections.ArrayList
    $lastSec = -1
    try {
        while (-not $W.Handle.IsCompleted) {
            foreach ($o in (Receive-OzWorker $W)) { [void]$results.Add($o) }
            if ($Activity -and $Oz.UI.StatusText) {
                $sec = [int]([DateTime]::Now - $W.Started).TotalSeconds
                if ($sec -ne $lastSec -and $sec -ge 2) { $Oz.UI.StatusText.Text = '{0}  {1} s' -f $Activity, $sec; $lastSec = $sec }
            }
            Update-OzUI
            Start-Sleep -Milliseconds 15
        }
        try { [void]$W.PS.EndInvoke($W.Handle) }
        catch {
            $m = $_.Exception.Message
            if ($_.Exception.InnerException) { $m = $_.Exception.InnerException.Message }
            Write-OzLog $m 'WARN'
        }
        foreach ($o in (Receive-OzWorker $W)) { [void]$results.Add($o) }
        $n = 0
        foreach ($e in @($W.PS.Streams.Error)) { if ($e -and $n -lt 5) { Write-OzLog ([string]$e) 'WARN'; $n++ } }
    } finally { try { $W.PS.Dispose() } catch { } }
    , $results.ToArray()
}

function Invoke-OzJob {
    # Runs heavy work in the background so the window stays responsive.
    # Strings written by the job are streamed to the log; other objects are returned.
    param([scriptblock]$ScriptBlock, [object[]]$ArgumentList = @(), [string]$Activity = 'Working...')
    Set-OzBusy $true $Activity
    try {
        $w = Start-OzWorker -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
        $r = Wait-OzWorker $w $Activity
    } finally { Set-OzBusy $false }
    , $r
}

function Invoke-OzBlock {
    # Catalog script blocks belong to the UI runspace. On a background runspace they are
    # re-created from their text first, so they run safely on that thread.
    param([scriptblock]$Block)
    if ($OzWorker) { $Block = [scriptblock]::Create($Block.ToString()) }
    & $Block
}

function Start-OzConsole {
    # Opens a visible console for long built-in tools (SFC, DISM...) so the user sees progress
    param([string]$Title, [string]$Command)
    Write-OzLog ((T 'Opened console: {0}') -f $Title) 'STEP'
    Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/k title $Title & color 0B & $Command"
}

function Test-OzAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Format-OzNum {
    param([double]$Value, [string]$Format = '0.##')
    $Value.ToString($Format, $Oz.Inv)
}
#endregion

#region ============================ REGISTRY ENGINE ============================
function Get-OzReg {
    param([string]$Path, [string]$Name)
    $r = [ordered]@{ Exists = $false; Value = $null; Kind = $null }
    try {
        $key = Get-Item -LiteralPath $Path -ErrorAction Stop
        if (@($key.GetValueNames()) -contains $Name) {
            $r.Exists = $true
            $r.Value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $r.Kind = $key.GetValueKind($Name).ToString()
        }
    } catch { }
    [pscustomobject]$r
}

function ConvertTo-OzDword {
    param($Value)
    $v = [int64]$Value
    if ($v -gt [int32]::MaxValue) { return [BitConverter]::ToInt32([BitConverter]::GetBytes($v), 0) }
    [int32]$v
}

function Set-OzReg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
    switch ($Type) {
        'DWord'       { $Value = ConvertTo-OzDword $Value }
        'QWord'       { $Value = [int64]$Value }
        'Binary'      { $Value = [byte[]]@($Value | ForEach-Object { [byte]$_ }) }
        'MultiString' { $Value = [string[]]@($Value) }
        default       { $Value = [string]$Value }
    }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
}

function Remove-OzReg {
    param([string]$Path, [string]$Name)
    if (Test-Path -LiteralPath $Path) {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -Force -ErrorAction SilentlyContinue
    }
}

function Test-OzValueEqual {
    param($Actual, $Expected)
    if ($null -eq $Actual) { return $false }
    if ($Actual -is [array] -or $Expected -is [array]) {
        return ((@($Actual) -join ',') -eq (@($Expected) -join ','))
    }
    return ([string]$Actual -eq [string]$Expected)
}
#endregion

#region ============================ UNDO JOURNAL ============================
function ConvertTo-OzHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-OzHashtable $p.Value }
        return $h
    }
    if ($InputObject -is [array]) {
        $list = @()
        foreach ($i in $InputObject) { $list += , (ConvertTo-OzHashtable $i) }
        return , $list
    }
    return $InputObject
}

function Read-OzJournal {
    if ($null -ne $Oz.JournalData) { return $Oz.JournalData }
    $data = @{}
    if (Test-Path -LiteralPath $Oz.Journal) {
        try {
            $raw = Get-Content -LiteralPath $Oz.Journal -Raw -ErrorAction Stop
            if ($raw.Trim()) { $data = ConvertTo-OzHashtable ($raw | ConvertFrom-Json) }
        } catch {
            Write-OzLog 'Undo journal was unreadable - a backup copy was kept and a new one started.' 'WARN'
            Copy-Item -LiteralPath $Oz.Journal -Destination ($Oz.Journal + '.bad') -Force -ErrorAction SilentlyContinue
        }
    }
    if ($data -isnot [hashtable]) { $data = @{} }
    $Oz.JournalData = $data
    return $data
}

function Save-OzJournal {
    try {
        if (-not (Test-Path -LiteralPath $Oz.DataDir)) { New-Item -ItemType Directory -Path $Oz.DataDir -Force | Out-Null }
        $json = (Read-OzJournal) | ConvertTo-Json -Depth 12
        Set-Content -LiteralPath $Oz.Journal -Value $json -Encoding UTF8
    } catch { Write-OzLog "Could not save undo journal: $($_.Exception.Message)" 'WARN' }
}

function Get-OzJournalEntry {
    param([string]$Id, [switch]$Create)
    $j = Read-OzJournal
    if (-not $j.ContainsKey($Id)) {
        if (-not $Create) { return $null }
        $j[$Id] = @{ Applied = ''; Reg = @{}; Tasks = @{}; Data = @{} }
    }
    $e = $j[$Id]
    foreach ($k in 'Reg', 'Tasks', 'Data') { if ($e[$k] -isnot [hashtable]) { $e[$k] = @{} } }
    return $e
}

function Save-OzOriginalReg {
    param([string]$Id, [string]$Path, [string]$Name)
    $e = Get-OzJournalEntry $Id -Create
    $k = "$Path|$Name"
    if (-not $e.Reg.ContainsKey($k)) {
        $cur = Get-OzReg $Path $Name
        $val = $cur.Value
        if ($val -is [byte[]]) { $val = @($val | ForEach-Object { [int]$_ }) }
        $e.Reg[$k] = @{ Exists = $cur.Exists; Value = $val; Kind = $cur.Kind }
    }
}

function Set-OzData {
    param([string]$Id, [string]$Key, $Value, [switch]$OnlyIfMissing)
    $e = Get-OzJournalEntry $Id -Create
    if ($OnlyIfMissing -and $e.Data.ContainsKey($Key)) { return }
    $e.Data[$Key] = $Value
}

function Get-OzData {
    param([string]$Id, [string]$Key)
    $e = Get-OzJournalEntry $Id
    if ($e -and $e.Data.ContainsKey($Key)) { return $e.Data[$Key] }
    return $null
}
#endregion

#region ============================ SCHEDULED TASKS ============================
function Get-OzTask {
    param([string]$FullName)
    $i = $FullName.LastIndexOf('\')
    $path = $FullName.Substring(0, $i + 1)
    $name = $FullName.Substring($i + 1)
    try { Get-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $null }
}

function Get-OzTaskCom {
    # The Task Scheduler COM API answers in milliseconds; Get-ScheduledTask is much slower.
    param([string]$FullName)
    $i = $FullName.LastIndexOf('\')
    $folder = $FullName.Substring(0, $i)
    if (-not $folder) { $folder = '\' }
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $svc.GetFolder($folder).GetTask($FullName.Substring($i + 1))
}

function Get-OzTaskState {
    # Missing | Enabled | Disabled
    param([string]$FullName)
    try {
        $t = Get-OzTaskCom $FullName
        if ($t.Enabled) { return 'Enabled' } else { return 'Disabled' }
    } catch {
        # 0x80070002 / 0x80070003: the task or its folder does not exist on this PC.
        # PowerShell wraps the COM error, so look through the inner exceptions too.
        $ex = $_.Exception
        while ($ex) {
            if ($ex.HResult -in -2147024894, -2147024893 -or $ex.Message -match '0x8007000[23]') { return 'Missing' }
            $ex = $ex.InnerException
        }
    }
    $st = Get-OzTask $FullName
    if (-not $st) { 'Missing' } elseif ([string]$st.State -eq 'Disabled') { 'Disabled' } else { 'Enabled' }
}

function Set-OzTaskEnabled {
    param([string]$FullName, [bool]$Enabled)
    try { $t = Get-OzTaskCom $FullName; $t.Enabled = $Enabled; return }
    catch {
        $st = Get-OzTask $FullName
        if (-not $st) { throw }
        if ($Enabled) { $st | Enable-ScheduledTask -ErrorAction Stop | Out-Null }
        else { $st | Disable-ScheduledTask -ErrorAction Stop | Out-Null }
    }
}
#endregion

#region ============================ TWEAK ENGINE ============================
function Get-OzTweakState {
    # On  : the tweak is in effect on this PC right now
    # Off : it is not
    # NA  : nothing to act on here (the service / task does not exist on this PC)
    # Error : the state could not be read this time
    param($T)
    try {
        if ($T.Detect) { if (Invoke-OzBlock $T.Detect) { return 'On' } else { return 'Off' } }
        $checked = 0
        $protReg = @(Get-OzData $T.Id 'ProtectedReg' | Where-Object { $_ })
        foreach ($r in $T.Reg) {
            if ($r.OnlyIfExists -and -not (Test-Path -LiteralPath $r.P)) { continue }
            if ($r.Soft) { continue }   # applied, but Windows keeps re-writing it: not used to decide ON/OFF
            if ($protReg -contains "$($r.P)|$($r.N)") { continue }   # Windows does not allow changing it
            $checked++
            $cur = Get-OzReg $r.P $r.N
            if ($r.Remove) { if ($cur.Exists) { return 'Off' } else { continue } }
            if (-not $cur.Exists -or -not (Test-OzValueEqual $cur.Value $r.V)) { return 'Off' }
        }
        if ($T.Tasks.Count) {
            $protected = @(Get-OzData $T.Id 'ProtectedTasks' | Where-Object { $_ })
            foreach ($task in $T.Tasks) {
                if ($protected -contains $task) { continue }
                $st = Get-OzTaskState $task
                if ($st -eq 'Missing') { continue }
                $checked++
                if ($st -ne 'Disabled') { return 'Off' }
            }
        }
        if ($checked -eq 0) { return 'NA' }
        return 'On'
    } catch { return 'Error' }
}

function Test-OzTweak {
    # Returns $true when the tweak is currently in effect on this PC
    param($T)
    (Get-OzTweakState $T) -eq 'On'
}

function Test-OzAccessDenied {
    # True when the error is Windows refusing access (a value or key protected by TrustedInstaller)
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    while ($ex) {
        if ($ex -is [System.Security.SecurityException] -or $ex -is [System.UnauthorizedAccessException]) { return $true }
        $ex = $ex.InnerException
    }
    $false
}

function Invoke-OzTweakApply {
    param($T)
    foreach ($r in $T.Reg) {
        if ($r.OnlyIfExists -and -not (Test-Path -LiteralPath $r.P)) { continue }
        Save-OzOriginalReg $T.Id $r.P $r.N
        try {
            if ($r.Remove) { Remove-OzReg $r.P $r.N } else { Set-OzReg $r.P $r.N $r.V $r.T }
        } catch {
            if (-not (Test-OzAccessDenied $_)) { throw }
            # Windows protects a few values (some service keys). Remember them so they do not keep
            # the switch OFF, and skip them on revert: they were never changed.
            $k = "$($r.P)|$($r.N)"
            $prot = @(Get-OzData $T.Id 'ProtectedReg' | Where-Object { $_ })
            if ($prot -notcontains $k) { Set-OzData $T.Id 'ProtectedReg' (@($prot) + $k) }
            Write-OzLog ((T '  setting is protected by Windows, skipped: {0}') -f $k) 'WARN'
        }
    }
    foreach ($task in $T.Tasks) {
        $st = Get-OzTaskState $task
        if ($st -eq 'Missing') { continue }
        $e = Get-OzJournalEntry $T.Id -Create
        if (-not $e.Tasks.ContainsKey($task)) { $e.Tasks[$task] = $(if ($st -eq 'Disabled') { 'Disabled' } else { 'Ready' }) }
        if ($st -eq 'Disabled') { continue }
        try { Set-OzTaskEnabled $task $false }
        catch {
            # Windows protects a few tasks. Remember them so they do not keep the switch OFF.
            $prot = @(Get-OzData $T.Id 'ProtectedTasks' | Where-Object { $_ })
            if ($prot -notcontains $task) { Set-OzData $T.Id 'ProtectedTasks' (@($prot) + $task) }
            Write-OzLog ((T '  task is protected by Windows, skipped: {0}') -f $task) 'WARN'
        }
    }
    if ($T.Apply) { & $T.Apply }
    $e = Get-OzJournalEntry $T.Id -Create
    $e.Applied = (Get-Date).ToString('s')
    $e.Name = $T.Name
    $e.Ver = $Oz.Version
    Save-OzJournal
}

function Set-OzTracked {
    # For custom tweaks: remembers the original value, then writes the new one.
    # Everything written this way is restored automatically on revert.
    param([string]$Id, [string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    Save-OzOriginalReg $Id $Path $Name
    Set-OzReg $Path $Name $Value $Type
}

function Restore-OzOriginal {
    param([string]$Path, [string]$Name, $Orig, [string]$FallbackType = 'DWord')
    if ($Orig.Exists) {
        $kind = if ($Orig.Kind) { $Orig.Kind } else { $FallbackType }
        Set-OzReg $Path $Name $Orig.Value $kind
    } else { Remove-OzReg $Path $Name }
}

function Invoke-OzTweakRevert {
    param($T)
    $e = Get-OzJournalEntry $T.Id
    $done = @{}
    $protReg = @(Get-OzData $T.Id 'ProtectedReg' | Where-Object { $_ })
    foreach ($k in $protReg) { $done[$k] = $true }   # never changed, so nothing to restore
    foreach ($r in $T.Reg) {
        if ($r.OnlyIfExists -and -not (Test-Path -LiteralPath $r.P)) { continue }
        $k = "$($r.P)|$($r.N)"
        if ($done.ContainsKey($k)) { continue }
        $done[$k] = $true
        # One value Windows refuses must not stop the others from being restored
        try {
            if ($e -and $e.Reg.ContainsKey($k)) { Restore-OzOriginal $r.P $r.N $e.Reg[$k] $r.T }
            elseif ($null -eq $r.D) { Remove-OzReg $r.P $r.N }
            else { Set-OzReg $r.P $r.N $r.D $r.T }
        } catch {
            if (-not (Test-OzAccessDenied $_)) { throw }
            Write-OzLog ((T '  could not restore {0}') -f $k) 'WARN'
        }
    }
    if ($e) {
        # values written dynamically by custom tweaks (Set-OzTracked)
        foreach ($k in @($e.Reg.Keys)) {
            if ($done.ContainsKey($k)) { continue }
            $i = $k.LastIndexOf('|')
            try { Restore-OzOriginal $k.Substring(0, $i) $k.Substring($i + 1) $e.Reg[$k] }
            catch { Write-OzLog ((T '  could not restore {0}') -f $k) 'WARN' }
        }
    }
    foreach ($task in $T.Tasks) {
        $was = $null
        if ($e -and $e.Tasks.ContainsKey($task)) { $was = $e.Tasks[$task] }
        if ($was -eq 'Disabled') { continue }
        if ((Get-OzTaskState $task) -ne 'Disabled') { continue }
        try { Set-OzTaskEnabled $task $true } catch { Write-OzLog ((T '  could not re-enable task: {0}') -f $task) 'WARN' }
    }
    if ($T.Revert) { & $T.Revert }
    $j = Read-OzJournal
    if ($j.ContainsKey($T.Id)) { $j.Remove($T.Id) }
    Save-OzJournal
}

function Test-OzApplicable {
    param($T, $Sys)
    if (-not $Sys) { return $true }
    $b = [int]$Sys.OS.Build
    if ($T.MinBuild -and $b -lt $T.MinBuild) { return $false }
    if ($T.MaxBuild -and $b -gt $T.MaxBuild) { return $false }
    if ($T.Requires) { try { return [bool](Invoke-OzBlock $T.Requires) } catch { return $false } }
    return $true
}

function Test-OzRecommended {
    param($T, $Sys)
    if (-not $Sys) { return $false }
    foreach ($tok in @($T.Rec)) {
        switch ($tok) {
            'all'       { return $true }
            'laptop'    { if ($Sys.IsLaptop) { return $true } }
            'desktop'   { if (-not $Sys.IsLaptop -and -not $Sys.IsVM) { return $true } }
            'lowend'    { if ($Sys.Score.TierKey -in 'CHEAP', 'BUDGET') { return $true } }
            'highend'   { if ($Sys.Score.TierKey -in 'MIDRANGE', 'FANCY') { return $true } }
            'gaming'    { if (($Sys.GPU.Primary -and $Sys.GPU.Primary.Dedicated) -or $Sys.Score.TierKey -in 'MIDRANGE', 'FANCY') { return $true } }
            'hdd'       { if ($Sys.Storage.SystemKind -eq 'HDD') { return $true } }
            'ssd'       { if ($Sys.Storage.SystemKind -match 'SSD') { return $true } }
            'ram8plus'  { if ($Sys.Memory.GB -ge 8) { return $true } }
            'ram16plus' { if ($Sys.Memory.GB -ge 16) { return $true } }
            'win11'     { if ($Sys.OS.IsWin11) { return $true } }
        }
    }
    return $false
}

function Get-OzAllStates {
    # Reads the state of the given tweaks (runs on a background runspace at startup)
    param([object[]]$Tweaks)
    $h = @{}
    foreach ($t in $Tweaks) { $h[$t.Id] = Get-OzTweakState $t }
    $h
}
#endregion

#region ============================ POWER HELPERS ============================
function Invoke-OzPowercfg {
    param([string[]]$Arguments)
    $out = & "$env:SystemRoot\System32\powercfg.exe" @Arguments 2>&1
    return ($out | Out-String)
}

function Get-OzActivePlan {
    $txt = Invoke-OzPowercfg @('/getactivescheme')
    $guid = $null; $name = $null
    if ($txt -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $guid = $Matches[1].ToLower() }
    if ($txt -match '\(([^)]+)\)') { $name = $Matches[1] }
    [pscustomobject]@{ Guid = $guid; Name = $name }
}

function Get-OzActivePlanGuid {
    # Instant registry read instead of starting powercfg.exe
    $v = [string](Get-OzReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActivePowerScheme').Value
    if ($v -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { return $v.ToLower() }
    (Get-OzActivePlan).Guid
}

function Test-OzPlanActive {
    # Our plan is active - or this PC blocks custom plans and our settings went into its own plan
    param([string]$Id, [string]$Guid)
    $a = Get-OzActivePlanGuid
    if ($a -eq $Guid) { return $true }
    $fb = Get-OzData $Id 'FallbackPlan'
    [bool]($fb -and $a -eq [string]$fb)
}

function Test-OzPlanExists {
    param([string]$Guid)
    (Invoke-OzPowercfg @('/list')) -match [regex]::Escape($Guid)
}

function Get-OzPowerValue {
    # Returns @{AC; DC} for a setting of the active plan (locale-independent parsing)
    param([string]$Sub, [string]$Setting)
    $txt = Invoke-OzPowercfg @('/qh', 'scheme_current', $Sub, $Setting)
    $hex = [regex]::Matches($txt, '0x([0-9a-fA-F]{8})')
    if ($hex.Count -lt 2) { return $null }
    [pscustomobject]@{
        AC = [Convert]::ToInt32($hex[$hex.Count - 2].Groups[1].Value, 16)
        DC = [Convert]::ToInt32($hex[$hex.Count - 1].Groups[1].Value, 16)
    }
}

function Set-OzPowerValue {
    param([string]$Sub, [string]$Setting, $AC, $DC, [string]$Scheme = 'scheme_current')
    if ($null -ne $AC) { Invoke-OzPowercfg @('/setacvalueindex', $Scheme, $Sub, $Setting, [string]$AC) | Out-Null }
    if ($null -ne $DC) { Invoke-OzPowercfg @('/setdcvalueindex', $Scheme, $Sub, $Setting, [string]$DC) | Out-Null }
}

function Install-OzPlan {
    param([string]$Id, [string]$Guid, [string]$Name, [string]$Description, [object[]]$Settings)
    $active = Get-OzActivePlanGuid
    if ($active -and $active -notin @($Oz.PlanPerf, $Oz.PlanSmart, $Oz.PlanCool)) {
        Set-OzData $Id 'PreviousPlan' $active -OnlyIfMissing
    }
    if (-not (Test-OzPlanExists $Guid)) {
        Invoke-OzPowercfg @('/duplicatescheme', $Oz.PlanBalanced, $Guid) | Out-Null
    }
    Invoke-OzPowercfg @('/changename', $Guid, $Name, $Description) | Out-Null
    foreach ($s in $Settings) { Set-OzPowerValue -Sub $s[0] -Setting $s[1] -AC $s[2] -DC $s[3] -Scheme $Guid }
    Invoke-OzPowercfg @('/setactive', $Guid) | Out-Null
    $e = Get-OzJournalEntry $Id -Create
    if ($e.Data.ContainsKey('FallbackPlan')) { $e.Data.Remove('FallbackPlan') }
    if ((Get-OzActivePlanGuid) -ne $Guid) {
        Write-OzLog (T 'This PC blocks custom power plans (Modern Standby). The settings were applied to its own plan instead.') 'WARN'
        foreach ($s in $Settings) { Set-OzPowerValue -Sub $s[0] -Setting $s[1] -AC $s[2] -DC $s[3] }
        Invoke-OzPowercfg @('/setactive', 'scheme_current') | Out-Null
        Set-OzData $Id 'FallbackPlan' (Get-OzActivePlanGuid)
    }
}

function Remove-OzPlan {
    param([string]$Id, [string]$Guid)
    $prev = Get-OzData $Id 'PreviousPlan'
    if ((Get-OzActivePlanGuid) -eq $Guid) {
        $target = if ($prev -and (Test-OzPlanExists $prev)) { $prev } else { $Oz.PlanBalanced }
        Invoke-OzPowercfg @('/setactive', $target) | Out-Null
    }
    if (Test-OzPlanExists $Guid) { Invoke-OzPowercfg @('/delete', $Guid) | Out-Null }
}
#endregion

#region ============================ RESTORE POINT ============================
function New-OzRestorePoint {
    # Without -Force, a restore point from the last 24 hours (or from earlier in this session)
    # is reused: it already covers the changes, and making a new one takes 30-60 s.
    param([string]$Description = 'Ozzyhn Tweaks - before changes', [switch]$Force)
    if (-not $Force -and $Oz.RestoreDone) {
        Write-OzLog (T 'Restore point already made in this session - reusing it.') 'OK'
        return $true
    }
    $res = Invoke-OzJob -Activity (T 'Creating a System Restore point (can take a minute)...') -ArgumentList @($Description, [bool]$Force) -ScriptBlock {
        param($d, $force)
        if (-not $force) {
            try {
                $last = @(Get-ComputerRestorePoint -ErrorAction Stop) | Sort-Object SequenceNumber | Select-Object -Last 1
                if ($last) {
                    $when = [Management.ManagementDateTimeConverter]::ToDateTime([string]$last.CreationTime)
                    if (((Get-Date) - $when).TotalHours -lt 24) {
                        return [pscustomobject]@{ Ok = $true; Skipped = $true; When = $when; Msg = [string]$last.Description }
                    }
                }
            } catch { }
        }
        try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop } catch { }
        try {
            $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            New-ItemProperty -Path $k -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
        } catch { }
        try {
            Checkpoint-Computer -Description $d -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
            [pscustomobject]@{ Ok = $true; Skipped = $false; When = (Get-Date); Msg = '' }
        } catch { [pscustomobject]@{ Ok = $false; Skipped = $false; When = $null; Msg = $_.Exception.Message } }
    }
    $r = @($res) | Select-Object -First 1
    if ($r -and $r.Ok) {
        $Oz.RestoreDone = $true
        if ($r.Skipped) { Write-OzLog ((T 'Using the restore point from {0} ({1}) - it already covers these changes.') -f ([datetime]$r.When).ToString('yyyy-MM-dd HH:mm'), $r.Msg) 'OK' }
        else { Write-OzLog (T 'Restore point created.') 'OK' }
        return $true
    }
    $msg = if ($r) { $r.Msg } else { T 'unknown error' }
    Write-OzLog ((T 'Restore point not created ({0}). Changes are still tracked in the undo journal.') -f $msg) 'WARN'
    return $false
}
#endregion

#region ============================ HARDWARE SCAN ============================
function Get-OzCim {
    param([string]$Class, [string]$Namespace = 'root/cimv2', [string]$Filter)
    try {
        if ($Filter) { Get-CimInstance -Namespace $Namespace -ClassName $Class -Filter $Filter -ErrorAction Stop }
        else { Get-CimInstance -Namespace $Namespace -ClassName $Class -ErrorAction Stop }
    } catch { $null }
}

function Get-OzMemoryTypeName {
    param([int]$Code)
    switch ($Code) {
        20 { 'DDR' } 21 { 'DDR2' } 24 { 'DDR3' } 26 { 'DDR4' } 27 { 'LPDDR' } 28 { 'LPDDR2' }
        29 { 'LPDDR3' } 30 { 'LPDDR4' } 34 { 'DDR5' } 35 { 'LPDDR5' } default { 'Unknown' }
    }
}

function Get-OzGpuKind {
    # Returns @{Vendor; Dedicated} from a GPU name + PCI vendor id
    param([string]$Name, [string]$PnpId)
    $ven = ''
    if ($PnpId -match 'VEN_([0-9A-Fa-f]{4})') { $ven = $Matches[1].ToUpper() }
    $vendor = switch ($ven) {
        '10DE' { 'NVIDIA' } '1002' { 'AMD' } '1022' { 'AMD' } '8086' { 'Intel' } '5143' { 'Qualcomm' } '4D4F' { 'Qualcomm' }
        default {
            if ($Name -match 'NVIDIA|GeForce|Quadro|RTX') { 'NVIDIA' }
            elseif ($Name -match 'AMD|Radeon') { 'AMD' }
            elseif ($Name -match 'Intel') { 'Intel' }
            elseif ($Name -match 'Adreno|Qualcomm') { 'Qualcomm' }
            else { 'Other' }
        }
    }
    $dedicated = switch ($vendor) {
        'NVIDIA' { $true }
        'AMD' { ($Name -notmatch 'Graphics\s*$') -and ($Name -match 'RX|Pro|R9|R7|HD|FirePro|VII|Vega (56|64)') -and ($Name -notmatch '\d{4}G\b') }
        'Intel' { $Name -match 'Arc.*\b[AB]\d{3}' }
        default { $false }
    }
    [pscustomobject]@{ Vendor = $vendor; Dedicated = [bool]$dedicated }
}

function Get-OzSystemInfo {
    $os   = Get-OzCim Win32_OperatingSystem | Select-Object -First 1
    $cs   = Get-OzCim Win32_ComputerSystem | Select-Object -First 1
    $cpus = @(Get-OzCim Win32_Processor)
    $bb   = Get-OzCim Win32_BaseBoard | Select-Object -First 1
    $bios = Get-OzCim Win32_BIOS | Select-Object -First 1
    $enc  = Get-OzCim Win32_SystemEnclosure | Select-Object -First 1
    $bats = @(Get-OzCim Win32_Battery)
    $mems = @(Get-OzCim Win32_PhysicalMemory)
    $mArr = Get-OzCim Win32_PhysicalMemoryArray | Select-Object -First 1
    $gpus = @(Get-OzCim Win32_VideoController)
    $cv   = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue

    # ---------- Windows ----------
    $build = [int]$os.BuildNumber
    $osInfo = [pscustomobject]@{
        Caption        = [string]$os.Caption
        Family         = if ($build -ge 22000) { 'Windows 11' } elseif ($build -ge 10240) { 'Windows 10' } else { 'Unsupported Windows' }
        Build          = $build
        UBR            = $cv.UBR
        DisplayVersion = @($cv.DisplayVersion, $cv.ReleaseId) | Where-Object { $_ } | Select-Object -First 1
        Edition        = [string]$cv.EditionID
        IsWin11        = ($build -ge 22000)
        Arch           = [string]$os.OSArchitecture
        LastBoot       = $os.LastBootUpTime
        InstallDate    = $os.InstallDate
    }

    # ---------- CPU ----------
    $c = $cpus | Select-Object -First 1
    $cpuName = ([string]$c.Name -replace '\s+', ' ').Trim()
    $cpuVendor = if ($c.Manufacturer -match 'Intel') { 'Intel' } elseif ($c.Manufacturer -match 'AMD') { 'AMD' } elseif ($cpuName -match 'Snapdragon|Qualcomm') { 'Qualcomm' } else { [string]$c.Manufacturer }
    $cpuInfo = [pscustomobject]@{
        Name     = $cpuName
        Vendor   = $cpuVendor
        Sockets  = $cpus.Count
        Cores    = [int](($cpus | Measure-Object NumberOfCores -Sum).Sum)
        Threads  = [int](($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum)
        MaxMHz   = [int]$c.MaxClockSpeed
        L2KB     = [int]$c.L2CacheSize
        L3KB     = [int]$c.L3CacheSize
        Socket   = [string]$c.SocketDesignation
        Virt     = [bool]$c.VirtualizationFirmwareEnabled
        Arch     = switch ([int]$c.Architecture) { 0 { 'x86' } 9 { 'x64' } 12 { 'ARM64' } 5 { 'ARM' } default { 'x64' } }
    }

    # ---------- Memory ----------
    $installed = [int64](($mems | Measure-Object Capacity -Sum).Sum)
    if (-not $installed) { $installed = [int64]$cs.TotalPhysicalMemory }
    $m0 = $mems | Select-Object -First 1
    $memType = Get-OzMemoryTypeName ([int]$m0.SMBIOSMemoryType)
    $memInfo = [pscustomobject]@{
        GB         = [math]::Round($installed / 1GB, 1)
        Type       = $memType
        SpeedMTs   = [int](($mems | Measure-Object ConfiguredClockSpeed -Maximum).Maximum)
        RatedMTs   = [int](($mems | Measure-Object Speed -Maximum).Maximum)
        Modules    = $mems.Count
        Slots      = [int]$mArr.MemoryDevices
        Soldered   = ($memType -like 'LP*')
        FormFactor = switch ([int]$m0.FormFactor) { 8 { 'DIMM' } 12 { 'SO-DIMM' } default { '' } }
        Details    = @($mems | ForEach-Object {
                '{0} GB {1} {2} MT/s {3}' -f [math]::Round($_.Capacity / 1GB), ([string]$_.Manufacturer).Trim(), $_.ConfiguredClockSpeed, ([string]$_.PartNumber).Trim()
            })
    }

    # ---------- Storage ----------
    # Raw storage CIM classes: same data as Get-PhysicalDisk without loading the Storage module (much faster)
    $sysLetter = ([string]$env:SystemDrive).TrimEnd(':')
    $sns = 'root/Microsoft/Windows/Storage'
    $busNames = @{ 1 = 'SCSI'; 2 = 'ATAPI'; 3 = 'ATA'; 4 = '1394'; 5 = 'SSA'; 6 = 'Fibre Channel'; 7 = 'USB'; 8 = 'RAID'; 9 = 'iSCSI'; 10 = 'SAS'; 11 = 'SATA'; 12 = 'SD'; 13 = 'MMC'; 16 = 'Storage Spaces'; 17 = 'NVMe' }
    $mediaNames = @{ 3 = 'HDD'; 4 = 'SSD'; 5 = 'SCM' }
    $healthNames = @{ 0 = 'Healthy'; 1 = 'Warning'; 2 = 'Unhealthy' }
    $phys = @(Get-OzCim -Namespace $sns -Class 'MSFT_PhysicalDisk' | ForEach-Object {
            [pscustomobject]@{
                DeviceId = [string]$_.DeviceId; FriendlyName = [string]$_.FriendlyName; Size = [int64]$_.Size
                BusType = [string]$busNames[[int]$_.BusType]; MediaType = [string]$mediaNames[[int]$_.MediaType]
                HealthStatus = [string]$healthNames[[int]$_.HealthStatus]
            }
        })
    $sysDiskNum = $null
    $part = @(Get-OzCim -Namespace $sns -Class 'MSFT_Partition') | Where-Object { [string]$_.DriveLetter -eq $sysLetter } | Select-Object -First 1
    if ($part) { $sysDiskNum = $part.DiskNumber }
    $sysPhys = $phys | Where-Object { [string]$_.DeviceId -eq [string]$sysDiskNum } | Select-Object -First 1
    if (-not $sysPhys -and $phys.Count -eq 1) { $sysPhys = $phys[0] }
    $kind = 'Unknown'
    if ($sysPhys) {
        $bus = [string]$sysPhys.BusType; $media = [string]$sysPhys.MediaType
        if ($bus -eq 'NVMe') { $kind = 'NVMe SSD' }
        elseif ($media -eq 'SSD') { $kind = 'SATA SSD' }
        elseif ($media -eq 'HDD') { $kind = 'HDD' }
        elseif ($bus -in 'SD', 'MMC') { $kind = 'eMMC' }
        elseif ($sysPhys.FriendlyName -match 'NVMe') { $kind = 'NVMe SSD' }
        elseif ($sysPhys.FriendlyName -match 'SSD') { $kind = 'SATA SSD' }
    }
    $ld = Get-OzCim Win32_LogicalDisk -Filter "DeviceID='$($sysLetter):'" | Select-Object -First 1
    $freeGB = if ($ld) { [math]::Round($ld.FreeSpace / 1GB, 1) } else { 0 }
    $sizeGB = if ($ld) { [math]::Round($ld.Size / 1GB, 1) } else { 0 }
    $stoInfo = [pscustomobject]@{
        SystemKind  = $kind
        SystemModel = if ($sysPhys) { [string]$sysPhys.FriendlyName } else { '' }
        SizeGB      = $sizeGB
        FreeGB      = $freeGB
        FreePct     = if ($sizeGB) { [math]::Round(($freeGB / $sizeGB) * 100) } else { 0 }
        Disks       = @($phys | ForEach-Object {
                '{0} - {1} GB {2}/{3} ({4})' -f $_.FriendlyName, [math]::Round($_.Size / 1GB), $_.BusType, $_.MediaType, $_.HealthStatus
            })
    }

    # ---------- GPU ----------
    $vramMap = @{}
    $classKey = 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in @(Get-ChildItem -LiteralPath $classKey -ErrorAction SilentlyContinue)) {
        if ($k.PSChildName -notmatch '^\d{4}$') { continue }
        $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p.DriverDesc) { continue }
        $mem = $p.'HardwareInformation.qwMemorySize'
        if (-not $mem) {
            $m2 = $p.'HardwareInformation.MemorySize'
            if ($m2 -is [byte[]] -and $m2.Length -ge 4) { $mem = [BitConverter]::ToUInt32($m2, 0) } else { $mem = $m2 }
        }
        if ($mem) { $vramMap[[string]$p.DriverDesc] = [int64]$mem }
    }
    $gpuList = @(foreach ($g in $gpus) {
            $n = [string]$g.Name
            if (-not $n) { continue }
            $virtual = $n -match 'Basic Display|Basic Render|Remote|Virtual|Parsec|IddSample|DisplayLink|Citrix|Hyper-V|VMware|VirtualBox|Mirage|Spacedesk'
            $k = Get-OzGpuKind -Name $n -PnpId ([string]$g.PNPDeviceID)
            $vram = if ($vramMap.ContainsKey($n)) { $vramMap[$n] } elseif ($g.AdapterRAM) { [int64]$g.AdapterRAM } else { 0 }
            [pscustomobject]@{
                Name          = $n
                Vendor        = $k.Vendor
                Dedicated     = $k.Dedicated
                Virtual       = [bool]$virtual
                VramGB        = [math]::Round($vram / 1GB, 1)
                DriverVersion = [string]$g.DriverVersion
                DriverDate    = $g.DriverDate
                Resolution    = if ($g.CurrentHorizontalResolution) { '{0}x{1} @ {2} Hz' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate } else { '' }
            }
        })
    $realGpus = @($gpuList | Where-Object { -not $_.Virtual })
    $primary = $realGpus | Sort-Object @{ Expression = { $_.Dedicated }; Descending = $true }, @{ Expression = { $_.VramGB }; Descending = $true } | Select-Object -First 1
    if (-not $primary) { $primary = $gpuList | Select-Object -First 1 }
    $gpuInfo = [pscustomobject]@{ List = $gpuList; Primary = $primary }

    # ---------- Board / form factor ----------
    $model = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim()
    $isVM = $model -match 'Virtual|VMware|VirtualBox|KVM|QEMU|Xen|Parallels|Hyper-V|Bochs'
    $chassis = @($enc.ChassisTypes | ForEach-Object { [int]$_ })
    $laptopCh = 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32
    $desktopCh = 3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 34, 35, 36
    $isLaptop = ([int]$cs.PCSystemType -in 2, 8) -or [bool]($chassis | Where-Object { $_ -in $laptopCh })
    if (-not $isLaptop -and -not ($chassis | Where-Object { $_ -in $desktopCh }) -and $bats.Count -gt 0) { $isLaptop = $true }
    if ($isVM) { $isLaptop = $false }
    $form = if ($isVM) { 'Virtual Machine' } elseif ($isLaptop) { 'Laptop' } else { 'Desktop' }

    $biosDate = $null
    try { $biosDate = $bios.ReleaseDate } catch { }
    $boardInfo = [pscustomobject]@{
        SystemManufacturer = ([string]$cs.Manufacturer).Trim()
        SystemModel        = ([string]$cs.Model).Trim()
        Manufacturer       = ([string]$bb.Manufacturer).Trim()
        Product            = ([string]$bb.Product).Trim()
        BiosVersion        = ([string]$bios.SMBIOSBIOSVersion).Trim()
        BiosDate           = $biosDate
    }

    # ---------- Battery ----------
    $batInfo = [pscustomobject]@{ Present = ($bats.Count -gt 0); Charge = $null; WearPct = $null }
    if ($bats.Count -gt 0) {
        $batInfo.Charge = [int]($bats | Select-Object -First 1).EstimatedChargeRemaining
        $full = Get-OzCim -Namespace 'root/wmi' -Class 'BatteryFullChargedCapacity' | Select-Object -First 1
        $stat = Get-OzCim -Namespace 'root/wmi' -Class 'BatteryStaticData' | Select-Object -First 1
        if ($full.FullChargedCapacity -and $stat.DesignedCapacity) {
            $batInfo.WearPct = [math]::Max(0, [math]::Round((1 - ($full.FullChargedCapacity / $stat.DesignedCapacity)) * 100))
        }
    }

    # ---------- Security state ----------
    $dg = Get-OzCim -Namespace 'root/Microsoft/Windows/DeviceGuard' -Class 'Win32_DeviceGuard' | Select-Object -First 1
    $sb = $null
    try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch { }
    $tpm = Get-OzCim -Namespace 'root/cimv2/Security/MicrosoftTpm' -Class 'Win32_Tpm' | Select-Object -First 1
    $secInfo = [pscustomobject]@{
        VBS        = ([int]$dg.VirtualizationBasedSecurityStatus -eq 2)
        HVCI       = (@($dg.SecurityServicesRunning) -contains 2)
        SecureBoot = $sb
        TPM        = if ($tpm) { ([string]$tpm.SpecVersion -split ',')[0] } else { $null }
    }

    # Kinds of devices present (Bluetooth, Biometric...), so tweaks for missing hardware can be offered.
    # $null when Windows could not list them: then those tweaks stay hidden.
    $devClasses = $null
    try { $devClasses = @(Get-CimInstance -ClassName Win32_PnPEntity -Property PNPClass -ErrorAction Stop | ForEach-Object { [string]$_.PNPClass } | Where-Object { $_ } | Sort-Object -Unique) } catch { }

    $plan = Get-OzActivePlan

    $sys = [pscustomobject]@{
        OS       = $osInfo
        CPU      = $cpuInfo
        Memory   = $memInfo
        Storage  = $stoInfo
        GPU      = $gpuInfo
        Board    = $boardInfo
        Form     = $form
        IsLaptop = [bool]$isLaptop
        IsVM     = [bool]$isVM
        Battery  = $batInfo
        DevClasses = $devClasses
        Security = $secInfo
        Power    = $plan
        Score    = $null
        StartupCount = 0
    }
    $sys.Score = Get-OzScore -Sys $sys
    return $sys
}
#endregion

#region ============================ SCORING / TIERS ============================
function Limit-OzScore { param([double]$v) [int][math]::Max(5, [math]::Min(100, [math]::Round($v))) }

function Get-OzCpuScore {
    param([string]$Name, [int]$Threads)
    $s = switch ($Threads) {
        { $_ -le 2 } { 8; break }
        { $_ -le 4 } { 22; break }
        { $_ -le 6 } { 38; break }
        { $_ -le 8 } { 52; break }
        { $_ -le 12 } { 66; break }
        { $_ -le 16 } { 80; break }
        { $_ -le 24 } { 90; break }
        default { 100 }
    }
    if ($Name -match 'Celeron|Pentium|Atom|Athlon|Sempron|Core\(TM\)2|Core 2|\bA[4-9]-|\bE[12]-|\bN\d{3,4}\b') { $s = [math]::Min($s, 18) }
    if ($Name -match 'i[3579]-(\d{4,5})') {
        $d = $Matches[1]
        $gen = if ($d.Length -eq 5) { [int]$d.Substring(0, 2) } else { [int]$d.Substring(0, 1) }
        if ($gen -le 3) { $s -= 15 } elseif ($gen -le 6) { $s -= 8 } elseif ($gen -ge 12) { $s += 6 }
    }
    if ($Name -match 'Core\(TM\) Ultra|Core Ultra|Ryzen AI') { $s += 6 }
    if ($Name -match 'Ryzen\s+\d\s+(\d)\d{3}') {
        $series = [int]$Matches[1]
        if ($series -le 1) { $s -= 5 } elseif ($series -ge 7) { $s += 5 }
    }
    if ($Name -match 'i9-|Ryzen 9|Threadripper|Xeon W|Ultra 9') { $s += 5 }
    if ($Name -match '\d{4,5}[UY]\b') { $s -= 6 }
    Limit-OzScore $s
}

function Get-OzGpuScore {
    param($Gpu)
    if (-not $Gpu) { return 10 }
    $n = [string]$Gpu.Name
    if (-not $Gpu.Dedicated) {
        if ($n -match 'Iris Xe|Arc|[6-8][4-9]0M|Radeon 8\d0M') { return 32 }
        if ($n -match 'Vega|Radeon\(TM\) Graphics|Radeon Graphics|Iris|UHD Graphics 7') { return 22 }
        return 14
    }
    $v = [double]$Gpu.VramGB
    $s = if ($v -ge 16) { 100 } elseif ($v -ge 12) { 90 } elseif ($v -ge 10) { 82 } elseif ($v -ge 8) { 74 } elseif ($v -ge 6) { 62 } elseif ($v -ge 4) { 50 } elseif ($v -ge 2) { 36 } else { 25 }
    if ($n -match 'RTX\s?(40|50)\d{2}|RX\s?(7[6-9]|9[0-9])\d{2}|Arc.*B\d{3}') { $s += 6 }
    if ($n -match 'GT \d{3,4}\b|GTX\s?[6-9]\d{2}\b|HD [5-7]\d{3}|MX\s?\d{3}|R7 \d{3}') { $s -= 12 }
    # Class caps: xx50/xx60 cards are mid-range no matter how much VRAM they carry
    if ($n -match '(RTX|GTX)\s?\d{2}(50|60)\b|RX\s?\d6\d{2}\b|Arc.*A[3-7]\d{2}|Arc.*B5\d{2}') { $s = [math]::Min($s, 72) }
    elseif ($n -match '(RTX|GTX)\s?\d{2}70\b|RX\s?\d7\d{2}\b') { $s = [math]::Min($s, 86) }
    Limit-OzScore $s
}

function Get-OzRamScore {
    param([double]$GB)
    foreach ($step in @(@(3, 5), @(5, 15), @(7, 28), @(9, 42), @(13, 55), @(17, 66), @(33, 84))) {
        if ($GB -lt $step[0]) { return $step[1] }
    }
    return 100
}

function Get-OzStorageScore {
    param([string]$Kind)
    switch -Wildcard ($Kind) { 'NVMe*' { 100; break } '*SSD' { 75; break } 'eMMC' { 25; break } 'HDD' { 12; break } default { 50 } }
}

function Get-OzScore {
    param($Sys)
    $cpu = Get-OzCpuScore -Name $Sys.CPU.Name -Threads $Sys.CPU.Threads
    $gpu = Get-OzGpuScore -Gpu $Sys.GPU.Primary
    $ram = Get-OzRamScore -GB $Sys.Memory.GB
    $sto = Get-OzStorageScore -Kind $Sys.Storage.SystemKind
    $overall = [int][math]::Round($cpu * 0.30 + $gpu * 0.25 + $ram * 0.25 + $sto * 0.20)
    $tier = if ($overall -lt 34) { 'CHEAP' } elseif ($overall -lt 55) { 'BUDGET' } elseif ($overall -lt 75) { 'MIDRANGE' } else { 'FANCY' }
    $name = switch ($tier) {
        'CHEAP'    { 'CHEAP  /  REVIVE MODE' }
        'BUDGET'   { 'BUDGET' }
        'MIDRANGE' { 'MID-RANGE' }
        'FANCY'    { 'FANCY  /  HIGH-END' }
    }
    $color = switch ($tier) { 'CHEAP' { '#FF3B5C' } 'BUDGET' { '#FFB020' } 'MIDRANGE' { '#00E5FF' } 'FANCY' { '#FF2BD6' } }
    $bottleneck = @(
        [pscustomobject]@{ Part = 'CPU'; S = $cpu }, [pscustomobject]@{ Part = 'GPU'; S = $gpu },
        [pscustomobject]@{ Part = 'RAM'; S = $ram }, [pscustomobject]@{ Part = 'Storage'; S = $sto }
    ) | Sort-Object S | Select-Object -First 1
    [pscustomobject]@{
        Cpu = $cpu; Gpu = $gpu; Ram = $ram; Storage = $sto; Overall = $overall
        TierKey = $tier; TierName = $name; TierColor = $color; Bottleneck = $bottleneck.Part
    }
}
#endregion

#region ============================ LIVE STATS ============================
function Get-OzTemperature {
    if ($Oz.NoThermal) { return $null }
    $t = @()
    foreach ($z in @(Get-OzCim Win32_PerfFormattedData_Counters_ThermalZoneInformation)) {
        if ($z.HighPrecisionTemperature -gt 0) { $t += ($z.HighPrecisionTemperature / 10.0) - 273.15 }
        elseif ($z.Temperature -gt 0) { $t += $z.Temperature - 273.15 }
    }
    if (-not $t) {
        foreach ($z in @(Get-OzCim -Namespace 'root/wmi' -Class 'MSAcpi_ThermalZoneTemperature')) {
            if ($z.CurrentTemperature -gt 0) { $t += ($z.CurrentTemperature / 10.0) - 273.15 }
        }
    }
    $t = @($t | Where-Object { $_ -gt 5 -and $_ -lt 125 })
    if (-not $t) { $Oz.NoThermal = $true; return $null }
    [int][math]::Round(($t | Measure-Object -Maximum).Maximum)
}

function Get-OzLiveStats {
    $p = Get-OzCim Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" | Select-Object -First 1
    $pi = Get-OzCim Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" | Select-Object -First 1
    $os = Get-OzCim Win32_OperatingSystem | Select-Object -First 1
    $ramPct = 0; $ramUsed = 0
    if ($os.TotalVisibleMemorySize) {
        $ramUsed = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB
        $ramPct = [int](100 * ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize)
    }
    $mhz = $null
    if ($pi -and $pi.PercentProcessorPerformance -and $Oz.Sys) { $mhz = [int]($Oz.Sys.CPU.MaxMHz * $pi.PercentProcessorPerformance / 100) }
    $up = $null
    if ($os.LastBootUpTime) { $up = (Get-Date) - $os.LastBootUpTime }
    [pscustomobject]@{
        Cpu       = [int]$p.PercentProcessorTime
        ClockMHz  = $mhz
        RamPct    = $ramPct
        RamUsedGB = [math]::Round($ramUsed, 1)
        Temp      = Get-OzTemperature
        Uptime    = $up
        Procs     = @(Get-Process -ErrorAction SilentlyContinue).Count
    }
}
#endregion

#region ============================ INSIGHTS ============================
function New-OzInsight {
    param([ValidateSet('crit', 'warn', 'info', 'good')][string]$Level, [string]$Title, [string]$Text, [string]$Go)
    [pscustomobject]@{ Level = $Level; Title = $Title; Text = $Text; Go = $Go }
}

function Get-OzInsights {
    param($Sys)
    $list = New-Object System.Collections.ArrayList
    $add = { param($i) [void]$list.Add($i) }

    if ($Sys.IsVM) { & $add (New-OzInsight info (T 'Virtual machine detected') (T 'Hardware-specific tweaks (power plans, NIC, GPU) are skipped automatically. Privacy and debloat work normally.')) }

    switch ($Sys.Storage.SystemKind) {
        'HDD' { & $add (New-OzInsight crit (T 'Windows is on a hard disk (HDD)') (T 'This is the #1 slowdown on this PC. Even a basic SATA SSD makes boot and app launches dramatically faster. REVIVE tunes Windows for HDDs until then.') 'Profiles') }
        'eMMC' { & $add (New-OzInsight warn (T 'Windows is on slow eMMC storage') (T 'Keep at least 10 GB free and use CompactOS in TOOLS to free 2-4 GB.') 'Tools') }
        'NVMe SSD' { & $add (New-OzInsight good (T 'NVMe SSD detected') (T 'Storage is fast. Tweaks that only help hard disks are not recommended here.')) }
    }

    $gb = [double]$Sys.Memory.GB
    if ($gb -lt 4) { & $add (New-OzInsight crit (T 'Only {0} GB of RAM' $gb) (T 'Windows will swap constantly. REVIVE trims background apps; adding RAM is the best hardware fix.') 'Profiles') }
    elseif ($gb -lt 8) { & $add (New-OzInsight warn (T '{0} GB of RAM' $gb) (T 'Windows feels smooth from 8 GB. REVIVE disables background apps and visual effects to save memory.') 'Profiles') }
    elseif ($gb -ge 16) { & $add (New-OzInsight good (T '{0} GB of RAM' $gb) (T 'Plenty of memory for gaming and multitasking.')) }

    if ($Sys.Memory.Modules -eq 1 -and -not $Sys.Memory.Soldered -and $Sys.Memory.Slots -gt 1) {
        & $add (New-OzInsight warn (T 'RAM is running single-channel') (T 'Only one memory module is installed. Adding a matching second module doubles memory bandwidth, which is often a big FPS gain on integrated graphics.'))
    }
    if (-not $Sys.IsLaptop -and -not $Sys.IsVM) {
        $speed = [int]$Sys.Memory.SpeedMTs
        if (($Sys.Memory.Type -eq 'DDR4' -and $speed -gt 0 -and $speed -le 2666) -or ($Sys.Memory.Type -eq 'DDR5' -and $speed -gt 0 -and $speed -le 4800)) {
            & $add (New-OzInsight info (T 'RAM runs at {0} MT/s' $speed) (T 'If the sticker on your RAM shows a higher speed, enable XMP / EXPO in the BIOS. It is free performance and runs within the kit rating.'))
        }
    }

    if ($Sys.Storage.FreePct -gt 0 -and $Sys.Storage.FreePct -lt 15) {
        & $add (New-OzInsight warn (T 'Drive {0} is almost full ({1} GB free)' $env:SystemDrive $Sys.Storage.FreeGB) (T 'Low free space slows Windows and updates. Use CLEAN UP FILES in TOOLS.') 'Tools')
    }

    if (-not $Sys.OS.IsWin11 -and $Sys.OS.Build -ge 10240) {
        & $add (New-OzInsight warn (T 'Windows 10 is past end of support') (T 'Standard security updates ended in October 2025. If this PC meets the Windows 11 requirements, upgrading keeps it protected.'))
    }
    if ($Sys.OS.Build -lt 10240) {
        & $add (New-OzInsight crit (T 'Unsupported Windows version') (T 'This tool targets Windows 10 and 11. Some features will not work.'))
    }

    if ($Sys.Security.HVCI -and $Sys.GPU.Primary -and $Sys.GPU.Primary.Dedicated) {
        & $add (New-OzInsight info (T 'Memory Integrity (VBS / HVCI) is ON') (T 'It protects against kernel attacks and costs a few % of FPS in some games. The switch is in the DANGER ZONE - only turn it off if you accept that trade.') 'Tweaks')
    }

    if ($Sys.Power.Guid -eq $Oz.PlanPowerSaver -and -not $Sys.IsLaptop) {
        & $add (New-OzInsight warn (T 'Power Saver plan on a desktop') (T 'Your CPU is being held back. Apply the OZZYHN PERFORMANCE plan.') 'Profiles')
    }

    if ($Sys.IsLaptop) {
        & $add (New-OzInsight info (T 'Laptop detected') (T 'Use COOL & QUIET for lower temperatures and battery life. MAX PERFORMANCE is best only while plugged in.') 'Profiles')
        if ($Sys.Battery.WearPct -ge 30) {
            & $add (New-OzInsight warn (T 'Battery has {0}% wear' $Sys.Battery.WearPct) (T 'A worn battery holds less charge and can make some laptops throttle. Consider a replacement.'))
        }
    }

    $gpu = $Sys.GPU.Primary
    if ($gpu -and $gpu.DriverDate) {
        $age = ((Get-Date) - [datetime]$gpu.DriverDate).Days
        if ($age -gt 180 -and $gpu.Vendor -in 'NVIDIA', 'AMD', 'Intel') {
            & $add (New-OzInsight warn (T 'Graphics driver is {0} days old' $age) (T 'New {0} drivers often fix stutter and add FPS. See the DRIVERS tab for the official download.' $gpu.Vendor) 'Drivers')
        }
    }

    if ($Sys.StartupCount -gt 8) {
        & $add (New-OzInsight warn (T '{0} apps start with Windows' $Sys.StartupCount) (T 'Each one slows boot and eats RAM. Turn off the ones you do not need in TOOLS > STARTUP APPS.') 'Tools')
    }

    if ($Sys.Score.TierKey -eq 'FANCY') {
        & $add (New-OzInsight good (T 'High-end hardware') (T 'Focus on latency and smoothness: COMPETITIVE GAMING or MAX PERFORMANCE profiles.') 'Profiles')
    } elseif ($Sys.Score.TierKey -eq 'CHEAP') {
        & $add (New-OzInsight info (T 'Revive mode recommended') (T 'Weakest part: {0}. The REVIVE profile strips Windows down so this PC feels usable again.' (T $Sys.Score.Bottleneck)) 'Profiles')
    }

    return $list.ToArray()
}

function Get-OzSpecSheet {
    param($Sys)
    $g = $Sys.GPU.Primary
    $lines = @(
        "=== $($Oz.AppName) v$($Oz.Version) - Spec Sheet ===",
        ('Class    : {0}  (OZ Score {1}/100, weakest part: {2})' -f $Sys.Score.TierName, $Sys.Score.Overall, $Sys.Score.Bottleneck),
        ('Type     : {0}' -f $Sys.Form),
        ('Windows  : {0} {1} build {2}.{3} ({4})' -f $Sys.OS.Family, $Sys.OS.DisplayVersion, $Sys.OS.Build, $Sys.OS.UBR, $Sys.OS.Edition),
        ('CPU      : {0} | {1}C/{2}T | {3} MHz | L2 {4} KB L3 {5} KB | {6}' -f $Sys.CPU.Name, $Sys.CPU.Cores, $Sys.CPU.Threads, $Sys.CPU.MaxMHz, $Sys.CPU.L2KB, $Sys.CPU.L3KB, $Sys.CPU.Socket)
    )
    foreach ($x in $Sys.GPU.List) { $lines += ('GPU      : {0} | {1} GB | driver {2}' -f $x.Name, $x.VramGB, $x.DriverVersion) }
    $lines += ('Memory   : {0} GB {1} @ {2} MT/s | {3} module(s) / {4} slot(s)' -f $Sys.Memory.GB, $Sys.Memory.Type, $Sys.Memory.SpeedMTs, $Sys.Memory.Modules, $Sys.Memory.Slots)
    foreach ($d in $Sys.Memory.Details) { $lines += "           $d" }
    $lines += ('Storage  : {0} {1} | {2} GB free of {3} GB' -f $Sys.Storage.SystemKind, $Sys.Storage.SystemModel, $Sys.Storage.FreeGB, $Sys.Storage.SizeGB)
    foreach ($d in $Sys.Storage.Disks) { $lines += "           $d" }
    $lines += ('Board    : {0} {1} | BIOS {2}' -f $Sys.Board.Manufacturer, $Sys.Board.Product, $Sys.Board.BiosVersion)
    $lines += ('System   : {0} {1}' -f $Sys.Board.SystemManufacturer, $Sys.Board.SystemModel)
    $lines += ('Security : VBS {0} | HVCI {1} | Secure Boot {2} | TPM {3}' -f $Sys.Security.VBS, $Sys.Security.HVCI, $Sys.Security.SecureBoot, $Sys.Security.TPM)
    if ($Sys.Battery.Present) { $lines += ('Battery  : {0}% charge | wear {1}%' -f $Sys.Battery.Charge, $Sys.Battery.WearPct) }
    $lines += ('Power    : {0}' -f $Sys.Power.Name)
    $lines += ''
    $lines += ('--- {0} {1} by {2} - {3} ---' -f $Oz.AppName, $Oz.Version, $Oz.Brand, $Oz.ProfileUrl)
    return ($lines -join "`r`n")
}
#endregion

#region ============================ DRIVERS ============================
$Oz.Links = @{
    Nvidia      = 'https://www.nvidia.com/Download/index.aspx'
    NvidiaApp   = 'https://www.nvidia.com/en-us/software/nvidia-app/'
    Amd         = 'https://www.amd.com/en/support/downloads/drivers.html'
    IntelDsa    = 'https://www.intel.com/content/www/us/en/support/detect.html'
    NVCleanstall = 'https://www.techpowerup.com/download/techpowerup-nvcleanstall/'
    Ddu         = 'https://www.wagnardsoft.com/'
}

function Get-OzOemDomain {
    param([string]$Maker)
    switch -Regex ($Maker) {
        'Dell|Alienware' { 'dell.com'; break } 'HP|Hewlett' { 'hp.com'; break } 'Lenovo' { 'lenovo.com'; break } 'ASUS' { 'asus.com'; break }
        'Acer' { 'acer.com'; break } 'Micro-Star|MSI' { 'msi.com'; break } 'Gigabyte' { 'gigabyte.com'; break } 'ASRock' { 'asrock.com'; break }
        'Microsoft' { 'microsoft.com'; break } 'Samsung' { 'samsung.com'; break } 'Razer' { 'razer.com'; break } 'Toshiba|Dynabook' { 'dynabook.com'; break }
        'Huawei' { 'huawei.com'; break } 'Gateway' { 'gateway.com'; break } 'Medion' { 'medion.com'; break } 'Biostar' { 'biostar.com.tw'; break }
        default { '' }
    }
}

function Get-OzSearchUrl {
    param([string]$Query, [string]$Site)
    $q = if ($Site) { "$Query site:$Site" } else { $Query }
    'https://www.google.com/search?q=' + [uri]::EscapeDataString($q)
}

function Get-OzDriverRecommendations {
    param($Sys)
    $recs = New-Object System.Collections.ArrayList
    $add = { param($cat, $title, $text, $url, $btn) [void]$recs.Add([pscustomobject]@{ Cat = $cat; Title = $title; Text = $text; Url = $url; Button = $btn }) }

    foreach ($g in @($Sys.GPU.List | Where-Object { -not $_.Virtual })) {
        switch ($g.Vendor) {
            'NVIDIA' {
                & $add 'GPU' $g.Name (T 'Installed driver {0}. Get the latest Game Ready / Studio driver directly from NVIDIA.' $g.DriverVersion) $Oz.Links.Nvidia (T 'NVIDIA DRIVERS')
                & $add 'GPU' (T 'NVCleanstall (optional)') (T 'Installs the NVIDIA driver without telemetry and extras. Good for lean, low-latency setups.') $Oz.Links.NVCleanstall 'NVCLEANSTALL'
            }
            'AMD' { & $add 'GPU' $g.Name (T 'Installed driver {0}. AMD Software: Adrenalin Edition from AMD (auto-detect tool available).' $g.DriverVersion) $Oz.Links.Amd (T 'AMD DRIVERS') }
            'Intel' { & $add 'GPU' $g.Name (T 'Installed driver {0}. Intel Driver & Support Assistant finds the right Intel graphics driver.' $g.DriverVersion) $Oz.Links.IntelDsa 'INTEL DSA' }
            'Qualcomm' { & $add 'GPU' $g.Name (T 'Qualcomm graphics drivers are delivered by your laptop maker and Windows Update.') 'ms-settings:windowsupdate-optionalupdates' (T 'OPTIONAL UPDATES') }
        }
    }
    if (@($Sys.GPU.List | Where-Object { $_.Vendor -in 'NVIDIA', 'AMD' }).Count -gt 0) {
        & $add 'GPU' (T 'Display Driver Uninstaller (clean reinstall)') (T 'Fixes broken or stuttering GPU drivers by removing every trace before a fresh install. Use it offline, then install the new driver.') $Oz.Links.Ddu 'DDU'
    }

    switch ($Sys.CPU.Vendor) {
        'Intel' { & $add 'Chipset' (T 'Intel chipset / ME / Wi-Fi / Bluetooth') (T 'Intel DSA scans and updates Intel chipset, Management Engine, Wi-Fi and Bluetooth drivers.') $Oz.Links.IntelDsa 'INTEL DSA' }
        'AMD' { & $add 'Chipset' (T 'AMD Ryzen chipset driver') (T 'Includes the AMD power plans and scheduler support that Ryzen CPUs need for full boost and correct core parking.') $Oz.Links.Amd (T 'AMD CHIPSET') }
    }

    $oemMaker = $Sys.Board.SystemManufacturer
    $oemModel = $Sys.Board.SystemModel
    $diy = ($oemMaker -match 'System manufacturer|To Be Filled|Default string|O.E.M.') -or (-not $oemModel) -or ($oemModel -match 'System Product Name|To Be Filled|Default string')
    if ($Sys.IsLaptop -or -not $diy) {
        $site = Get-OzOemDomain $oemMaker
        & $add 'OEM' ('{0} {1}' -f $oemMaker, $oemModel) (T 'Laptops and brand PCs need the maker''s drivers for touchpad, hotkeys, audio, fans and power. Always check here first.') (Get-OzSearchUrl "$oemMaker $oemModel drivers download" $site) (T 'SUPPORT PAGE')
    }
    if (-not $Sys.IsLaptop -and $Sys.Board.Product) {
        $site = Get-OzOemDomain $Sys.Board.Manufacturer
        & $add 'Board' ('{0} {1}' -f $Sys.Board.Manufacturer, $Sys.Board.Product) (T 'BIOS {0}. Board page has LAN, audio and BIOS updates. Newer BIOS can improve RAM stability and CPU support.' $Sys.Board.BiosVersion) (Get-OzSearchUrl "$($Sys.Board.Manufacturer) $($Sys.Board.Product) support drivers BIOS" $site) (T 'BOARD SUPPORT')
    }

    foreach ($n in @(Get-OzCim Win32_NetworkAdapter -Filter 'PhysicalAdapter=True')) {
        $name = [string]$n.Name
        if ($name -match 'Virtual|VPN|Bluetooth|WAN|Hyper-V|TAP|Loopback') { continue }
        if ($name -match 'Intel|Killer') { & $add 'Network' $name (T 'Intel / Killer network adapters are updated with Intel DSA.') $Oz.Links.IntelDsa 'INTEL DSA' }
        elseif ($name -match 'Realtek|MediaTek|Qualcomm|Atheros|Broadcom|Marvell|Aquantia') {
            & $add 'Network' $name (T 'Get this driver from your board or laptop support page (above), or Windows Update optional drivers.') 'ms-settings:windowsupdate-optionalupdates' (T 'OPTIONAL UPDATES')
        }
    }
    & $add 'Windows' (T 'Windows Update - optional drivers') (T 'Microsoft-certified drivers for your exact hardware. Safe and easy.') 'ms-settings:windowsupdate-optionalupdates' (T 'OPEN')
    return $recs.ToArray()
}

function Get-OzDriverScan {
    # Heavy WMI queries run in a background job
    $res = Invoke-OzJob -Activity (T 'Scanning drivers and devices...') -ScriptBlock {
        T 'Reading installed drivers...'
        $drivers = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object {
                $_.DeviceName -and (
                    $_.DeviceClass -eq 'DISPLAY' -or
                    ($_.DeviceClass -in 'NET', 'MEDIA', 'BLUETOOTH', 'SYSTEM', 'HDC', 'SCSIADAPTER', 'USB' -and $_.DriverProviderName -notmatch 'Microsoft')
                ) -and $_.DeviceName -notmatch 'WAN Miniport|Virtual|Hyper-V|Microsoft'
            } | ForEach-Object {
                [pscustomobject]@{
                    Kind = 'Driver'; Class = $_.DeviceClass; Name = $_.DeviceName; Provider = $_.DriverProviderName
                    Version = $_.DriverVersion; Date = $_.DriverDate
                }
            })
        T 'Checking for devices with problems...'
        $problems = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction SilentlyContinue |
                Where-Object { $_.ConfigManagerErrorCode -ne 45 } | ForEach-Object {
                    [pscustomobject]@{ Kind = 'Problem'; Name = $(if ($_.Name) { $_.Name } else { $_.DeviceID }); Code = [int]$_.ConfigManagerErrorCode; Id = $_.DeviceID }
                })
        $drivers + $problems
    }
    $codes = @{
        1 = 'not configured'; 3 = 'driver may be corrupted'; 10 = 'cannot start'; 12 = 'resource conflict'; 14 = 'needs restart'
        18 = 'reinstall driver'; 22 = 'disabled'; 24 = 'not present / no driver'; 28 = 'driver NOT installed'; 31 = 'not working'
        39 = 'driver corrupted or missing'; 43 = 'device reported a problem'; 52 = 'unsigned driver blocked'
    }
    $Oz.DeviceCodes = $codes
    $drv = @($res | Where-Object { $_.Kind -eq 'Driver' } | ForEach-Object {
            $d = $_.Date; $age = $null
            try { if ($d) { $age = ((Get-Date) - [datetime]$d).Days } } catch { }
            $_ | Add-Member -NotePropertyName AgeDays -NotePropertyValue $age -PassThru -Force
        } | Sort-Object @{ Expression = { $_.Class -ne 'DISPLAY' } }, Class, Name)
    $prob = @($res | Where-Object { $_.Kind -eq 'Problem' } | ForEach-Object {
            $m = if ($codes.ContainsKey($_.Code)) { $codes[$_.Code] } else { 'error code {0}' -f $_.Code }
            $_ | Add-Member -NotePropertyName Meaning -NotePropertyValue $m -PassThru -Force
        })
    [pscustomobject]@{ Drivers = $drv; Problems = $prob }
}
#endregion

#region ============================ TWEAK CATALOG ============================
# Every tweak is data: registry values, services and scheduled tasks are applied,
# detected and reverted by the generic engine. Custom ones add Apply/Revert/Detect.
#   Risk : Safe | Moderate | Advanced | Danger   (Danger is never in a profile)
#   Rec  : tokens deciding if it is recommended for THIS PC
#          all, laptop, desktop, lowend, highend, gaming, hdd, ssd, ram8plus, ram16plus, win11, none

$Oz.Categories = @(
    [pscustomobject]@{ Key = 'Privacy';     Name = 'PRIVACY & TELEMETRY' }
    [pscustomobject]@{ Key = 'AI';          Name = 'AI & COPILOT' }
    [pscustomobject]@{ Key = 'Performance'; Name = 'PERFORMANCE' }
    [pscustomobject]@{ Key = 'Gaming';      Name = 'GAMING & INPUT' }
    [pscustomobject]@{ Key = 'Power';       Name = 'POWER & THERMALS' }
    [pscustomobject]@{ Key = 'Services';    Name = 'SERVICES' }
    [pscustomobject]@{ Key = 'Network';     Name = 'NETWORK & LATENCY' }
    [pscustomobject]@{ Key = 'Explorer';    Name = 'EXPLORER & UI' }
    [pscustomobject]@{ Key = 'Start';       Name = 'START, TASKBAR & SEARCH' }
    [pscustomobject]@{ Key = 'Apps';        Name = 'EDGE, ONEDRIVE & STORE' }
    [pscustomobject]@{ Key = 'Installed';   Name = 'INSTALLED APPS' }
    [pscustomobject]@{ Key = 'Update';      Name = 'WINDOWS UPDATE' }
    [pscustomobject]@{ Key = 'Storage';     Name = 'STORAGE & NTFS' }
    [pscustomobject]@{ Key = 'Security';    Name = 'SECURITY HARDENING' }
    [pscustomobject]@{ Key = 'Danger';      Name = 'DANGER ZONE' }
)

function Add-OzTweak {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Cat,
        [Parameter(Mandatory)][string]$Name,
        [string]$Desc = '',
        [ValidateSet('Safe', 'Moderate', 'Advanced', 'Danger')][string]$Risk = 'Safe',
        [object[]]$Reg = @(),
        [object[]]$Svc = @(),
        [string[]]$Tasks = @(),
        [scriptblock]$Apply, [scriptblock]$Revert, [scriptblock]$Detect, [scriptblock]$Requires,
        [string[]]$Rec = @('none'),
        [int]$MinBuild = 0, [int]$MaxBuild = 0,
        [switch]$Reboot, [switch]$Explorer,
        [string]$Group = '', [string]$Note = ''
    )
    if ($Cat -eq 'Danger') { $Risk = 'Danger' }
    $regs = @()
    foreach ($r in $Reg) {
        # Read with the indexer: on a hashtable, $r.Remove (when the key is missing) returns the
        # built-in .Remove() METHOD, which counts as $true. v1.0 used that, so every registry tweak
        # deleted its value instead of writing it.
        $regs += @{
            P = $r['P']; N = $r['N']; V = $r['V']; T = $(if ($r['T']) { $r['T'] } else { 'DWord' }); D = $r['D']
            Remove = [bool]$r['Remove']; OnlyIfExists = [bool]$r['OnlyIfExists']; Soft = [bool]$r['Soft']
        }
    }
    foreach ($s in $Svc) {
        $regs += @{ P = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s['N'])"; N = 'Start'; V = $s['V']; T = 'DWord'; D = $s['D']; Remove = $false; OnlyIfExists = $true; Soft = $false }
    }
    $Oz.Tweaks += [pscustomobject]@{
        Id = $Id; Cat = $Cat; Name = $Name; Desc = $Desc; Risk = $Risk; Reg = $regs; Tasks = $Tasks
        Apply = $Apply; Revert = $Revert; Detect = $Detect; Requires = $Requires; Rec = $Rec
        MinBuild = $MinBuild; MaxBuild = $MaxBuild; Reboot = [bool]$Reboot; Explorer = [bool]$Explorer
        Group = $Group; Note = $Note
    }
}

function Get-OzEthernetPowerProps {
    # Cached list of Ethernet power-saving properties (EEE / Green Ethernet) found on this PC
    if ($null -ne $Oz.EeeCache) { return $Oz.EeeCache }
    $keys = '*EEE', 'AdvancedEEE', 'EEELinkAdvertisement', 'EnableGreenEthernet', 'GigaLite', 'PowerSavingMode'
    $found = @()
    $seen = @{}
    try {
        # One query per adapter (not one per keyword): the same answer in a fraction of the time
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
            foreach ($p in @(Get-NetAdapterAdvancedProperty -Name $a.Name -AllProperties -ErrorAction SilentlyContinue)) {
                $kw = [string]$p.RegistryKeyword
                if ($keys -notcontains $kw) { continue }
                $id = '{0}|{1}' -f $a.Name, $kw
                if ($seen.ContainsKey($id)) { continue }
                $seen[$id] = $true
                $found += [pscustomobject]@{ Adapter = $a.Name; Key = $kw; Value = [string](@($p.RegistryValue)[0]) }
            }
        }
    } catch { }
    $Oz.EeeCache = $found
    return $found
}

function Get-OzNicProps {
    # Physical adapters that support one advanced property (for example *InterruptModeration), cached per keyword
    param([string]$Keyword)
    if ($null -eq $Oz.NicPropCache) { $Oz.NicPropCache = @{} }
    if ($Oz.NicPropCache.ContainsKey($Keyword)) { return $Oz.NicPropCache[$Keyword] }
    $found = @()
    try {
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
            $p = Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $Keyword -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($p) { $found += [pscustomobject]@{ Adapter = $a.Name; Value = [string](@($p.RegistryValue)[0]) } }
        }
    } catch { }
    $Oz.NicPropCache[$Keyword] = $found
    return $found
}

function Test-OzAppInstalled {
    # Desktop apps that some tweaks are only shown for
    param([ValidateSet('Chrome', 'Firefox', 'Office')][string]$App)
    $appPaths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths'
    switch ($App) {
        'Chrome' {
            (Test-Path -LiteralPath "$appPaths\chrome.exe") -or (Test-Path -LiteralPath "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") -or
            (Test-Path -LiteralPath "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
        }
        'Firefox' { (Test-Path -LiteralPath "$appPaths\firefox.exe") -or (Test-Path -LiteralPath "$env:ProgramFiles\Mozilla Firefox\firefox.exe") }
        'Office' {
            (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration') -or (Test-Path -LiteralPath "$appPaths\WINWORD.EXE") -or
            (Test-Path -LiteralPath "$appPaths\EXCEL.EXE") -or (Test-Path -LiteralPath "$appPaths\OUTLOOK.EXE")
        }
    }
}

function Get-OzActiveInterfaces {
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object {
            $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            ($p.DhcpIPAddress -and $p.DhcpIPAddress -ne '0.0.0.0') -or ($p.IPAddress -and (@($p.IPAddress)[0]) -and (@($p.IPAddress)[0]) -ne '0.0.0.0')
        } | ForEach-Object { $_.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE', 'HKLM:' })
}

function Get-OzNagleInterfaces {
    # The physical adapters' TCP/IP keys. VPN, WSL and Hyper-V adapters come and go,
    # so they are tuned too but never decide whether the switch shows ON.
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $paths = @()
    try {
        $paths = @(Get-NetAdapter -Physical -ErrorAction Stop | ForEach-Object { Join-Path $base ([string]$_.InterfaceGuid) } |
                Where-Object { Test-Path -LiteralPath $_ })
    } catch { }
    if (-not $paths) { $paths = @(Get-OzActiveInterfaces) }
    $paths
}


function Initialize-OzCatalog {
    $Oz.Tweaks = @()
    $Pol  = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
    $CU   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion'
    $Adv  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $CDM  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $Cons = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'
    $MM   = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $Edge = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    $WU   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $FS   = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
    $Srch = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    $AI   = 'SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
    # The Windows version this PC runs now, for "Stay on your current Windows version"
    $cvk = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $Oz.PinVersion = @([string]$cvk.DisplayVersion, [string]$cvk.ReleaseId) | Where-Object { $_ -match '^\d{2}H\d$|^\d{4}$' } | Select-Object -First 1
    $pinProduct = if ([int]$cvk.CurrentBuildNumber -ge 22000) { 'Windows 11' } else { 'Windows 10' }

    # =============================== PRIVACY ===============================
    Add-OzTweak -Id 'telemetry-off' -Cat 'Privacy' -Name 'Disable telemetry' -Rec all -Reboot `
        -Desc 'Stops the Connected User Experiences & Telemetry service and sets diagnostic data to the lowest level your edition allows.' `
        -Reg @(@{ P = "$Pol\DataCollection"; N = 'AllowTelemetry'; V = 0 },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; N = 'AllowTelemetry'; V = 0; Soft = $true },
            @{ P = "$Pol\DataCollection"; N = 'DisableOneSettingsDownloads'; V = 1 }) `
        -Svc @(@{ N = 'DiagTrack'; V = 4; D = 2 }, @{ N = 'dmwappushservice'; V = 4; D = 3 })

    Add-OzTweak -Id 'telemetry-tasks-off' -Cat 'Privacy' -Name 'Disable telemetry scheduled tasks' -Rec all `
        -Desc 'Turns off the compatibility appraiser, CEIP, disk diagnostics, feedback and error-report upload tasks that wake the PC in the background.' `
        -Tasks @('\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
            '\Microsoft\Windows\Feedback\Siuf\DmClient',
            '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
            '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
            '\Microsoft\Windows\Autochk\Proxy')

    Add-OzTweak -Id 'ceip-off' -Cat 'Privacy' -Name 'Disable Customer Experience Improvement Program' -Rec all `
        -Desc 'Opts out of CEIP / SQM usage collection.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; N = 'CEIPEnable'; V = 0 },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\SQMClient\Windows'; N = 'CEIPEnable'; V = 0 })

    Add-OzTweak -Id 'appcompat-telemetry-off' -Cat 'Privacy' -Name 'Disable app-compatibility telemetry' -Rec all `
        -Desc 'Stops the inventory collector and steps recorder from reporting the apps you use.' `
        -Reg @(@{ P = "$Pol\AppCompat"; N = 'AITEnable'; V = 0 }, @{ P = "$Pol\AppCompat"; N = 'DisableInventory'; V = 1 },
            @{ P = "$Pol\AppCompat"; N = 'DisableUAR'; V = 1 })

    Add-OzTweak -Id 'werr-off' -Cat 'Privacy' -Name 'Disable Windows Error Reporting' -Rec all `
        -Desc 'Crashes are no longer packaged and uploaded to Microsoft. Saves disk writes after crashes.' `
        -Reg @(@{ P = "$Pol\Windows Error Reporting"; N = 'Disabled'; V = 1 }) -Svc @(@{ N = 'WerSvc'; V = 4; D = 3 })

    Add-OzTweak -Id 'adid-off' -Cat 'Privacy' -Name 'Disable advertising ID' -Rec all `
        -Desc 'Apps can no longer use a per-user ID to target ads.' `
        -Reg @(@{ P = "$CU\AdvertisingInfo"; N = 'Enabled'; V = 0; D = 1 }, @{ P = "$Pol\AdvertisingInfo"; N = 'DisabledByGroupPolicy'; V = 1 })

    Add-OzTweak -Id 'tailored-off' -Cat 'Privacy' -Name 'Disable tailored experiences' -Rec all `
        -Desc 'Microsoft stops using your diagnostic data for personalized tips, ads and recommendations.' `
        -Reg @(@{ P = "$CU\Privacy"; N = 'TailoredExperiencesWithDiagnosticDataEnabled'; V = 0; D = 1 },
            @{ P = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'; N = 'DisableTailoredExperiencesWithDiagnosticData'; V = 1 })

    Add-OzTweak -Id 'activity-off' -Cat 'Privacy' -Name 'Disable activity history' -Rec all `
        -Desc 'Windows stops recording and uploading the apps, files and sites you open.' `
        -Reg @(@{ P = "$Pol\System"; N = 'EnableActivityFeed'; V = 0 }, @{ P = "$Pol\System"; N = 'PublishUserActivities'; V = 0 },
            @{ P = "$Pol\System"; N = 'UploadUserActivities'; V = 0 })

    Add-OzTweak -Id 'feedback-off' -Cat 'Privacy' -Name 'Stop feedback requests' -Rec all `
        -Desc 'No more "How likely are you to recommend Windows" pop-ups.' `
        -Reg @(@{ P = 'HKCU:\Software\Microsoft\Siuf\Rules'; N = 'NumberOfSIUFInPeriod'; V = 0 },
            @{ P = "$Pol\DataCollection"; N = 'DoNotShowFeedbackNotifications'; V = 1 })

    Add-OzTweak -Id 'inking-off' -Cat 'Privacy' -Name 'Disable inking & typing personalization' -Rec all `
        -Desc 'Stops sending typing and handwriting samples to improve recognition.' `
        -Reg @(@{ P = 'HKCU:\Software\Microsoft\InputPersonalization'; N = 'RestrictImplicitInkCollection'; V = 1; D = 0 },
            @{ P = 'HKCU:\Software\Microsoft\InputPersonalization'; N = 'RestrictImplicitTextCollection'; V = 1; D = 0 },
            @{ P = 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore'; N = 'HarvestContacts'; V = 0; D = 1 },
            @{ P = 'HKCU:\Software\Microsoft\Personalization\Settings'; N = 'AcceptedPrivacyPolicy'; V = 0; D = 1 })

    Add-OzTweak -Id 'speech-off' -Cat 'Privacy' -Name 'Disable online speech recognition' -Rec all `
        -Desc 'Voice is not sent to the cloud. Offline voice typing still works.' `
        -Reg @(@{ P = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'; N = 'HasAccepted'; V = 0 })

    Add-OzTweak -Id 'langlist-off' -Cat 'Privacy' -Name 'Hide language list from websites' -Rec all `
        -Desc 'Sites can no longer read your installed language list to fingerprint you.' `
        -Reg @(@{ P = 'HKCU:\Control Panel\International\User Profile'; N = 'HttpAcceptLanguageOptOut'; V = 1 })

    Add-OzTweak -Id 'app-tracking-off' -Cat 'Privacy' -Name 'Stop tracking app launches' -Rec none `
        -Desc 'Windows stops logging which programs you start. Start no longer shows "Most used".' `
        -Reg @(@{ P = $Adv; N = 'Start_TrackProgs'; V = 0; D = 1 })

    Add-OzTweak -Id 'location-off' -Cat 'Privacy' -Name 'Deny location to apps' -Rec none `
        -Desc 'Apps can no longer read your location. Maps, weather and Find My Device lose it.' `
        -Reg @(@{ P = "$Cons\location"; N = 'Value'; V = 'Deny'; T = 'String'; D = 'Allow' })

    Add-OzTweak -Id 'app-perms-off' -Cat 'Privacy' -Name 'Restrict app access to personal data' -Rec none `
        -Desc 'Store apps lose access to account info, contacts, calendar, call history, email, messages, tasks and app diagnostics. Camera and microphone are untouched.' `
        -Reg @('userAccountInformation', 'contacts', 'appointments', 'phoneCallHistory', 'email', 'chat', 'userDataTasks', 'appDiagnostics' | ForEach-Object {
                @{ P = "$Cons\$_"; N = 'Value'; V = 'Deny'; T = 'String'; D = 'Allow' } })

    Add-OzTweak -Id 'clipboard-cloud-off' -Cat 'Privacy' -Name 'Disable cloud clipboard sync' -Rec none `
        -Desc 'Clipboard history stays on this PC and is not synced to other devices.' `
        -Reg @(@{ P = "$Pol\System"; N = 'AllowCrossDeviceClipboard'; V = 0 })

    Add-OzTweak -Id 'sync-off' -Cat 'Privacy' -Name 'Disable settings sync' -Rec none `
        -Desc 'Theme, passwords and preferences are no longer synced through your Microsoft account.' `
        -Reg @(@{ P = "$Pol\SettingSync"; N = 'DisableSettingSync'; V = 2 }, @{ P = "$Pol\SettingSync"; N = 'DisableSettingSyncUserOverride'; V = 1 })

    Add-OzTweak -Id 'smart-actions-off' -Cat 'Privacy' -Name 'No suggested actions when copying' -Rec all -MinBuild 22621 `
        -Desc 'Copying a date, time or phone number no longer pops up suggestions to make a call or add a calendar event.' `
        -Reg @(@{ P = "$CU\SmartActionPlatform\SmartClipboard"; N = 'Disabled'; V = 1; D = 0 })

    Add-OzTweak -Id 'devtools-telemetry-off' -Cat 'Privacy' -Name 'No telemetry from PowerShell 7 and .NET tools' -Rec all `
        -Desc 'Sets the official opt-out switches, so PowerShell 7 and the .NET SDK stop sending usage data. Windows PowerShell is not affected.' `
        -Note 'Applies to programs started after the change.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; N = 'POWERSHELL_TELEMETRY_OPTOUT'; V = '1'; T = 'String' },
            @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; N = 'DOTNET_CLI_TELEMETRY_OPTOUT'; V = '1'; T = 'String' })


    # =============================== AI ===============================
    Add-OzTweak -Id 'copilot-off' -Cat 'AI' -Name 'Disable Copilot in Windows' -Rec all -MinBuild 19045 -Explorer `
        -Desc 'Turns off the Windows Copilot sidebar and hides its taskbar button. Remove the Copilot app in DEBLOAT.' `
        -Reg @(@{ P = 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'; N = 'TurnOffWindowsCopilot'; V = 1 },
            @{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; N = 'TurnOffWindowsCopilot'; V = 1 },
            @{ P = $Adv; N = 'ShowCopilotButton'; V = 0; D = 1 })

    Add-OzTweak -Id 'recall-off' -Cat 'AI' -Name 'Disable Recall (screen snapshots)' -Rec all -MinBuild 26100 -Reboot `
        -Desc 'Blocks Recall from being enabled and stops AI snapshot analysis (Copilot+ PCs).' `
        -Reg @(@{ P = "HKLM:\$AI"; N = 'AllowRecallEnablement'; V = 0 }, @{ P = "HKLM:\$AI"; N = 'DisableAIDataAnalysis'; V = 1 },
            @{ P = "HKCU:\$AI"; N = 'DisableAIDataAnalysis'; V = 1 })

    Add-OzTweak -Id 'clicktodo-off' -Cat 'AI' -Name 'Disable Click to Do' -Rec all -MinBuild 26100 `
        -Desc 'Turns off the AI screen-analysis overlay (Pro / Enterprise honor this policy).' `
        -Reg @(@{ P = "HKLM:\$AI"; N = 'DisableClickToDo'; V = 1 }, @{ P = "HKCU:\$AI"; N = 'DisableClickToDo'; V = 1 })

    Add-OzTweak -Id 'edge-sidebar-off' -Cat 'AI' -Name 'Disable Edge sidebar & Copilot pane' -Rec none `
        -Desc 'Removes the Edge sidebar (Copilot, Shopping, Tools). Edge may show "managed by your organization".' `
        -Reg @(@{ P = $Edge; N = 'HubsSidebarEnabled'; V = 0 })

    Add-OzTweak -Id 'paint-ai-off' -Cat 'AI' -Name 'Disable AI in Paint' -Rec all -MinBuild 22621 `
        -Desc 'Turns off Cocreator, Image Creator and generative fill in Paint (Pro and up honor this policy).' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; N = 'DisableCocreator'; V = 1 },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; N = 'DisableGenerativeFill'; V = 1 },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'; N = 'DisableImageCreator'; V = 1 })

    Add-OzTweak -Id 'notepad-ai-off' -Cat 'AI' -Name 'Disable AI in Notepad' -Rec all -MinBuild 22621 `
        -Desc 'Removes Copilot, Rewrite and Summarize from Notepad. The editor itself is unchanged.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\WindowsNotepad'; N = 'DisableAIFeatures'; V = 1 })

    Add-OzTweak -Id 'genai-apps-off' -Cat 'AI' -Name 'Block apps from Windows generative AI' -Rec all -MinBuild 26100 `
        -Desc 'Apps can no longer use the text and image generation built into Windows (Settings > Privacy > Text and image generation).' `
        -Reg @(@{ P = "$Pol\AppPrivacy"; N = 'LetAppsAccessGenerativeAI'; V = 2 },
            @{ P = "$CU\CapabilityAccessManager\ConsentStore\generativeAI"; N = 'Value'; V = 'Deny'; T = 'String'; D = 'Allow' })

    Add-OzTweak -Id 'edge-ai-model-off' -Cat 'AI' -Name 'Edge: no on-device AI model' -Rec all `
        -Desc 'Edge stops downloading its local AI model and deletes it if it is already there. Frees disk space.' `
        -Note 'Edge will show "managed by your organization" (normal for policies).' `
        -Reg @(@{ P = $Edge; N = 'GenAILocalFoundationalModelSettings'; V = 1 })


    # =============================== PERFORMANCE ===============================
    Add-OzTweak -Id 'visual-fx-perf' -Cat 'Performance' -Name 'Visual effects: best performance' -Rec lowend -Explorer `
        -Desc 'Turns off animations, fades, shadows and Aero Peek but keeps smooth fonts and thumbnails. Big win on weak GPUs.' `
        -Note 'Sign out once for every effect to apply.' `
        -Reg @(@{ P = "$CU\Explorer\VisualEffects"; N = 'VisualFXSetting'; V = 3 },
            @{ P = 'HKCU:\Control Panel\Desktop'; N = 'UserPreferencesMask'; V = @(0x90, 0x12, 0x03, 0x80, 0x10, 0, 0, 0); T = 'Binary'; D = @(0x9E, 0x1E, 0x07, 0x80, 0x12, 0, 0, 0) },
            @{ P = 'HKCU:\Control Panel\Desktop\WindowMetrics'; N = 'MinAnimate'; V = '0'; T = 'String'; D = '1' },
            @{ P = $Adv; N = 'TaskbarAnimations'; V = 0; D = 1 }, @{ P = $Adv; N = 'ListviewAlphaSelect'; V = 0; D = 1 },
            @{ P = $Adv; N = 'ListviewShadow'; V = 0; D = 1 }, @{ P = 'HKCU:\Software\Microsoft\Windows\DWM'; N = 'EnableAeroPeek'; V = 0; D = 1 })

    Add-OzTweak -Id 'transparency-off' -Cat 'Performance' -Name 'Disable transparency' -Rec lowend `
        -Desc 'Solid taskbar and Start. Saves GPU work on integrated graphics.' `
        -Reg @(@{ P = "$CU\Themes\Personalize"; N = 'EnableTransparency'; V = 0; D = 1 })

    Add-OzTweak -Id 'menu-delay' -Cat 'Performance' -Name 'Faster menus' -Rec all `
        -Desc 'Cuts the menu hover delay from 400 ms to 50 ms. Windows feels snappier.' `
        -Reg @(@{ P = 'HKCU:\Control Panel\Desktop'; N = 'MenuShowDelay'; V = '50'; T = 'String'; D = '400' })

    Add-OzTweak -Id 'background-apps-off' -Cat 'Performance' -Name 'Block background Store apps' -Risk Moderate -Rec @('lowend', 'laptop') `
        -Desc 'Store apps stop running when closed. Saves RAM, CPU and battery.' `
        -Note 'Phone Link / Mail notifications only arrive while the app is open.' `
        -Reg @(@{ P = "$CU\BackgroundAccessApplications"; N = 'GlobalUserDisabled'; V = 1; D = 0 },
            @{ P = "$Pol\AppPrivacy"; N = 'LetAppsRunInBackground'; V = 2 })

    Add-OzTweak -Id 'startup-delay-off' -Cat 'Performance' -Name 'Remove startup app delay' -Rec ssd `
        -Desc 'Startup apps launch right away instead of waiting ~10 s. Best on SSDs.' `
        -Reg @(@{ P = "$CU\Explorer\Serialize"; N = 'StartupDelayInMSec'; V = 0 })

    Add-OzTweak -Id 'priority-sep' -Cat 'Performance' -Name 'Foreground priority boost' -Rec all `
        -Desc 'Locks the scheduler to short, variable quanta with a 3:1 boost for the app you are using (0x26).' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl'; N = 'Win32PrioritySeparation'; V = 38; D = 2 })

    Add-OzTweak -Id 'sysmain-off' -Cat 'Performance' -Name 'Disable SysMain (Superfetch)' -Risk Moderate -Rec none `
        -Desc 'Stops RAM prefetching and its disk activity. Fine on fast NVMe with plenty of RAM.' `
        -Note 'Keep ON for hard disks: it makes HDD PCs faster.' `
        -Svc @(@{ N = 'SysMain'; V = 4; D = 2 })

    Add-OzTweak -Id 'search-index-off' -Cat 'Performance' -Name 'Disable search indexing' -Risk Moderate -Rec hdd `
        -Desc 'Stops the indexer from grinding the disk. Huge relief on hard disks.' `
        -Note 'File search in Start and Outlook gets slower.' `
        -Svc @(@{ N = 'WSearch'; V = 4; D = 2 })

    Add-OzTweak -Id 'fth-off' -Cat 'Performance' -Name 'Disable Fault Tolerant Heap' -Risk Moderate -Rec gaming `
        -Desc 'Stops Windows from silently slowing down apps that crashed before.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\FTH'; N = 'Enabled'; V = 0; D = 1 })

    Add-OzTweak -Id 'svchost-split' -Cat 'Performance' -Name 'Group service host processes' -Risk Moderate -Rec none -Reboot `
        -Desc 'Raises the svchost split threshold to your RAM size so services share fewer processes (lower process count and overhead).' `
        -Requires { $Oz.Sys -and $Oz.Sys.Memory.GB -gt 4 } `
        -Detect { $v = (Get-OzReg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB').Value; ($null -ne $v) -and ([int64]$v -gt 3670016) } `
        -Apply {
        $kb = 16777216
        if ($Oz.Sys -and $Oz.Sys.Memory.GB) { $kb = [int64]([double]$Oz.Sys.Memory.GB * 1048576) }
        Set-OzTracked 'svchost-split' 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' $kb
    }

    Add-OzTweak -Id 'mem-compress-off' -Cat 'Performance' -Name 'Disable memory compression' -Risk Advanced -Rec none -Reboot `
        -Desc 'Trades RAM for a little CPU time. Only for 16 GB+ PCs.' `
        -Note 'Keep ON with 8 GB or less: compression helps low-RAM PCs.' `
        -Requires { $Oz.Sys -and $Oz.Sys.Memory.GB -ge 16 } `
        -Detect { -not (Get-MMAgent -ErrorAction Stop).MemoryCompression } `
        -Apply { Disable-MMAgent -MemoryCompression -ErrorAction Stop } `
        -Revert { Enable-MMAgent -MemoryCompression -ErrorAction Stop }

    Add-OzTweak -Id 'paging-exec' -Cat 'Performance' -Name 'Keep kernel in RAM' -Risk Advanced -Rec none -Reboot `
        -Desc 'Kernel and drivers are never paged to disk (DisablePagingExecutive). Only for 16 GB+.' `
        -Requires { $Oz.Sys -and $Oz.Sys.Memory.GB -ge 16 } `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; N = 'DisablePagingExecutive'; V = 1; D = 0 })

    Add-OzTweak -Id 'timer-global' -Cat 'Performance' -Name 'Global timer resolution requests' -Risk Advanced -Rec none -MinBuild 22000 -Reboot `
        -Desc 'Restores pre-Windows 11 behaviour so a timer-resolution request applies system-wide. Only matters if you use a timer tool.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'; N = 'GlobalTimerResolutionRequests'; V = 1 })

    Add-OzTweak -Id 'dynamic-tick-off' -Cat 'Performance' -Name 'Disable dynamic tick' -Risk Advanced -Rec none -Reboot `
        -Desc 'Keeps the system timer ticking at a steady rate. Can smooth frame pacing on some desktops.' `
        -Note 'Suspend BitLocker before changing boot settings. Desktop only.' `
        -Requires { $Oz.Sys -and -not $Oz.Sys.IsLaptop -and -not $Oz.Sys.IsVM } `
        -Detect { (& "$env:SystemRoot\System32\bcdedit.exe" /enum '{current}' | Out-String) -match '(?m)^disabledynamictick\s' } `
        -Apply { & "$env:SystemRoot\System32\bcdedit.exe" /set '{current}' disabledynamictick yes | Out-Null } `
        -Revert { & "$env:SystemRoot\System32\bcdedit.exe" /deletevalue '{current}' disabledynamictick | Out-Null }

    # =============================== GAMING ===============================
    Add-OzTweak -Id 'game-mode-on' -Cat 'Gaming' -Name 'Game Mode ON' -Rec all `
        -Desc 'Windows prioritizes the game and pauses update installs and notifications while you play.' `
        -Reg @(@{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AutoGameModeEnabled'; V = 1 }, @{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'AllowAutoGameMode'; V = 1 })

    Add-OzTweak -Id 'gamedvr-off' -Cat 'Gaming' -Name 'Disable Game DVR background recording' -Rec all `
        -Desc 'Stops the always-on capture buffer that costs FPS and VRAM. Use OBS or your GPU app to record.' `
        -Reg @(@{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_Enabled'; V = 0; D = 1 },
            @{ P = "$CU\GameDVR"; N = 'AppCaptureEnabled'; V = 0 }, @{ P = "$Pol\GameDVR"; N = 'AllowGameDVR'; V = 0 })

    Add-OzTweak -Id 'gamebar-tips-off' -Cat 'Gaming' -Name 'Hide Game Bar startup tips' -Rec all `
        -Desc 'No Game Bar pop-up when a game starts.' `
        -Reg @(@{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'ShowStartupPanel'; V = 0 })

    Add-OzTweak -Id 'hags-on' -Cat 'Gaming' -Name 'Hardware-accelerated GPU scheduling' -Rec gaming -MinBuild 19041 -Reboot `
        -Desc 'The GPU manages its own memory queue: lower latency, and required for DLSS Frame Generation.' `
        -Requires { $Oz.Sys -and $Oz.Sys.GPU.Primary -and $Oz.Sys.GPU.Primary.Dedicated -and $Oz.Sys.GPU.Primary.Vendor -in 'NVIDIA', 'AMD' } `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; N = 'HwSchMode'; V = 2 })

    Add-OzTweak -Id 'mmcss-games' -Cat 'Gaming' -Name 'Multimedia scheduler: games first' -Rec gaming `
        -Desc 'Gives games high CPU/GPU/IO priority in MMCSS and lowers the CPU share reserved for background tasks from 20% to 10%.' `
        -Reg @(@{ P = $MM; N = 'SystemResponsiveness'; V = 10; D = 20 },
            @{ P = "$MM\Tasks\Games"; N = 'GPU Priority'; V = 8; D = 8 }, @{ P = "$MM\Tasks\Games"; N = 'Priority'; V = 6; D = 2 },
            @{ P = "$MM\Tasks\Games"; N = 'Scheduling Category'; V = 'High'; T = 'String'; D = 'Medium' },
            @{ P = "$MM\Tasks\Games"; N = 'SFIO Priority'; V = 'High'; T = 'String'; D = 'Normal' })

    Add-OzTweak -Id 'windowed-opt-on' -Cat 'Gaming' -Name 'Optimizations for windowed games' -Rec gaming -MinBuild 22000 `
        -Desc 'Older DX10/11 games in windowed / borderless mode use the low-latency flip model.' `
        -Detect { [string](Get-OzReg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings').Value -match 'SwapEffectUpgradeEnable=1' } `
        -Apply {
        $p = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
        $cur = [string](Get-OzReg $p 'DirectXUserGlobalSettings').Value
        $new = (($cur -replace 'SwapEffectUpgradeEnable=\d;?', '').TrimEnd(';') + ';SwapEffectUpgradeEnable=1;').TrimStart(';')
        Set-OzTracked 'windowed-opt-on' $p 'DirectXUserGlobalSettings' $new 'String'
    }

    Add-OzTweak -Id 'fso-off' -Cat 'Gaming' -Name 'Disable fullscreen optimizations (global)' -Risk Advanced -Rec none `
        -Desc 'Forces true exclusive fullscreen in older games.' `
        -Note 'Windows 11 is usually smoother with them ON. Try only if a game stutters or alt-tab misbehaves.' `
        -Reg @(@{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_FSEBehaviorMode'; V = 2 }, @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_HonorUserFSEBehaviorMode'; V = 1 },
            @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_FSEBehavior'; V = 2 }, @{ P = 'HKCU:\System\GameConfigStore'; N = 'GameDVR_DXGIHonorFSEWindowsCompatible'; V = 1 })

    Add-OzTweak -Id 'mouse-accel-off' -Cat 'Gaming' -Name 'Raw mouse input (no acceleration)' -Rec gaming `
        -Desc 'Turns off "Enhance pointer precision" for 1:1 aim.' `
        -Reg @(@{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseSpeed'; V = '0'; T = 'String'; D = '1' },
            @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseThreshold1'; V = '0'; T = 'String'; D = '6' },
            @{ P = 'HKCU:\Control Panel\Mouse'; N = 'MouseThreshold2'; V = '0'; T = 'String'; D = '10' })

    Add-OzTweak -Id 'sticky-keys-off' -Cat 'Gaming' -Name 'Disable Sticky / Filter / Toggle key prompts' -Rec gaming `
        -Desc 'Pressing Shift 5 times no longer pops a dialog mid-game.' `
        -Reg @(@{ P = 'HKCU:\Control Panel\Accessibility\StickyKeys'; N = 'Flags'; V = '506'; T = 'String'; D = '510' },
            @{ P = 'HKCU:\Control Panel\Accessibility\ToggleKeys'; N = 'Flags'; V = '58'; T = 'String'; D = '62' },
            @{ P = 'HKCU:\Control Panel\Accessibility\Keyboard Response'; N = 'Flags'; V = '122'; T = 'String'; D = '126' })

    Add-OzTweak -Id 'kb-repeat-fast' -Cat 'Gaming' -Name 'Fastest key repeat' -Rec gaming `
        -Desc 'A held key starts repeating after the shortest delay, at the fastest rate.' `
        -Reg @(@{ P = 'HKCU:\Control Panel\Keyboard'; N = 'KeyboardDelay'; V = '0'; T = 'String'; D = '1' },
            @{ P = 'HKCU:\Control Panel\Keyboard'; N = 'KeyboardSpeed'; V = '31'; T = 'String'; D = '31' })

    Add-OzTweak -Id 'gamebar-button-off' -Cat 'Gaming' -Name 'Xbox button does not open Game Bar' -Rec gaming `
        -Desc 'Pressing the Xbox button on a controller no longer pops Game Bar over your game. Win+G still opens it.' `
        -Reg @(@{ P = 'HKCU:\Software\Microsoft\GameBar'; N = 'UseNexusForGameBarEnabled'; V = 0; D = 1 })


    # =============================== POWER & THERMALS ===============================
    $notVM = { $Oz.Sys -and -not $Oz.Sys.IsVM }
    Add-OzTweak -Id 'plan-perf' -Cat 'Power' -Group 'plan' -Name 'OZZYHN PERFORMANCE power plan' -Rec desktop -Requires $notVM `
        -Desc 'Max boost and unparked cores under load, but 5% minimum state so the CPU idles cool. PCIe/USB/disk power saving off while plugged in.' `
        -Detect { Test-OzPlanActive 'plan-perf' $Oz.PlanPerf } `
        -Apply {
        Install-OzPlan -Id 'plan-perf' -Guid $Oz.PlanPerf -Name 'Ozzyhn Performance' -Description 'Max performance, cool idle - Optimizaciones de Ozzyhn' -Settings @(
            @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 5, 5), @('SUB_PROCESSOR', 'PROCTHROTTLEMAX', 100, 100),
            @('SUB_PROCESSOR', 'PERFBOOSTMODE', 2, 3), @('SUB_PROCESSOR', 'PERFEPP', 0, 50),
            @('SUB_PROCESSOR', 'CPMINCORES', 100, 50), @('SUB_PROCESSOR', 'SYSCOOLPOL', 1, 0),
            @('SUB_PCIEXPRESS', 'ASPM', 0, 2), @('SUB_DISK', 'DISKIDLE', 0, 600),
            @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0, 1))
    } -Revert { Remove-OzPlan -Id 'plan-perf' -Guid $Oz.PlanPerf }

    Add-OzTweak -Id 'plan-smart' -Cat 'Power' -Group 'plan' -Name 'OZZYHN SMART power plan (fast + cool)' -Rec laptop -Requires $notVM `
        -Desc 'Efficient-aggressive boost: near full speed when you need it, much less heat and fan noise the rest of the time. Fans spin up before the CPU throttles.' `
        -Note 'Laptop maker apps (Armoury Crate, Vantage, MSI Center...) can switch the plan back. Use their Balanced / Auto mode with this.' `
        -Detect { Test-OzPlanActive 'plan-smart' $Oz.PlanSmart } `
        -Apply {
        Install-OzPlan -Id 'plan-smart' -Guid $Oz.PlanSmart -Name 'Ozzyhn Smart' -Description 'Fast and cool - Optimizaciones de Ozzyhn' -Settings @(
            @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 5, 5), @('SUB_PROCESSOR', 'PROCTHROTTLEMAX', 100, 100),
            @('SUB_PROCESSOR', 'PERFBOOSTMODE', 4, 3), @('SUB_PROCESSOR', 'PERFEPP', 25, 60),
            @('SUB_PROCESSOR', 'SYSCOOLPOL', 1, 0), @('SUB_PCIEXPRESS', 'ASPM', 1, 2))
    } -Revert { Remove-OzPlan -Id 'plan-smart' -Guid $Oz.PlanSmart }

    Add-OzTweak -Id 'plan-cool' -Cat 'Power' -Group 'plan' -Name 'OZZYHN COOL power plan (turbo off)' -Rec none -Requires $notVM `
        -Desc 'Disables CPU turbo boost. Load temperatures often drop by 10 C or more and fans calm down, in exchange for lower peak speed. Rescue mode for overheating laptops.' `
        -Detect { Test-OzPlanActive 'plan-cool' $Oz.PlanCool } `
        -Apply {
        Install-OzPlan -Id 'plan-cool' -Guid $Oz.PlanCool -Name 'Ozzyhn Cool' -Description 'Turbo off, low temperatures - Optimizaciones de Ozzyhn' -Settings @(
            @('SUB_PROCESSOR', 'PROCTHROTTLEMIN', 5, 5), @('SUB_PROCESSOR', 'PROCTHROTTLEMAX', 100, 100),
            @('SUB_PROCESSOR', 'PERFBOOSTMODE', 0, 0), @('SUB_PROCESSOR', 'PERFEPP', 60, 80),
            @('SUB_PROCESSOR', 'SYSCOOLPOL', 1, 0))
    } -Revert { Remove-OzPlan -Id 'plan-cool' -Guid $Oz.PlanCool }

    Add-OzTweak -Id 'power-throttle-off' -Cat 'Power' -Name 'Disable power throttling' -Rec desktop -Reboot `
        -Desc 'Background apps are never forced onto slow efficiency mode. Desktop only - laptops lose battery life.' `
        -Requires { $Oz.Sys -and -not $Oz.Sys.IsLaptop } `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'; N = 'PowerThrottlingOff'; V = 1 })

    Add-OzTweak -Id 'hibernate-off' -Cat 'Power' -Name 'Disable hibernation' -Rec desktop `
        -Desc 'Deletes hiberfil.sys and frees disk space (about 40% of your RAM size). Also disables Fast Startup.' `
        -Requires { $Oz.Sys -and -not $Oz.Sys.IsLaptop } `
        -Detect { $v = (Get-OzReg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled').Value; ($v -eq 0) -or (($null -eq $v) -and -not (Test-Path -LiteralPath "$env:SystemDrive\hiberfil.sys")) } `
        -Apply { Invoke-OzPowercfg @('/hibernate', 'off') | Out-Null } `
        -Revert { Invoke-OzPowercfg @('/hibernate', 'on') | Out-Null }

    Add-OzTweak -Id 'fast-startup-off' -Cat 'Power' -Name 'Disable Fast Startup' -Rec ssd `
        -Desc 'Shut down really shuts down: fixes stale drivers, dual-boot and "uptime never resets" issues.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'; N = 'HiberbootEnabled'; V = 0; D = 1 })

    Add-OzTweak -Id 'standby-net-off' -Cat 'Power' -Name 'No network while asleep on battery' -Rec laptop -Reboot `
        -Desc 'Modern Standby laptops stop syncing mail and downloading updates while asleep on battery: less drain and heat in a bag.' `
        -Requires { $Oz.Sys -and $Oz.Sys.IsLaptop } `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\f15576e8-98b7-4186-b944-eafa664402d9'; N = 'DCSettingIndex'; V = 0 })

    Add-OzTweak -Id 'power-unhide' -Cat 'Power' -Name 'Show hidden CPU power settings' -Rec none `
        -Desc 'Adds "Processor performance boost mode" and core parking to Power Options > Advanced settings, so you can tune them yourself.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7'; N = 'Attributes'; V = 2; D = 1 },
            @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583'; N = 'Attributes'; V = 0; D = 1 })


    # =============================== SERVICES ===============================
    Add-OzTweak -Id 'svc-fax' -Cat 'Services' -Name 'Fax service OFF' -Rec all -Desc 'Nobody faxes from a PC.' -Svc @(@{ N = 'Fax'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-retaildemo' -Cat 'Services' -Name 'Retail Demo service OFF' -Rec all -Desc 'Store-display demo mode.' -Svc @(@{ N = 'RetailDemo'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-maps' -Cat 'Services' -Name 'Downloaded Maps Manager OFF' -Rec all -Desc 'Stops background offline-map updates.' -Svc @(@{ N = 'MapsBroker'; V = 4; D = 2 })
    Add-OzTweak -Id 'svc-wmpnet' -Cat 'Services' -Name 'Media Player network sharing OFF' -Rec all -Desc 'Legacy Windows Media Player library sharing.' -Svc @(@{ N = 'WMPNetworkSvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-insider' -Cat 'Services' -Name 'Windows Insider service OFF' -Rec all -Desc 'Only needed for Insider preview builds.' -Svc @(@{ N = 'wisvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-diag' -Cat 'Services' -Name 'Diagnostic services OFF' -Risk Moderate -Rec none `
        -Desc 'Diagnostic Policy + Diagnostic hosts. Saves RAM on low-end PCs.' -Note 'Built-in troubleshooters and network diagnostics stop working.' `
        -Svc @(@{ N = 'DPS'; V = 4; D = 2 }, @{ N = 'WdiServiceHost'; V = 4; D = 3 }, @{ N = 'WdiSystemHost'; V = 4; D = 3 }, @{ N = 'diagsvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-print' -Cat 'Services' -Name 'Print Spooler OFF' -Risk Moderate -Rec none `
        -Desc 'Frees RAM and closes the PrintNightmare attack surface.' -Note 'You will not be able to print or use "Print to PDF".' `
        -Svc @(@{ N = 'Spooler'; V = 4; D = 2 })
    Add-OzTweak -Id 'svc-xbox' -Cat 'Services' -Name 'Xbox Live services OFF' -Risk Moderate -Rec none `
        -Desc 'Xbox auth, cloud saves and networking services.' -Note 'Breaks Game Pass, the Xbox app and achievements.' `
        -Svc @(@{ N = 'XblAuthManager'; V = 4; D = 3 }, @{ N = 'XblGameSave'; V = 4; D = 3 }, @{ N = 'XboxNetApiSvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-phone' -Cat 'Services' -Name 'Phone service OFF' -Rec none -Desc 'Telephony for Phone Link calls. Safe on desktops without Phone Link.' `
        -Svc @(@{ N = 'PhoneSvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-geo' -Cat 'Services' -Name 'Geolocation service OFF' -Rec none -Desc 'No location for any app or Windows feature.' `
        -Svc @(@{ N = 'lfsvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-parental' -Cat 'Services' -Name 'Parental Controls service OFF' -Rec none -Desc 'Only needed for Microsoft Family child accounts.' `
        -Svc @(@{ N = 'WpcMonSvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-smartcard' -Cat 'Services' -Name 'Smart card services OFF' -Rec none -Desc 'Only used by corporate smart-card logins.' `
        -Svc @(@{ N = 'SCardSvr'; V = 4; D = 3 }, @{ N = 'ScDeviceEnum'; V = 4; D = 3 }, @{ N = 'SCPolicySvc'; V = 4; D = 3 })

    Add-OzTweak -Id 'svc-bluetooth' -Cat 'Services' -Name 'Bluetooth services OFF' -Rec all `
        -Desc 'Only shown when this PC has no Bluetooth radio, so nothing here can use them.' -Note 'Turn this back off before you plug in a Bluetooth adapter.' `
        -Requires { $Oz.Sys -and $null -ne $Oz.Sys.DevClasses -and @($Oz.Sys.DevClasses) -notcontains 'Bluetooth' } `
        -Svc @(@{ N = 'bthserv'; V = 4; D = 3 }, @{ N = 'BTAGService'; V = 4; D = 3 }, @{ N = 'BluetoothUserService'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-biometric' -Cat 'Services' -Name 'Fingerprint / face sign-in service OFF' -Rec all `
        -Desc 'Only shown when this PC has no fingerprint reader or Windows Hello camera.' -Note 'Turn this back off before you add a fingerprint reader or face camera.' `
        -Requires { $Oz.Sys -and $null -ne $Oz.Sys.DevClasses -and @($Oz.Sys.DevClasses) -notcontains 'Biometric' } `
        -Svc @(@{ N = 'WbioSrvc'; V = 4; D = 3 })
    Add-OzTweak -Id 'svc-hotspot' -Cat 'Services' -Name 'Mobile hotspot service OFF' -Rec none -Desc 'Only needed to share this PC''s internet with other devices.' `
        -Svc @(@{ N = 'icssvc'; V = 4; D = 3 })


    # =============================== NETWORK ===============================
    Add-OzTweak -Id 'net-throttle-off' -Cat 'Network' -Name 'Disable network throttling' -Rec gaming `
        -Desc 'Windows stops limiting network packet processing while media plays.' `
        -Reg @(@{ P = $MM; N = 'NetworkThrottlingIndex'; V = -1; D = 10 })

    Add-OzTweak -Id 'nagle-off' -Cat 'Network' -Name 'Disable Nagle (TCP no-delay)' -Rec gaming `
        -Desc 'Sends small TCP packets immediately instead of batching them. Helps TCP-based games and remote desktop.' `
        -Detect {
        $ifs = @(Get-OzNagleInterfaces)
        if (-not $ifs) { return $false }
        foreach ($i in $ifs) { if ((Get-OzReg $i 'TcpAckFrequency').Value -ne 1 -or (Get-OzReg $i 'TCPNoDelay').Value -ne 1) { return $false } }
        $true
    } -Apply {
        $seen = @{}
        foreach ($i in @(@(Get-OzNagleInterfaces) + @(Get-OzActiveInterfaces))) {
            if (-not $i -or $seen.ContainsKey($i)) { continue }
            $seen[$i] = $true
            Set-OzTracked 'nagle-off' $i 'TcpAckFrequency' 1
            Set-OzTracked 'nagle-off' $i 'TCPNoDelay' 1
        }
    }

    Add-OzTweak -Id 'nic-power-off' -Cat 'Network' -Name 'Network adapter never sleeps' -Rec desktop `
        -Desc 'Windows can no longer turn off the network card to save power - prevents random disconnects and latency spikes.' `
        -Requires { $Oz.Sys -and -not $Oz.Sys.IsLaptop -and -not $Oz.Sys.IsVM } `
        -Detect {
        $pm = @(Get-NetAdapter -Physical -ErrorAction Stop | Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue | Where-Object { [string]$_.AllowComputerToTurnOffDevice -ne 'Unsupported' })
        if (-not $pm) { return $false }
        -not ($pm | Where-Object { [string]$_.AllowComputerToTurnOffDevice -eq 'Enabled' })
    } -Apply {
        foreach ($a in @(Get-NetAdapter -Physical)) { Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice Disabled -NoRestart -ErrorAction SilentlyContinue }
    } -Revert {
        foreach ($a in @(Get-NetAdapter -Physical)) { Set-NetAdapterPowerManagement -Name $a.Name -AllowComputerToTurnOffDevice Enabled -NoRestart -ErrorAction SilentlyContinue }
    }

    Add-OzTweak -Id 'eee-off' -Cat 'Network' -Name 'Disable Ethernet power saving (EEE / Green)' -Risk Moderate -Rec gaming -Reboot `
        -Desc 'Turns off Energy-Efficient Ethernet and Green Ethernet, a common cause of ping spikes on Realtek / Intel LAN.' `
        -Requires { $Oz.Sys -and -not $Oz.Sys.IsVM -and @(Get-OzEthernetPowerProps).Count -gt 0 } `
        -Detect { $p = @(Get-OzEthernetPowerProps); ($p.Count -gt 0) -and -not ($p | Where-Object { $_.Value -ne '0' }) } `
        -Apply {
        $orig = @{}
        foreach ($p in @(Get-OzEthernetPowerProps)) {
            $orig["$($p.Adapter)|$($p.Key)"] = $p.Value
            Set-NetAdapterAdvancedProperty -Name $p.Adapter -RegistryKeyword $p.Key -RegistryValue '0' -NoRestart -ErrorAction SilentlyContinue
        }
        Set-OzData 'eee-off' 'Orig' $orig -OnlyIfMissing
        $Oz.EeeCache = $null
    } -Revert {
        $orig = Get-OzData 'eee-off' 'Orig'
        foreach ($p in @(Get-OzEthernetPowerProps)) {
            $k = "$($p.Adapter)|$($p.Key)"
            $v = if ($orig -and $orig.ContainsKey($k)) { [string]$orig[$k] } else { '1' }
            Set-NetAdapterAdvancedProperty -Name $p.Adapter -RegistryKeyword $p.Key -RegistryValue $v -NoRestart -ErrorAction SilentlyContinue
        }
        $Oz.EeeCache = $null
    }

    Add-OzTweak -Id 'smb-throttle-off' -Cat 'Network' -Name 'Faster network file copies' -Rec all `
        -Desc 'Disables SMB bandwidth throttling for large transfers to NAS / other PCs.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'; N = 'DisableBandwidthThrottling'; V = 1 })

    Add-OzTweak -Id 'do-p2p-off' -Cat 'Network' -Name 'Stop uploading updates to other PCs' -Rec all `
        -Desc 'Delivery Optimization stops seeding Windows Updates to strangers using your upload bandwidth.' `
        -Reg @(@{ P = "$Pol\DeliveryOptimization"; N = 'DODownloadMode'; V = 0 })

    Add-OzTweak -Id 'teredo-off' -Cat 'Network' -Name 'Disable Teredo tunneling' -Rec none `
        -Desc 'Turns off the IPv6-over-IPv4 tunnel adapter.' -Note 'Xbox app party chat and some P2P games use Teredo.' `
        -Detect { [string](Get-NetTeredoConfiguration -ErrorAction Stop).Type -eq 'Disabled' } `
        -Apply { Set-NetTeredoConfiguration -Type Disabled -ErrorAction Stop } `
        -Revert { Set-NetTeredoConfiguration -Type Default -ErrorAction Stop }

    Add-OzTweak -Id 'ipv4-prefer' -Cat 'Network' -Name 'Prefer IPv4 over IPv6' -Risk Moderate -Rec none -Reboot `
        -Desc 'Windows tries IPv4 first. Fixes slow first connections on networks with broken IPv6, while IPv6 keeps working.' `
        -Note 'Microsoft recommends keeping IPv6 on. This only changes which one is tried first.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'; N = 'DisabledComponents'; V = 32 })

    Add-OzTweak -Id 'nic-intmod-off' -Cat 'Network' -Name 'Disable interrupt moderation (wired)' -Risk Advanced -Rec none -Reboot `
        -Desc 'The network card reports every packet right away instead of batching them. Can lower ping jitter in games, costs a little CPU.' `
        -Note 'The adapter briefly reconnects. Turn this back off if downloads get slower.' `
        -Requires { $Oz.Sys -and -not $Oz.Sys.IsVM -and @(Get-OzNicProps '*InterruptModeration').Count -gt 0 } `
        -Detect { $p = @(Get-OzNicProps '*InterruptModeration'); ($p.Count -gt 0) -and -not ($p | Where-Object { $_.Value -ne '0' }) } `
        -Apply {
        $orig = @{}
        foreach ($p in @(Get-OzNicProps '*InterruptModeration')) {
            $orig[$p.Adapter] = $p.Value
            Set-NetAdapterAdvancedProperty -Name $p.Adapter -RegistryKeyword '*InterruptModeration' -RegistryValue '0' -NoRestart -ErrorAction SilentlyContinue
        }
        Set-OzData 'nic-intmod-off' 'Orig' $orig -OnlyIfMissing
        $Oz.NicPropCache = @{}
    } -Revert {
        $orig = Get-OzData 'nic-intmod-off' 'Orig'
        foreach ($p in @(Get-OzNicProps '*InterruptModeration')) {
            $v = if ($orig -and $orig.ContainsKey($p.Adapter)) { [string]$orig[$p.Adapter] } else { '1' }
            Set-NetAdapterAdvancedProperty -Name $p.Adapter -RegistryKeyword '*InterruptModeration' -RegistryValue $v -NoRestart -ErrorAction SilentlyContinue
        }
        $Oz.NicPropCache = @{}
    }


    # =============================== EXPLORER & UI ===============================
    Add-OzTweak -Id 'classic-context' -Cat 'Explorer' -Name 'Classic right-click menu' -Rec win11 -MinBuild 22000 -Explorer `
        -Desc 'Restores the full Windows 10 context menu - no more "Show more options".' `
        -Detect { Test-Path -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' } `
        -Apply {
        $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        New-Item -Path $k -Force | Out-Null
        Set-ItemProperty -LiteralPath $k -Name '(default)' -Value ''
    } -Revert { Remove-Item -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue }

    Add-OzTweak -Id 'show-ext' -Cat 'Explorer' -Name 'Show file extensions' -Rec all -Explorer `
        -Desc 'See .exe/.pdf/.lnk. Also protects against "invoice.pdf.exe" tricks.' `
        -Reg @(@{ P = $Adv; N = 'HideFileExt'; V = 0; D = 1 })
    Add-OzTweak -Id 'show-hidden' -Cat 'Explorer' -Name 'Show hidden files' -Rec none -Explorer -Desc 'Shows hidden files and folders.' `
        -Reg @(@{ P = $Adv; N = 'Hidden'; V = 1; D = 2 })
    Add-OzTweak -Id 'open-thispc' -Cat 'Explorer' -Name 'Explorer opens to This PC' -Rec none -Explorer -Desc 'Instead of Home / Quick access.' `
        -Reg @(@{ P = $Adv; N = 'LaunchTo'; V = 1 })
    Add-OzTweak -Id 'no-recent-files' -Cat 'Explorer' -Name 'Hide recent files in Explorer' -Rec none -Explorer -Desc 'Home / Quick access stops listing recent files and frequent folders.' `
        -Reg @(@{ P = "$CU\Explorer"; N = 'ShowRecent'; V = 0 }, @{ P = "$CU\Explorer"; N = 'ShowFrequent'; V = 0 })
    Add-OzTweak -Id 'no-sync-ads' -Cat 'Explorer' -Name 'No OneDrive / Microsoft 365 ads in Explorer' -Rec all -Explorer -Desc 'Removes sync-provider banners in File Explorer.' `
        -Reg @(@{ P = $Adv; N = 'ShowSyncProviderNotifications'; V = 0; D = 1 })
    Add-OzTweak -Id 'gallery-off' -Cat 'Explorer' -Name 'Hide Gallery from Explorer' -Rec none -MinBuild 22621 -Explorer -Desc 'Removes the Gallery entry in the navigation pane.' `
        -Reg @(@{ P = 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'; N = 'System.IsPinnedToNameSpaceTree'; V = 0 })
    Add-OzTweak -Id 'dark-mode' -Cat 'Explorer' -Name 'Dark mode' -Rec none -Desc 'Dark theme for Windows and apps.' `
        -Reg @(@{ P = "$CU\Themes\Personalize"; N = 'AppsUseLightTheme'; V = 0; D = 1 }, @{ P = "$CU\Themes\Personalize"; N = 'SystemUsesLightTheme'; V = 0; D = 1 })
    Add-OzTweak -Id 'shortcut-suffix-off' -Cat 'Explorer' -Name 'No "- Shortcut" suffix' -Rec all -Desc 'New shortcuts keep a clean name.' `
        -Reg @(@{ P = "$CU\Explorer\NamingTemplates"; N = 'ShortcutNameTemplate'; V = '"%s.lnk"'; T = 'String' })
    Add-OzTweak -Id 'alt-tab-windows' -Cat 'Explorer' -Name 'Alt+Tab shows windows only' -Rec all -MinBuild 19041 -Desc 'Edge tabs no longer flood Alt+Tab.' `
        -Reg @(@{ P = $Adv; N = 'MultiTaskingAltTabFilter'; V = 3 })
    Add-OzTweak -Id 'notif-suggest-off' -Cat 'Explorer' -Name 'No "suggested" notifications' -Rec all -Desc 'Stops Windows suggestion toasts.' `
        -Reg @(@{ P = "$CU\Notifications\Settings\Windows.SystemToast.Suggested"; N = 'Enabled'; V = 0 })
    Add-OzTweak -Id 'seconds-clock' -Cat 'Explorer' -Name 'Show seconds in the clock' -Rec none -Explorer -Desc 'Taskbar clock shows seconds.' `
        -Reg @(@{ P = $Adv; N = 'ShowSecondsInSystemClock'; V = 1 })
    Add-OzTweak -Id 'bsod-details' -Cat 'Explorer' -Name 'Detailed blue-screen info' -Rec none -Desc 'Blue screens show the technical parameters - easier to troubleshoot.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'; N = 'DisplayParameters'; V = 1 })
    Add-OzTweak -Id 'verbose-status' -Cat 'Explorer' -Name 'Verbose startup / shutdown messages' -Rec none -Desc 'See what Windows is doing when boot or shutdown is slow.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; N = 'VerboseStatus'; V = 1 })
    Add-OzTweak -Id 'numlock-on' -Cat 'Explorer' -Name 'Num Lock on at sign-in' -Rec none -Desc 'Number pad works on the login screen.' `
        -Requires { $Oz.Sys -and -not $Oz.Sys.IsLaptop } `
        -Reg @(@{ P = 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard'; N = 'InitialKeyboardIndicators'; V = '2'; T = 'String'; D = '2147483648' })
    Add-OzTweak -Id 'shutdown-faster' -Cat 'Explorer' -Name 'Faster shutdown' -Risk Moderate -Rec none `
        -Desc 'Services get 2 s instead of 5 s to stop at shutdown.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control'; N = 'WaitToKillServiceTimeout'; V = '2000'; T = 'String'; D = '5000' })

    Add-OzTweak -Id 'home-nav-off' -Cat 'Explorer' -Name 'Hide Home from Explorer' -Rec none -MinBuild 22621 -Explorer -Desc 'Removes the Home entry at the top of the navigation pane.' `
        -Reg @(@{ P = 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'; N = 'System.IsPinnedToNameSpaceTree'; V = 0 })
    Add-OzTweak -Id 'dup-drives-off' -Cat 'Explorer' -Name 'No duplicate USB drives in Explorer' -Rec none -Explorer `
        -Desc 'USB sticks and SD cards show once under This PC instead of twice in the navigation pane.' `
        -Detect { -not (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}') } `
        -Apply {
        $had = @()
        foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}') {
            if (Test-Path -LiteralPath $k) { $had += $k; Remove-Item -LiteralPath $k -Recurse -Force -ErrorAction Stop }
        }
        if ($had.Count) { Set-OzData 'dup-drives-off' 'Keys' $had -OnlyIfMissing }
    } -Revert {
        $keys = @(Get-OzData 'dup-drives-off' 'Keys' | Where-Object { $_ })
        if (-not $keys.Count) { $keys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\DelegateFolders\{F5FB2C77-0E2F-4A16-A381-3E560C68BC83}') }
        foreach ($k in $keys) {
            if (-not (Test-Path -LiteralPath $k)) { New-Item -Path $k -Force | Out-Null }
            Set-ItemProperty -LiteralPath $k -Name '(default)' -Value 'Removable Drives'
        }
    }
    Add-OzTweak -Id 'ctx-share-off' -Cat 'Explorer' -Name 'Right-click menu: no Give access, Share or Cast' -Rec none -Explorer `
        -Desc 'Removes "Give access to", "Share" and "Cast to device" from the right-click menu.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}'; V = 'Give access to'; T = 'String' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{e2bf9676-5f8f-435c-97eb-11607a5bedf7}'; V = 'Share'; T = 'String' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{7AD84985-87B4-4a16-BE58-8B72A5B390F7}'; V = 'Cast to device'; T = 'String' })
    Add-OzTweak -Id 'ctx-apps-off' -Cat 'Explorer' -Name 'Right-click menu: no app shortcuts' -Rec none -MinBuild 22000 -Explorer `
        -Desc 'Removes "Ask Copilot", "Edit with Clipchamp", "Edit with Photos", "Edit with Paint" and "Edit in Notepad". Open with still works.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}'; V = 'Ask Copilot'; T = 'String' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{8AB635F8-9A67-4698-AB99-784AD929F3B4}'; V = 'Edit with Clipchamp'; T = 'String' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{BFE0E2A4-C70C-4AD7-AC3D-10D1ECEBB5B4}'; V = 'Edit with Photos'; T = 'String' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{2430F218-B743-4FD6-97BF-5C76541B4AE9}'; V = 'Edit with Paint'; T = 'String' },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'; N = '{CA6CC9F1-867A-481E-951E-A28C5E4F01EA}'; V = 'Edit in Notepad'; T = 'String' })
    Add-OzTweak -Id 'store-openwith-off' -Cat 'Explorer' -Name 'No "Look for an app in the Store"' -Rec all `
        -Desc 'Opening an unknown file type shows your installed apps instead of sending you to the Microsoft Store.' `
        -Reg @(@{ P = "$Pol\Explorer"; N = 'NoUseStoreOpenWith'; V = 1 })
    Add-OzTweak -Id 'spotlight-icon-off' -Cat 'Explorer' -Name 'Hide the "Learn about this picture" icon' -Rec all -MinBuild 22621 -Explorer `
        -Desc 'Removes the Windows Spotlight icon from the desktop. Spotlight wallpapers keep changing.' `
        -Reg @(@{ P = "$CU\Explorer\HideDesktopIcons\NewStartPanel"; N = '{2cc5ca98-6485-489a-920e-b3e88a6ccce3}'; V = 1; D = 0 })
    Add-OzTweak -Id 'aero-shake-off' -Cat 'Explorer' -Name 'No window shake to minimize' -Rec none -Desc 'Shaking a window by its title bar no longer minimizes every other window.' `
        -Reg @(@{ P = $Adv; N = 'DisallowShaking'; V = 1 })
    Add-OzTweak -Id 'compact-view' -Cat 'Explorer' -Name 'Compact Explorer view' -Rec none -MinBuild 22000 -Explorer -Desc 'Less space between files, so more fit on screen (the Windows 10 spacing).' `
        -Reg @(@{ P = $Adv; N = 'UseCompactMode'; V = 1; D = 0 })
    Add-OzTweak -Id 'logon-blur-off' -Cat 'Explorer' -Name 'Sharp sign-in screen background' -Rec none -MinBuild 18362 -Desc 'The sign-in screen shows your lock-screen picture without the blur.' `
        -Reg @(@{ P = "$Pol\System"; N = 'DisableAcrylicBackgroundOnLogon'; V = 1 })
    Add-OzTweak -Id 'wallpaper-quality' -Cat 'Explorer' -Name 'Full-quality wallpaper' -Rec all `
        -Desc 'Windows stops recompressing your wallpaper to 85% JPEG quality, so gradients and dark scenes stay smooth.' -Note 'Set your wallpaper again to see the difference.' `
        -Reg @(@{ P = 'HKCU:\Control Panel\Desktop'; N = 'JPEGImportQuality'; V = 100 })
    Add-OzTweak -Id 'copy-details' -Cat 'Explorer' -Name 'Detailed file copy window' -Rec all -Desc 'Copy and move windows open with the speed graph and details already shown.' `
        -Reg @(@{ P = "$CU\Explorer\OperationStatusManager"; N = 'EnthusiastMode'; V = 1 })


    # =============================== START / TASKBAR / SEARCH ===============================
    Add-OzTweak -Id 'web-search-off' -Cat 'Start' -Name 'No Bing web results in Start search' -Rec all -Explorer `
        -Desc 'Start search only finds your apps, files and settings. Faster and private.' `
        -Reg @(@{ P = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; N = 'DisableSearchBoxSuggestions'; V = 1 },
            @{ P = "$CU\Search"; N = 'BingSearchEnabled'; V = 0 }, @{ P = "$CU\Search"; N = 'CortanaConsent'; V = 0 })
    Add-OzTweak -Id 'cortana-off' -Cat 'Start' -Name 'Disable Cortana' -Rec all -Desc 'Turns off the retired Cortana assistant.' `
        -Reg @(@{ P = $Srch; N = 'AllowCortana'; V = 0 })
    Add-OzTweak -Id 'search-highlights-off' -Cat 'Start' -Name 'No search highlights' -Rec all -Desc 'Removes trending doodles and news from the search box.' `
        -Reg @(@{ P = "$CU\SearchSettings"; N = 'IsDynamicSearchBoxEnabled'; V = 0; D = 1 }, @{ P = $Srch; N = 'EnableDynamicContentInWSB'; V = 0 })
    Add-OzTweak -Id 'cloud-search-off' -Cat 'Start' -Name 'No cloud content in search' -Rec none -Desc 'Search stops looking in OneDrive / Outlook / work accounts.' `
        -Reg @(@{ P = $Srch; N = 'AllowCloudSearch'; V = 0 }, @{ P = "$CU\SearchSettings"; N = 'IsMSACloudSearchEnabled'; V = 0 },
            @{ P = "$CU\SearchSettings"; N = 'IsAADCloudSearchEnabled'; V = 0 })
    Add-OzTweak -Id 'widgets-off' -Cat 'Start' -Name 'Disable Widgets / News and Interests' -Rec all -Explorer `
        -Desc 'Removes the weather/news panel and its background web process (saves 100-300 MB RAM).' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'; N = 'AllowNewsAndInterests'; V = 0 }, @{ P = "$Pol\Windows Feeds"; N = 'EnableFeeds'; V = 0 })
    Add-OzTweak -Id 'chat-off' -Cat 'Start' -Name 'Remove Chat / Teams taskbar icon' -Rec all -MinBuild 22000 -Explorer -Desc 'Hides the consumer Teams Chat button.' `
        -Reg @(@{ P = $Adv; N = 'TaskbarMn'; V = 0; D = 1 }, @{ P = "$Pol\Windows Chat"; N = 'ChatIcon'; V = 3 })
    Add-OzTweak -Id 'taskview-off' -Cat 'Start' -Name 'Hide Task View button' -Rec none -Explorer -Desc 'Win+Tab still works.' `
        -Reg @(@{ P = $Adv; N = 'ShowTaskViewButton'; V = 0; D = 1 })
    Add-OzTweak -Id 'taskbar-left' -Cat 'Start' -Name 'Left-aligned taskbar' -Rec none -MinBuild 22000 -Explorer -Desc 'Classic Start button position on Windows 11.' `
        -Reg @(@{ P = $Adv; N = 'TaskbarAl'; V = 0; D = 1 })
    Add-OzTweak -Id 'search-icon' -Cat 'Start' -Name 'Search box as icon only' -Rec none -Explorer -Desc 'Saves taskbar space.' `
        -Reg @(@{ P = "$CU\Search"; N = 'SearchboxTaskbarMode'; V = 1 })
    Add-OzTweak -Id 'end-task' -Cat 'Start' -Name '"End task" on taskbar right-click' -Rec all -MinBuild 22631 -Desc 'Kill frozen apps without Task Manager.' `
        -Reg @(@{ P = "$Adv\TaskbarDeveloperSettings"; N = 'TaskbarEndTask'; V = 1 })
    Add-OzTweak -Id 'start-recs-off' -Cat 'Start' -Name 'Clean Start menu (no recommendations)' -Rec all -MinBuild 22000 `
        -Desc 'Removes promoted apps, tips and account nags from Start.' `
        -Reg @(@{ P = $Adv; N = 'Start_IrisRecommendations'; V = 0; D = 1 }, @{ P = $Adv; N = 'Start_AccountNotifications'; V = 0; D = 1 })
    Add-OzTweak -Id 'start-suggest-off' -Cat 'Start' -Name 'No suggested / auto-installed apps' -Rec all `
        -Desc 'Stops Windows from silently installing Candy Crush-style apps and showing app suggestions.' `
        -Reg @(@{ P = $CDM; N = 'SilentInstalledAppsEnabled'; V = 0; D = 1 }, @{ P = $CDM; N = 'SystemPaneSuggestionsEnabled'; V = 0; D = 1 },
            @{ P = $CDM; N = 'SubscribedContent-338388Enabled'; V = 0; D = 1 }, @{ P = $CDM; N = 'PreInstalledAppsEnabled'; V = 0; D = 1 },
            @{ P = $CDM; N = 'OemPreInstalledAppsEnabled'; V = 0; D = 1 }, @{ P = "$Pol\CloudContent"; N = 'DisableWindowsConsumerFeatures'; V = 1 })
    Add-OzTweak -Id 'tips-off' -Cat 'Start' -Name 'No tips, tricks and "finish setup" nags' -Rec all `
        -Desc 'Removes Windows tips, Settings suggestions, the welcome experience and the "Let''s finish setting up" screen.' `
        -Reg @(@{ P = $CDM; N = 'SubscribedContent-338389Enabled'; V = 0; D = 1 }, @{ P = $CDM; N = 'SubscribedContent-353694Enabled'; V = 0; D = 1 },
            @{ P = $CDM; N = 'SubscribedContent-353696Enabled'; V = 0; D = 1 }, @{ P = $CDM; N = 'SubscribedContent-310093Enabled'; V = 0; D = 1 },
            @{ P = $CDM; N = 'SoftLandingEnabled'; V = 0; D = 1 }, @{ P = "$CU\UserProfileEngagement"; N = 'ScoobeSystemSettingEnabled'; V = 0 })
    Add-OzTweak -Id 'lockscreen-ads-off' -Cat 'Start' -Name 'No lock-screen ads and "fun facts"' -Rec all -Desc 'Keeps your lock screen clean.' `
        -Reg @(@{ P = $CDM; N = 'RotatingLockScreenOverlayEnabled'; V = 0; D = 1 }, @{ P = $CDM; N = 'SubscribedContent-338387Enabled'; V = 0; D = 1 })

    Add-OzTweak -Id 'taskbar-no-combine' -Cat 'Start' -Name 'Never combine taskbar buttons' -Rec none -MinBuild 22631 -Explorer `
        -Desc 'Every window gets its own taskbar button with its title, on every monitor.' `
        -Reg @(@{ P = $Adv; N = 'TaskbarGlomLevel'; V = 2; D = 0 }, @{ P = $Adv; N = 'MMTaskbarGlomLevel'; V = 2; D = 0 })
    Add-OzTweak -Id 'search-history-off' -Cat 'Start' -Name 'No search history on this device' -Rec all `
        -Desc 'Windows search stops remembering what you searched for on this PC.' `
        -Reg @(@{ P = "$CU\SearchSettings"; N = 'IsDeviceSearchHistoryEnabled'; V = 0; D = 1 })


    # =============================== EDGE / ONEDRIVE / STORE ===============================
    Add-OzTweak -Id 'edge-boost-off' -Cat 'Apps' -Name 'Edge: no startup boost / background mode' -Rec all `
        -Desc 'Edge stops pre-loading at sign-in and running after you close it. Frees RAM and CPU.' `
        -Reg @(@{ P = $Edge; N = 'StartupBoostEnabled'; V = 0 }, @{ P = $Edge; N = 'BackgroundModeEnabled'; V = 0 })
    Add-OzTweak -Id 'edge-nags-off' -Cat 'Apps' -Name 'Edge: no nags, shopping or recommendations' -Rec all `
        -Desc 'Skips first-run, default-browser prompts, shopping assistant and recommendations.' -Note 'Edge will show "managed by your organization" (normal for policies).' `
        -Reg @(@{ P = $Edge; N = 'HideFirstRunExperience'; V = 1 }, @{ P = $Edge; N = 'DefaultBrowserSettingEnabled'; V = 0 },
            @{ P = $Edge; N = 'ShowRecommendationsEnabled'; V = 0 }, @{ P = $Edge; N = 'EdgeShoppingAssistantEnabled'; V = 0 },
            @{ P = $Edge; N = 'PersonalizationReportingEnabled'; V = 0 }, @{ P = $Edge; N = 'SpotlightExperiencesAndRecommendationsEnabled'; V = 0 })
    Add-OzTweak -Id 'edge-telemetry-off' -Cat 'Apps' -Name 'Edge: minimum diagnostic data' -Rec all -Desc 'Edge sends only required diagnostic data.' `
        -Reg @(@{ P = $Edge; N = 'DiagnosticData'; V = 0 })
    Add-OzTweak -Id 'edgeupdate-manual' -Cat 'Apps' -Name 'Edge updater services to Manual' -Rec lowend -Desc 'Edge still updates, just without two always-on services.' `
        -Note 'Edge resets these when it updates itself. The app flags it when that happens.' `
        -Svc @(@{ N = 'edgeupdate'; V = 3; D = 2 }, @{ N = 'edgeupdatem'; V = 3; D = 3 })
    Add-OzTweak -Id 'store-autoupdate-off' -Cat 'Apps' -Name 'Store apps do not auto-update' -Risk Moderate -Rec lowend `
        -Desc 'No surprise downloads hogging the disk and network. Update from the Store when you choose.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'; N = 'AutoDownload'; V = 2 })
    Add-OzTweak -Id 'onedrive-remove' -Cat 'Apps' -Name 'Uninstall OneDrive' -Risk Moderate -Rec none `
        -Desc 'Removes the OneDrive app and its startup entry. Turn this switch back on to reinstall it.' `
        -Note 'Turn off "Back up folders" in OneDrive first. Your files stay in your user folder.' `
        -Detect {
        -not ((Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe") -or (Test-Path "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"))
    } -Apply {
        Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $setup = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") +
        @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName) |
            Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($setup) { Start-Process -FilePath $setup -ArgumentList '/uninstall' -Wait -WindowStyle Hidden }
        elseif (Get-Command winget -ErrorAction SilentlyContinue) { & winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements | Out-Null }
        else { throw 'OneDrive uninstaller not found.' }
    } -Revert {
        if (Get-Command winget -ErrorAction SilentlyContinue) { & winget install --id Microsoft.OneDrive -e --silent --accept-source-agreements --accept-package-agreements | Out-Null }
        elseif (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") { Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -Wait }
        else { throw 'Install OneDrive from https://www.microsoft.com/microsoft-365/onedrive/download' }
    }
    Add-OzTweak -Id 'onedrive-block' -Cat 'Apps' -Name 'Block OneDrive from syncing' -Rec none -Desc 'Prevents OneDrive from running even if it is reinstalled by an update.' `
        -Reg @(@{ P = "$Pol\OneDrive"; N = 'DisableFileSyncNGSC'; V = 1 })

    # =============================== INSTALLED APPS ===============================
    # Shown only when the app is installed on this PC.
    Add-OzTweak -Id 'chrome-bg-off' -Cat 'Installed' -Name 'Chrome: no background mode or usage reports' -Rec all `
        -Desc 'Chrome stops running after you close it, stops its cleanup scanner and stops sending usage statistics.' `
        -Note 'Chrome will show "managed by your organization" (normal for policies).' `
        -Requires { Test-OzAppInstalled 'Chrome' } `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Google\Chrome'; N = 'BackgroundModeEnabled'; V = 0 },
            @{ P = 'HKLM:\SOFTWARE\Policies\Google\Chrome'; N = 'ChromeCleanupEnabled'; V = 0 },
            @{ P = 'HKLM:\SOFTWARE\Policies\Google\Chrome'; N = 'MetricsReportingEnabled'; V = 0 })
    Add-OzTweak -Id 'firefox-telemetry-off' -Cat 'Installed' -Name 'Firefox: no telemetry or studies' -Rec all `
        -Desc 'Firefox stops sending telemetry, stops installing studies and stops its default-browser agent task.' `
        -Requires { Test-OzAppInstalled 'Firefox' } `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'; N = 'DisableTelemetry'; V = 1 },
            @{ P = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'; N = 'DisableFirefoxStudies'; V = 1 },
            @{ P = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'; N = 'DisableDefaultBrowserAgent'; V = 1 })
    Add-OzTweak -Id 'office-telemetry-off' -Cat 'Installed' -Name 'Office: minimum diagnostic data' -Rec all `
        -Desc 'Word, Excel, Outlook and the other Office apps send no optional diagnostic data.' `
        -Requires { Test-OzAppInstalled 'Office' } `
        -Reg @(@{ P = 'HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry'; N = 'SendTelemetry'; V = 3 },
            @{ P = 'HKCU:\Software\Policies\Microsoft\office\common\clienttelemetry'; N = 'DisableTelemetry'; V = 1 })


    # =============================== WINDOWS UPDATE ===============================
    Add-OzTweak -Id 'wu-no-autoreboot' -Cat 'Update' -Name 'Never auto-restart while signed in' -Rec all `
        -Desc 'Updates still install, but Windows will not reboot your PC in the middle of a game or render.' `
        -Reg @(@{ P = "$WU\AU"; N = 'NoAutoRebootWithLoggedOnUsers'; V = 1 })
    Add-OzTweak -Id 'wu-no-drivers' -Cat 'Update' -Name 'Do not get drivers from Windows Update' -Risk Moderate -Rec none `
        -Desc 'Stops Windows from replacing the GPU / chipset drivers you installed yourself.' -Note 'You must keep drivers updated yourself (see DRIVERS).' `
        -Reg @(@{ P = $WU; N = 'ExcludeWUDriversInQualityUpdate'; V = 1 })
    Add-OzTweak -Id 'wu-notify' -Cat 'Update' -Name 'Ask before downloading updates' -Risk Moderate -Rec none `
        -Desc 'Windows notifies you instead of downloading in the background - good on slow or metered internet.' -Note 'Remember to install security updates.' `
        -Reg @(@{ P = "$WU\AU"; N = 'AUOptions'; V = 2 }, @{ P = "$WU\AU"; N = 'NoAutoUpdate'; V = 0 })
    Add-OzTweak -Id 'wu-defer-features' -Cat 'Update' -Name 'Delay feature updates 1 year' -Risk Moderate -Rec none `
        -Desc 'Security updates keep coming; big version upgrades wait until they are stable (Pro / Enterprise).' `
        -Reg @(@{ P = $WU; N = 'DeferFeatureUpdates'; V = 1 }, @{ P = $WU; N = 'DeferFeatureUpdatesPeriodInDays'; V = 365 })
    Add-OzTweak -Id 'wu-no-mrt' -Cat 'Update' -Name 'Skip the monthly Malicious Software Removal Tool' -Rec none `
        -Desc 'Saves a monthly download and scan if you already use Defender or another antivirus.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\MRT'; N = 'DontOfferThroughWUAU'; V = 1 })

    Add-OzTweak -Id 'wu-pin-version' -Cat 'Update' -Name 'Stay on your current Windows version' -Risk Moderate -Rec none `
        -Desc 'Windows Update keeps sending security fixes for the version you have now, but does not upgrade you to the next yearly version (Pro / Enterprise).' `
        -Note 'Turn this off before your version stops getting security updates.' `
        -Requires { [bool]$Oz.PinVersion } `
        -Reg @(@{ P = $WU; N = 'TargetReleaseVersion'; V = 1 }, @{ P = $WU; N = 'ProductVersion'; V = $pinProduct; T = 'String' },
            @{ P = $WU; N = 'TargetReleaseVersionInfo'; V = $Oz.PinVersion; T = 'String' })
    Add-OzTweak -Id 'wu-defer-quality' -Cat 'Update' -Name 'Delay monthly updates 7 days' -Risk Moderate -Rec none `
        -Desc 'Monthly fixes arrive a week later, after early problems are found and pulled (Pro / Enterprise).' `
        -Reg @(@{ P = $WU; N = 'DeferQualityUpdates'; V = 1 }, @{ P = $WU; N = 'DeferQualityUpdatesPeriodInDays'; V = 7 })


    # =============================== STORAGE & NTFS ===============================
    Add-OzTweak -Id 'ntfs-lastaccess-off' -Cat 'Storage' -Name 'Disable NTFS last-access timestamps' -Rec all `
        -Desc 'Reading a file no longer triggers a disk write. Less I/O on every drive.' `
        -Detect { $v = (Get-OzReg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate').Value; ($null -ne $v) -and (([int64]$v -band 1) -eq 1) } `
        -Apply { & "$env:SystemRoot\System32\fsutil.exe" behavior set disablelastaccess 1 | Out-Null } `
        -Revert { & "$env:SystemRoot\System32\fsutil.exe" behavior set disablelastaccess 2 | Out-Null }
    Add-OzTweak -Id 'ntfs-8dot3-off' -Cat 'Storage' -Name 'Disable 8.3 short file names' -Risk Moderate -Rec all `
        -Desc 'NTFS stops creating legacy DOS names for every new file - faster in big folders.' `
        -Reg @(@{ P = $FS; N = 'NtfsDisable8dot3NameCreation'; V = 1; D = 2 })
    Add-OzTweak -Id 'ntfs-memory' -Cat 'Storage' -Name 'More RAM for NTFS cache' -Rec ram16plus -Reboot `
        -Desc 'Lets NTFS use more paged pool for file metadata. Speeds up heavy file work on 16 GB+.' `
        -Requires { $Oz.Sys -and $Oz.Sys.Memory.GB -ge 8 } `
        -Reg @(@{ P = $FS; N = 'NtfsMemoryUsage'; V = 2 })
    Add-OzTweak -Id 'long-paths' -Cat 'Storage' -Name 'Enable long file paths' -Rec all `
        -Desc 'Apps can use paths longer than 260 characters (fixes many dev-tool and game-mod errors).' `
        -Reg @(@{ P = $FS; N = 'LongPathsEnabled'; V = 1; D = 0 })
    Add-OzTweak -Id 'trim-on' -Cat 'Storage' -Name 'Make sure SSD TRIM is ON' -Rec ssd `
        -Desc 'TRIM keeps SSDs fast over time. This guarantees it was not disabled.' `
        -Reg @(@{ P = $FS; N = 'DisableDeleteNotification'; V = 0; D = 0 })
    Add-OzTweak -Id 'storage-sense-on' -Cat 'Storage' -Name 'Storage Sense ON' -Rec lowend `
        -Desc 'Windows cleans temp files and the recycle bin automatically when space runs low.' `
        -Reg @(@{ P = "$CU\StorageSense\Parameters\StoragePolicy"; N = '01'; V = 1; D = 0 })

    Add-OzTweak -Id 'reserved-storage-off' -Cat 'Storage' -Name 'Free the space Windows reserves for updates' -Risk Moderate -Rec lowend `
        -Desc 'Gives back the 5-7 GB that Windows keeps aside for updates. Worth it on 64-128 GB drives.' `
        -Note 'Updates then need that much free space while they install. Windows cannot change this while an update is waiting.' `
        -Requires { [bool](Get-Command Get-WindowsReservedStorageState -ErrorAction SilentlyContinue) } `
        -Detect { [string](Get-WindowsReservedStorageState -ErrorAction Stop).ReservedStorageState -eq 'Disabled' } `
        -Apply { Set-WindowsReservedStorageState -State Disabled -ErrorAction Stop | Out-Null } `
        -Revert { Set-WindowsReservedStorageState -State Enabled -ErrorAction Stop | Out-Null }


    # =============================== SECURITY HARDENING ===============================
    Add-OzTweak -Id 'smb1-off' -Cat 'Security' -Name 'Disable SMBv1' -Rec all `
        -Desc 'The protocol WannaCry used. Modern Windows does not need it.' -Note 'Very old NAS boxes may need SMBv1.' `
        -Detect { -not (Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol } `
        -Apply { Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction Stop } `
        -Revert { Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force -ErrorAction Stop }
    Add-OzTweak -Id 'llmnr-off' -Cat 'Security' -Name 'Disable LLMNR' -Rec all `
        -Desc 'Blocks a legacy name-resolution protocol that attackers abuse on public Wi-Fi.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; N = 'EnableMulticast'; V = 0 })
    Add-OzTweak -Id 'anon-restrict' -Cat 'Security' -Name 'Restrict anonymous SAM / share access' -Rec all `
        -Desc 'Anonymous users cannot list accounts or shares on this PC.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymous'; V = 1; D = 0 },
            @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RestrictAnonymousSAM'; V = 1; D = 1 },
            @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'EveryoneIncludesAnonymous'; V = 0; D = 0 })
    Add-OzTweak -Id 'netbios-off' -Cat 'Security' -Name 'Disable NetBIOS over TCP/IP' -Risk Moderate -Rec none `
        -Desc 'Closes ports 137-139 on every adapter.' -Note 'Very old NAS / printers found by NetBIOS name may need their IP instead.' `
        -Detect {
        $ifs = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction Stop)
        if (-not $ifs) { return $false }
        -not ($ifs | Where-Object { (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).NetbiosOptions -ne 2 })
    } -Apply {
        foreach ($i in @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces')) {
            Set-OzTracked 'netbios-off' ('HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\' + $i.PSChildName) 'NetbiosOptions' 2
        }
    }
    Add-OzTweak -Id 'autorun-off' -Cat 'Security' -Name 'Disable AutoRun on all drives' -Rec all `
        -Desc 'USB sticks and discs can no longer launch programs automatically.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; N = 'NoDriveTypeAutoRun'; V = 255 })
    Add-OzTweak -Id 'remote-assist-off' -Cat 'Security' -Name 'Disable Remote Assistance' -Rec all `
        -Desc 'Closes the legacy "invite someone to help you" door. Quick Assist still works.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance'; N = 'fAllowToGetHelp'; V = 0; D = 1 })
    Add-OzTweak -Id 'sec-notifs-reduce' -Cat 'Security' -Name 'Fewer non-critical security notifications' -Risk Moderate -Rec none `
        -Desc 'Hides "summary" and informational Windows Security toasts. Threat alerts still show.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications'; N = 'DisableEnhancedNotifications'; V = 1 })

    Add-OzTweak -Id 'pua-block-on' -Cat 'Security' -Name 'Block potentially unwanted apps' -Rec all `
        -Desc 'Defender blocks adware, bundled toolbars, browser hijackers and hidden crypto miners.' -Note 'Only works while Microsoft Defender is your antivirus.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'; N = 'PUAProtection'; V = 1 })
    Add-OzTweak -Id 'wpad-off' -Cat 'Security' -Name 'Disable proxy auto-discovery (WPAD)' -Rec all `
        -Desc 'Stops Windows from asking the network for a proxy, a trick used to intercept traffic on public Wi-Fi.' -Note 'Company networks that hand out their proxy automatically need this on.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'; N = 'DisableWpad'; V = 1 })
    Add-OzTweak -Id 'autoplay-off' -Cat 'Security' -Name 'Disable AutoPlay' -Rec all `
        -Desc 'Plugging in a USB drive, phone or disc no longer pops up an action or opens an app by itself.' `
        -Reg @(@{ P = "$CU\Explorer\AutoplayHandlers"; N = 'DisableAutoplay'; V = 1; D = 0 })
    Add-OzTweak -Id 'lsa-protect-on' -Cat 'Security' -Name 'LSA protection ON' -Risk Moderate -Rec none -MinBuild 22621 -Reboot `
        -Desc 'Runs the Windows sign-in process as protected, so password-stealing tools cannot read its memory. Can be turned off again.' `
        -Note 'Some old smart-card readers or password plug-ins may stop loading.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'; N = 'RunAsPPL'; V = 2 })
    Add-OzTweak -Id 'rdp-off' -Cat 'Security' -Name 'Block Remote Desktop connections' -Rec all `
        -Desc 'Makes sure nobody can sign in to this PC with Remote Desktop. Quick Assist and remote tools you start yourself still work.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'; N = 'fDenyTSConnections'; V = 1; D = 1 })
    Add-OzTweak -Id 'wsh-off' -Cat 'Security' -Name 'Disable Windows Script Host' -Risk Moderate -Rec none `
        -Desc 'Blocks .vbs and .js script files, a common way malware arrives in e-mail attachments and downloads.' -Note 'Some old installers and login scripts use these files.' `
        -Reg @(@{ P = 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings'; N = 'Enabled'; V = 0 })


    # =============================== DANGER ZONE ===============================
    Add-OzTweak -Id 'defender-rt-off' -Cat 'Danger' -Name 'Turn off Defender real-time protection' -Rec none -Reboot `
        -Desc 'Stops on-access scanning. Only do this if you install another antivirus or the PC is offline.' `
        -Note 'Turn OFF Tamper Protection in Windows Security first, or Windows blocks this.' `
        -Detect { -not (Get-MpComputerStatus -ErrorAction Stop).RealTimeProtectionEnabled } `
        -Apply {
        $st = Get-MpComputerStatus -ErrorAction SilentlyContinue
        if ($st -and $st.IsTamperProtected) { throw 'Tamper Protection is ON. Open Windows Security > Virus & threat protection > Manage settings, turn it off, then try again.' }
        $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'
        foreach ($n in 'DisableRealtimeMonitoring', 'DisableBehaviorMonitoring', 'DisableOnAccessProtection', 'DisableScanOnRealtimeEnable', 'DisableIOAVProtection') {
            Set-OzTracked 'defender-rt-off' $p $n 1
        }
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    } -Revert { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue }

    Add-OzTweak -Id 'smartscreen-off' -Cat 'Danger' -Name 'Disable SmartScreen' -Rec none `
        -Desc 'No more "Windows protected your PC" for unknown downloads. You lose phishing and malware URL checks.' `
        -Reg @(@{ P = "$Pol\System"; N = 'EnableSmartScreen'; V = 0 },
            @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer'; N = 'SmartScreenEnabled'; V = 'Off'; T = 'String' },
            @{ P = $Edge; N = 'SmartScreenEnabled'; V = 0 }, @{ P = "$CU\AppHost"; N = 'EnableWebContentEvaluation'; V = 0 })

    Add-OzTweak -Id 'hvci-off' -Cat 'Danger' -Name 'Turn off Memory Integrity (HVCI)' -Rec none -Reboot `
        -Desc 'Can return a few % FPS in some games. Removes protection against malicious kernel drivers.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'; N = 'Enabled'; V = 0 })

    Add-OzTweak -Id 'vbs-off' -Cat 'Danger' -Name 'Turn off Virtualization-Based Security' -Rec none -Reboot `
        -Desc 'Disables VBS entirely (HVCI, Credential Guard). Some PCs lock VBS on in firmware and ignore this.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'; N = 'EnableVirtualizationBasedSecurity'; V = 0 })

    Add-OzTweak -Id 'mitigations-off' -Cat 'Danger' -Name 'Disable Spectre / Meltdown mitigations' -Rec none -Reboot `
        -Desc 'Mostly helps older Intel CPUs (pre-9th gen) in I/O-heavy work. Exposes the CPU to side-channel attacks.' `
        -Reg @(@{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; N = 'FeatureSettingsOverride'; V = 3 },
            @{ P = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'; N = 'FeatureSettingsOverrideMask'; V = 3 })
}
#endregion


#region ============================ PROFILES ============================
# A profile resolves to a list of tweak ids for the CURRENT PC.
# Danger Zone tweaks are filtered out of every profile, always.

$Oz.Core = @('telemetry-off', 'telemetry-tasks-off', 'ceip-off', 'appcompat-telemetry-off', 'werr-off', 'adid-off',
    'tailored-off', 'activity-off', 'feedback-off', 'copilot-off', 'recall-off', 'clicktodo-off')
$Oz.Clean = @('web-search-off', 'cortana-off', 'search-highlights-off', 'widgets-off', 'chat-off', 'start-recs-off',
    'start-suggest-off', 'tips-off', 'lockscreen-ads-off', 'notif-suggest-off', 'no-sync-ads', 'show-ext')

function Get-OzPlanFor {
    param([string]$Mode)
    if (-not $Oz.Sys -or $Oz.Sys.IsVM) { return @() }
    switch ($Mode) {
        'perf' { if ($Oz.Sys.IsLaptop) { 'plan-smart' } else { 'plan-perf' } }
        'max'  { 'plan-perf' }
        'cool' { if ($Oz.Sys.IsLaptop) { 'plan-cool' } else { 'plan-smart' } }
    }
}

function Initialize-OzProfiles {
    $Oz.Profiles = @(
        [pscustomobject]@{
            Key = 'auto'; Name = 'AUTO-TUNE THIS PC'; Icon = [char]0xE9D9; Color = '#00E5FF'; Featured = $true
            Sub = 'Built from your scan'
            Desc = 'Everything recommended for this exact machine: its tier, desktop or laptop, SSD or HDD, GPU and Windows version. Safe and fully reversible.'
            Resolve = { @($Oz.Tweaks | Where-Object { (Test-OzRecommended $_ $Oz.Sys) } | ForEach-Object Id) }
        }
        [pscustomobject]@{
            Key = 'revive'; Name = 'REVIVE CHEAP PC'; Icon = [char]0xE945; Color = '#FF3B5C'; Featured = $false
            Sub = 'Old, low-RAM or HDD machines'
            Desc = 'Strips Windows down: no animations, no background apps, no bloat services, no web junk in search. Makes 4-8 GB and hard-disk PCs usable again.'
            Resolve = {
                $ids = $Oz.Core + $Oz.Clean + @('visual-fx-perf', 'transparency-off', 'menu-delay', 'background-apps-off', 'gamedvr-off',
                    'svc-fax', 'svc-retaildemo', 'svc-maps', 'svc-wmpnet', 'svc-insider', 'edge-boost-off', 'edge-nags-off', 'edgeupdate-manual',
                    'store-autoupdate-off', 'storage-sense-on', 'ntfs-lastaccess-off', 'do-p2p-off', 'priority-sep')
                if ($Oz.Sys.Storage.SystemKind -eq 'HDD') { $ids += 'search-index-off' } else { $ids += 'startup-delay-off' }
                if ($Oz.Sys.Memory.GB -lt 8) { $ids += 'svc-diag' }
                if ($Oz.Sys.Storage.SizeGB -gt 0 -and $Oz.Sys.Storage.SizeGB -le 128) { $ids += 'reserved-storage-off' }
                $ids + @(Get-OzPlanFor 'perf')
            }
        }
        [pscustomobject]@{
            Key = 'maxperf'; Name = 'MAX PERFORMANCE'; Icon = [char]0xEC4A; Color = '#FF2BD6'; Featured = $false
            Sub = 'Desktops / laptops on AC'
            Desc = 'Every CPU core unparked, aggressive boost, games first in the scheduler, GPU scheduling on, background noise removed. Idle stays cool (5% minimum CPU state).'
            Resolve = {
                $Oz.Core + @('priority-sep', 'fth-off', 'mmcss-games', 'game-mode-on', 'gamedvr-off', 'gamebar-tips-off', 'hags-on',
                    'power-throttle-off', 'startup-delay-off', 'menu-delay', 'net-throttle-off', 'ntfs-lastaccess-off', 'background-apps-off',
                    'edge-boost-off', 'widgets-off', 'web-search-off', 'start-suggest-off', 'wu-no-autoreboot', 'do-p2p-off') + @(Get-OzPlanFor 'max')
            }
        }
        [pscustomobject]@{
            Key = 'cool'; Name = 'COOL & QUIET'; Icon = [char]0xE9CA; Color = '#2BFF9A'; Featured = $false
            Sub = 'Hot laptops, silent PCs, battery'
            Desc = 'Turbo-off cool plan on laptops (smart plan on desktops), fewer background processes and no surprise downloads. Lower temps, quieter fans, longer battery.'
            Resolve = {
                $Oz.Core + @('background-apps-off', 'edge-boost-off', 'gamedvr-off', 'svc-maps', 'svc-retaildemo', 'widgets-off',
                    'search-highlights-off', 'start-suggest-off', 'tips-off', 'store-autoupdate-off', 'do-p2p-off', 'ntfs-lastaccess-off',
                    'standby-net-off') + @(Get-OzPlanFor 'cool')
            }
        }
        [pscustomobject]@{
            Key = 'competitive'; Name = 'COMPETITIVE GAMING'; Icon = [char]0xE7FC; Color = '#8A5CFF'; Featured = $false
            Sub = 'Lowest input lag and ping'
            Desc = 'MAX PERFORMANCE plus raw mouse input, no sticky-key pop-ups, TCP no-delay, network card never sleeps, Ethernet power saving off and flip-model for windowed games.'
            Resolve = {
                $Oz.Core + @('priority-sep', 'fth-off', 'mmcss-games', 'game-mode-on', 'gamedvr-off', 'gamebar-tips-off', 'hags-on',
                    'power-throttle-off', 'net-throttle-off', 'nagle-off', 'nic-power-off', 'eee-off', 'mouse-accel-off', 'sticky-keys-off',
                    'windowed-opt-on', 'notif-suggest-off', 'background-apps-off', 'edge-boost-off', 'widgets-off', 'wu-no-autoreboot', 'do-p2p-off',
                    'kb-repeat-fast', 'gamebar-button-off') + @(Get-OzPlanFor 'max')
            }
        }
        [pscustomobject]@{
            Key = 'privacy'; Name = 'PRIVACY MAX'; Icon = [char]0xE72E; Color = '#FFB020'; Featured = $false
            Sub = 'Minimum data leaves this PC'
            Desc = 'All privacy, telemetry and AI switches, no cloud search, app permissions locked down, no sync, no ads anywhere. Camera and microphone are left for you to decide.'
            Resolve = {
                @($Oz.Tweaks | Where-Object { $_.Cat -in 'Privacy', 'AI', 'Installed' } | ForEach-Object Id) +
                @('web-search-off', 'cortana-off', 'cloud-search-off', 'search-highlights-off', 'edge-telemetry-off', 'edge-nags-off',
                    'do-p2p-off', 'llmnr-off', 'lockscreen-ads-off', 'start-suggest-off', 'tips-off', 'no-recent-files', 'svc-geo',
                    'search-history-off', 'wpad-off')
            }
        }
        [pscustomobject]@{
            Key = 'clean'; Name = 'CLEAN WINDOWS UI'; Icon = [char]0xE771; Color = '#4FD8FF'; Featured = $false
            Sub = 'Declutter Start, taskbar and Explorer'
            Desc = 'Classic right-click menu without app shortcuts, no widgets or chat icon, clean Start, no tips or ads, End Task on the taskbar, file extensions visible.'
            Resolve = {
                $Oz.Clean + @('classic-context', 'end-task', 'alt-tab-windows', 'shortcut-suffix-off', 'copilot-off', 'edge-nags-off',
                    'ctx-apps-off', 'store-openwith-off', 'spotlight-icon-off', 'copy-details')
            }
        }
    )
}

function Resolve-OzProfile {
    param($P)
    $ids = @(& $P.Resolve) | Where-Object { $_ } | Select-Object -Unique
    @($ids | Where-Object {
            $t = if ($Oz.TweakIndex.ContainsKey($_)) { $Oz.TweakIndex[$_] } else { $Oz.Tweaks | Where-Object Id -EQ $_ | Select-Object -First 1 }
            $t -and $t.Risk -ne 'Danger' -and (Test-OzApplicable $t $Oz.Sys)
        })
}
#endregion

#region ============================ DEBLOAT CATALOG ============================
# Rec = pre-selected by "Select recommended". Protected system apps (Store, Calculator,
# Notepad, Terminal, Security, frameworks) are never listed so they cannot be removed.
$Oz.Bloat = @(
    @{ P = 'Microsoft.BingNews'; N = 'Microsoft News'; R = $true }
    @{ P = 'Microsoft.BingWeather'; N = 'Weather'; R = $true }
    @{ P = 'Microsoft.BingSearch'; N = 'Bing Search'; R = $true }
    @{ P = 'Microsoft.BingFinance'; N = 'Money'; R = $true }
    @{ P = 'Microsoft.BingSports'; N = 'Sports'; R = $true }
    @{ P = 'Microsoft.GetHelp'; N = 'Get Help'; R = $true }
    @{ P = 'Microsoft.Getstarted'; N = 'Tips'; R = $true }
    @{ P = 'Microsoft.Microsoft3DViewer'; N = '3D Viewer'; R = $true }
    @{ P = 'Microsoft.MSPaint'; N = 'Paint 3D'; R = $true }
    @{ P = 'Microsoft.MicrosoftOfficeHub'; N = 'Microsoft 365 (Office hub)'; R = $true }
    @{ P = 'Microsoft.Office.OneNote'; N = 'OneNote for Windows 10'; R = $true }
    @{ P = 'Microsoft.Office.Sway'; N = 'Sway'; R = $true }
    @{ P = 'Microsoft.MicrosoftSolitaireCollection'; N = 'Solitaire Collection'; R = $true }
    @{ P = 'Microsoft.MixedReality.Portal'; N = 'Mixed Reality Portal'; R = $true }
    @{ P = 'Microsoft.People'; N = 'People'; R = $true }
    @{ P = 'Microsoft.SkypeApp'; N = 'Skype'; R = $true }
    @{ P = 'Microsoft.Wallet'; N = 'Wallet'; R = $true }
    @{ P = 'Microsoft.WindowsFeedbackHub'; N = 'Feedback Hub'; R = $true }
    @{ P = 'Microsoft.WindowsMaps'; N = 'Maps'; R = $true }
    @{ P = 'microsoft.windowscommunicationsapps'; N = 'Mail and Calendar (retired)'; R = $true }
    @{ P = 'Microsoft.OutlookForWindows'; N = 'Outlook (new)'; R = $true }
    @{ P = 'Microsoft.ZuneVideo'; N = 'Movies & TV'; R = $true }
    @{ P = 'Microsoft.549981C3F5F10'; N = 'Cortana'; R = $true }
    @{ P = 'Microsoft.PowerAutomateDesktop'; N = 'Power Automate'; R = $true }
    @{ P = 'Microsoft.MicrosoftPowerBIForWindows'; N = 'Power BI'; R = $true }
    @{ P = 'Microsoft.Whiteboard'; N = 'Whiteboard'; R = $true }
    @{ P = 'Microsoft.MicrosoftJournal'; N = 'Journal'; R = $true }
    @{ P = 'Microsoft.Windows.DevHome'; N = 'Dev Home'; R = $true }
    @{ P = 'Microsoft.Copilot'; N = 'Copilot app'; R = $true }
    @{ P = 'Microsoft.Windows.Ai.Copilot.Provider'; N = 'Copilot provider'; R = $true }
    @{ P = 'MicrosoftWindows.Client.WebExperience'; N = 'Widgets'; R = $true }
    @{ P = 'Microsoft.WidgetsPlatformRuntime'; N = 'Widgets Platform Runtime'; R = $true }
    @{ P = 'MicrosoftTeams'; N = 'Teams (personal, old)'; R = $true }
    @{ P = 'MSTeams'; N = 'Microsoft Teams'; R = $false }
    @{ P = 'MicrosoftCorporationII.MicrosoftFamily'; N = 'Family Safety'; R = $true }
    @{ P = 'Clipchamp.Clipchamp'; N = 'Clipchamp'; R = $true }
    @{ P = 'Microsoft.Advertising.Xaml'; N = 'Advertising SDK'; R = $true }
    @{ P = 'Microsoft.Todos'; N = 'Microsoft To Do'; R = $false }
    @{ P = 'Microsoft.MicrosoftStickyNotes'; N = 'Sticky Notes'; R = $false }
    @{ P = 'Microsoft.WindowsAlarms'; N = 'Clock / Alarms'; R = $false }
    @{ P = 'Microsoft.WindowsCamera'; N = 'Camera'; R = $false }
    @{ P = 'Microsoft.WindowsSoundRecorder'; N = 'Sound Recorder'; R = $false }
    @{ P = 'Microsoft.ZuneMusic'; N = 'Media Player'; R = $false }
    @{ P = 'Microsoft.Windows.Photos'; N = 'Photos'; R = $false }
    @{ P = 'Microsoft.YourPhone'; N = 'Phone Link'; R = $false }
    @{ P = 'MicrosoftCorporationII.QuickAssist'; N = 'Quick Assist'; R = $false }
    @{ P = 'Microsoft.StartExperiencesApp'; N = 'Start Experiences'; R = $false }
    @{ P = 'Microsoft.GamingApp'; N = 'Xbox app'; R = $false }
    @{ P = 'Microsoft.XboxApp'; N = 'Xbox Console Companion'; R = $true }
    @{ P = 'Microsoft.XboxGamingOverlay'; N = 'Xbox Game Bar'; R = $false }
    @{ P = 'Microsoft.XboxGameOverlay'; N = 'Xbox Game Overlay'; R = $false }
    @{ P = 'Microsoft.XboxSpeechToTextOverlay'; N = 'Xbox speech-to-text'; R = $false }
    @{ P = 'Microsoft.Xbox.TCUI'; N = 'Xbox TCUI'; R = $false }
    @{ P = 'Microsoft.XboxIdentityProvider'; N = 'Xbox Identity (needed for Xbox sign-in in games)'; R = $false }
    @{ P = 'SpotifyAB.SpotifyMusic'; N = 'Spotify'; R = $true }
    @{ P = 'Disney.37853FA22FAF4'; N = 'Disney+'; R = $true }
    @{ P = '4DF9E0F8.Netflix'; N = 'Netflix'; R = $true }
    @{ P = 'AmazonVideo.PrimeVideo'; N = 'Prime Video'; R = $true }
    @{ P = 'BytedancePte.Ltd.TikTok'; N = 'TikTok'; R = $true }
    @{ P = 'Facebook.Facebook*'; N = 'Facebook'; R = $true }
    @{ P = 'Facebook.Instagram*'; N = 'Instagram'; R = $true }
    @{ P = '5319275A.WhatsAppDesktop'; N = 'WhatsApp'; R = $false }
    @{ P = 'king.com.*'; N = 'Candy Crush and other King games'; R = $true }
    @{ P = '*.LinkedInforWindows'; N = 'LinkedIn'; R = $true }
    @{ P = '5A894077.McAfeeSecurity'; N = 'McAfee trial'; R = $true }
    @{ P = 'Microsoft.WindowsTerminalPreview'; N = 'Terminal Preview'; R = $false }
)
#endregion

#region ============================ CLEANUP ============================
# CLEAN UP FILES (TOOLS page): the user picks the drives, SCAN measures what can be cleaned there,
# and only the items they tick are deleted. Nothing outside this list is ever offered:
#   - Windows cache folders (Get-OzCleanCatalog), on the Windows drive only;
#   - the Recycle Bin, on each local drive the user picked.
# Every folder is checked by Test-OzCleanPath when it is measured and again right before it is
# emptied: on the Windows drive, not a drive root, the expected Windows folder, not holding a
# personal or system folder, and no junction or symbolic link on the way. Inside, links are never
# followed and never deleted (Clear-OzFolder), so nothing on another drive can be reached.
# Up to 1.2.0 Quick clean used Remove-Item -Recurse, which in Windows PowerShell 5.1 can follow
# such a link, and emptied the Recycle Bin of every drive without asking.

function Get-OzWindowsDrive {
    # 'C:' for the drive Windows runs from
    $root = ''
    try { $root = [IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows')) } catch { }
    if (-not $root) { $root = [string]$env:SystemDrive }
    $root.TrimEnd('\').ToUpperInvariant()
}

function Get-OzCleanProtected {
    # Folders that must never be emptied, and never sit inside a folder being emptied
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($v in @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData,
            $env:PUBLIC, $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $env:OneDrive)) {
        if ($v) { $list.Add($v) }
    }
    if ($env:USERPROFILE) { $list.Add((Split-Path -Parent $env:USERPROFILE)) }
    foreach ($f in 'Desktop', 'MyDocuments', 'MyPictures', 'MyMusic', 'MyVideos', 'Favorites', 'System', 'SystemX86') {
        try { $p = [Environment]::GetFolderPath($f); if ($p) { $list.Add($p) } } catch { }
    }
    # Downloads and the newer library folders only live in the registry
    $usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    foreach ($n in '{374DE290-123F-4565-9164-39C4925E467B}', '{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}', '{F42EE2D3-909F-4907-8871-4C22FC0BF756}',
        '{0DDD015D-B06C-45D5-8C4C-F59713854639}', '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}', '{A0C69A99-21C8-4671-8703-7934162FCF1D}') {
        try {
            $v = (Get-ItemProperty -LiteralPath $usf -Name $n -ErrorAction Stop).$n
            if ($v) { $list.Add([Environment]::ExpandEnvironmentVariables([string]$v)) }
        } catch { }
    }
    $list.ToArray()
}

function Test-OzCleanPath {
    # Returns '' when this folder may be emptied, otherwise the reason it must not.
    # $Tail is a regex for how the full path must end, e.g. '\\Temp$'.
    param([string]$Path, [string]$Tail)
    if (-not $Path -or $Path -notmatch '^[A-Za-z]:\\') { return 'not a full path' }
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return 'not a valid path' }
    $root = [IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($root -ne (Get-OzWindowsDrive)) { return 'not on the Windows drive' }
    if ($full.Length -le $root.Length) { return 'a whole drive' }
    if (-not $Tail -or $full -notmatch $Tail) { return 'not the expected Windows folder' }
    foreach ($p in @(Get-OzCleanProtected)) {
        try { $pf = [IO.Path]::GetFullPath($p).TrimEnd('\') } catch { continue }
        if ($pf -eq $full -or $pf.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'it holds personal or system files' }
    }
    # A junction or symbolic link anywhere on the way means the real folder could be on another drive
    for ($d = $full; $d -and $d.Length -gt $root.Length; $d = [IO.Path]::GetDirectoryName($d)) {
        try {
            if (([IO.Directory]::Exists($d) -or [IO.File]::Exists($d)) -and ([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint)) {
                return 'it is a link to another place'
            }
        } catch { return 'it could not be checked' }
    }
    ''
}

function Clear-OzFolder {
    # Deletes the files inside $Path ($Filter applies to the top level only) and the subfolders left
    # empty. Junctions and symbolic links are skipped, never followed and never deleted, so nothing
    # outside $Path can be reached. Files in use stay. Returns the bytes freed.
    param([string]$Path, [string]$Filter = '*')
    $freed = [int64]0
    if (-not $Path -or -not [IO.Directory]::Exists($Path)) { return $freed }
    $link = [IO.FileAttributes]::ReparsePoint
    $top = New-Object IO.DirectoryInfo $Path
    if ($top.Attributes -band $link) { return $freed }
    $dirs = New-Object System.Collections.Generic.List[object]
    $todo = New-Object System.Collections.Generic.Stack[object]
    $todo.Push(@($top, $Filter))
    while ($todo.Count) {
        $cur = $todo.Pop()
        $dir = $cur[0]
        # Checked again right before reading it, in case it was swapped for a link meanwhile
        try { $dir.Refresh(); if ($dir.Attributes -band $link) { continue } } catch { continue }
        $items = @()
        try { $items = @($dir.GetFileSystemInfos($cur[1])) } catch { continue }
        foreach ($i in $items) {
            if ($i.Attributes -band $link) { continue }
            if ($i -is [IO.DirectoryInfo]) { $dirs.Add($i); $todo.Push(@($i, '*')); continue }
            try {
                $len = $i.Length
                if ($i.Attributes -band [IO.FileAttributes]::ReadOnly) { $i.Attributes = [IO.FileAttributes]::Normal }
                $i.Delete()
                $freed += $len
            } catch { }
        }
    }
    # Deepest first; a folder that still has something in it is kept
    for ($n = $dirs.Count - 1; $n -ge 0; $n--) {
        try { $dirs[$n].Refresh(); if (-not ($dirs[$n].Attributes -band $link)) { $dirs[$n].Delete($false) } } catch { }
    }
    $freed
}

function Get-OzFolderSize {
    # The bytes Clear-OzFolder would look at in $Path, by the same rules (links are not followed).
    # 0 when the folder does not exist, -1 when it exists but cannot be read.
    param([string]$Path, [string]$Filter = '*')
    $total = [int64]0
    if (-not $Path -or -not [IO.Directory]::Exists($Path)) { return $total }
    $link = [IO.FileAttributes]::ReparsePoint
    $top = New-Object IO.DirectoryInfo $Path
    if ($top.Attributes -band $link) { return $total }
    $first = $null
    try { $first = $top.GetFileSystemInfos($Filter) } catch { return [int64]-1 }
    $todo = New-Object System.Collections.Generic.Stack[object]
    $todo.Push($first)
    while ($todo.Count) {
        foreach ($i in $todo.Pop()) {
            if ($i.Attributes -band $link) { continue }
            if ($i -is [IO.DirectoryInfo]) { try { $todo.Push($i.GetFileSystemInfos()) } catch { }; continue }
            $total += $i.Length
        }
    }
    $total
}

function Format-OzBytes {
    param([int64]$Bytes)
    if ($Bytes -lt 0) { return (T 'size unknown') }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -gt 0) { return ('{0:N0} KB' -f [math]::Max(1, [math]::Round($Bytes / 1KB))) }
    '0 MB'
}

function Get-OzLongPath {
    # 'C:\Users\OSCARV~1\AppData\Local\Temp' -> 'C:\Users\Oscar Vega\AppData\Local\Temp', for display and to
    # spot TEMP and TMP naming the same folder. Returns the path unchanged when it cannot be resolved.
    param([string]$Path)
    if ($Path -notmatch '~') { return $Path }
    try {
        $di = New-Object IO.DirectoryInfo $Path
        if (-not $di.Exists -or -not $di.Parent) { return $Path }
        $parent = Get-OzLongPath $di.Parent.FullName
        $m = @((New-Object IO.DirectoryInfo $parent).GetDirectories($di.Name))
        if ($m.Count -eq 1) { return $m[0].FullName }
    } catch { }
    $Path
}

function New-OzCleanFolder {
    param([string]$Path, [string]$Tail, [string]$Filter = '*')
    [pscustomobject]@{ Path = $Path; Tail = $Tail; Filter = $Filter }
}

function Get-OzCleanCatalog {
    # Every Windows cache CLEAN UP FILES can offer. All of it lives on the Windows drive.
    # Rec = pre-selected after a scan. Tail = how each full path must end (see Test-OzCleanPath).
    $la = $env:LOCALAPPDATA
    $win = $env:SystemRoot
    $temps = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($p in @($env:TEMP, $env:TMP)) {
        if (-not $p) { continue }
        $p = Get-OzLongPath $p.TrimEnd('\')
        $k = $p.ToUpperInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        # ...\Temp, or ...\Temp\2 in a Remote Desktop session
        $temps.Add((New-OzCleanFolder $p '\\Temp(\\\d+)?$'))
    }
    $none = [string[]]@()
    @(
        [pscustomobject]@{ Id = 'temp'; Kind = 'Folders'; Rec = $true; Services = $none; Folders = $temps.ToArray()
            Name = 'Your temp folder'; Desc = 'Leftovers from installers and apps. Files that are open right now are skipped.'
        }
        [pscustomobject]@{ Id = 'wintemp'; Kind = 'Folders'; Rec = $true; Services = $none; Folders = @((New-OzCleanFolder "$win\Temp" '\\Temp$'))
            Name = 'Windows temp'; Desc = 'Leftovers from Windows itself and from installers that ran as administrator.'
        }
        [pscustomobject]@{ Id = 'wu'; Kind = 'Folders'; Rec = $true; Services = [string[]]@('wuauserv', 'bits')
            Folders = @((New-OzCleanFolder "$win\SoftwareDistribution\Download" '\\SoftwareDistribution\\Download$'))
            Name = 'Windows Update downloads'; Desc = 'Update files that are already installed. Windows downloads again anything it still needs.'
        }
        [pscustomobject]@{ Id = 'do'; Kind = 'DeliveryOpt'; Rec = $true; Services = $none
            Folders = @((New-OzCleanFolder "$win\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" '\\Windows\\DeliveryOptimization\\Cache$'))
            Name = 'Delivery Optimization cache'; Desc = 'Pieces of updates Windows keeps to share with other PCs.'
        }
        [pscustomobject]@{ Id = 'thumbs'; Kind = 'Folders'; Rec = $true; Services = $none
            Folders = @((New-OzCleanFolder "$la\Microsoft\Windows\Explorer" '\\Microsoft\\Windows\\Explorer$' 'thumbcache_*.db'))
            Name = 'Thumbnail cache'; Desc = 'Picture and video previews. Windows makes them again, so big picture folders open slower once.'
        }
        [pscustomobject]@{ Id = 'dumps'; Kind = 'Folders'; Rec = $true; Services = $none; Folders = @((New-OzCleanFolder "$la\CrashDumps" '\\CrashDumps$'))
            Name = 'Crash dumps'; Desc = 'Memory dumps from apps that crashed. Only needed to send a crash to the app maker.'
        }
        [pscustomobject]@{ Id = 'wer'; Kind = 'Folders'; Rec = $true; Services = $none
            Folders = @((New-OzCleanFolder "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" '\\Microsoft\\Windows\\WER\\ReportArchive$'),
                (New-OzCleanFolder "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" '\\Microsoft\\Windows\\WER\\ReportQueue$'))
            Name = 'Error reports'; Desc = 'Problem reports already sent to Microsoft or waiting to be sent.'
        }
        [pscustomobject]@{ Id = 'inet'; Kind = 'Folders'; Rec = $true; Services = $none
            Folders = @((New-OzCleanFolder "$la\Microsoft\Windows\INetCache" '\\Microsoft\\Windows\\INetCache$'))
            Name = 'Legacy web cache'; Desc = 'Cache of Internet Explorer and older apps that still use it. Edge, Chrome and Firefox keep their own.'
        }
        [pscustomobject]@{ Id = 'cbs'; Kind = 'Folders'; Rec = $true; Services = $none; Folders = @((New-OzCleanFolder "$win\Logs\CBS" '\\Logs\\CBS$'))
            Name = 'Servicing logs'; Desc = 'Logs from installing Windows updates. Only useful when an update fails.'
        }
        [pscustomobject]@{ Id = 'shaders'; Kind = 'Folders'; Rec = $false; Services = $none
            Folders = @((New-OzCleanFolder "$la\D3DSCache" '\\D3DSCache$'),
                (New-OzCleanFolder "$la\NVIDIA\DXCache" '\\NVIDIA\\DXCache$'), (New-OzCleanFolder "$la\NVIDIA\GLCache" '\\NVIDIA\\GLCache$'),
                (New-OzCleanFolder "$la\AMD\DxCache" '\\AMD\\DxCache$'), (New-OzCleanFolder "$la\AMD\GLCache" '\\AMD\\GLCache$'),
                (New-OzCleanFolder "$la\AMD\VkCache" '\\AMD\\VkCache$'), (New-OzCleanFolder "$la\Intel\ShaderCache" '\\Intel\\ShaderCache$'))
            Name = 'Graphics shader caches'; Desc = 'Shaders compiled by DirectX and the graphics driver. Games build them again, so their first launch can stutter.'
        }
    )
}

function Get-OzCleanDrive {
    # Local drives that can be picked: fixed and removable ones that are ready (not empty or locked).
    # Network drives are never offered.
    $win = Get-OzWindowsDrive
    foreach ($d in @([IO.DriveInfo]::GetDrives())) {
        try {
            if ([string]$d.DriveType -notin 'Fixed', 'Removable') { continue }
            if (-not $d.IsReady) { continue }
            $name = $d.Name.TrimEnd('\').ToUpperInvariant()
            if ($name -notmatch '^[A-Z]:$') { continue }
            [pscustomobject]@{
                Drive = $name; Label = [string]$d.VolumeLabel; IsWindows = ($name -eq $win)
                FreeGB = [math]::Round($d.AvailableFreeSpace / 1GB, 1); SizeGB = [math]::Round($d.TotalSize / 1GB, 1)
            }
        } catch { }
    }
}

function Get-OzRecycleBinPath {
    # The Recycle Bin folder of the account running the app on $Drive (what Clear-RecycleBin empties)
    param([string]$Drive)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    '{0}\$Recycle.Bin\{1}' -f $Drive, $sid
}

function Get-OzRecycleBinSize {
    # What the Recycle Bin of $Drive holds: its $R (deleted item) and $I (info) entries, not desktop.ini
    param([string]$Drive)
    Get-OzFolderSize (Get-OzRecycleBinPath $Drive) '$*'
}

function Get-OzDeliveryCacheSize {
    # Bytes in the Delivery Optimization cache as Windows reports them, or -1
    try {
        $snap = Get-DeliveryOptimizationPerfSnap -ErrorAction Stop
        foreach ($p in @($snap.PSObject.Properties)) { if ($p.Name -match '^CacheSize') { return [int64]$p.Value } }
    } catch { }
    [int64]-1
}

function Get-OzCleanScan {
    # Measures what can be cleaned on $Drives. Reads only; deletes nothing.
    param([string[]]$Drives)
    $win = Get-OzWindowsDrive
    $picked = @($Drives | Where-Object { $_ -match '^[A-Za-z]:$' } | ForEach-Object { $_.ToUpperInvariant() } | Select-Object -Unique)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($drive in $picked) {
        if ($drive -eq $win) {
            $hasDo = [bool](Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue)
            foreach ($c in @(Get-OzCleanCatalog)) {
                if ($c.Kind -eq 'DeliveryOpt' -and -not $hasDo) { continue }
                $bytes = [int64]0; $unknown = $false
                $paths = New-Object System.Collections.Generic.List[string]
                $skipped = New-Object System.Collections.Generic.List[object]
                foreach ($f in @($c.Folders)) {
                    $why = Test-OzCleanPath $f.Path $f.Tail
                    if ($why) { if ($f.Path) { $skipped.Add([pscustomobject]@{ Path = $f.Path; Why = $why }) }; continue }
                    if (-not [IO.Directory]::Exists($f.Path)) { continue }
                    $s = Get-OzFolderSize $f.Path $f.Filter
                    if ($s -lt 0) { $unknown = $true } else { $bytes += $s }
                    $paths.Add($f.Path)
                }
                if ($c.Kind -eq 'DeliveryOpt') {
                    $reported = Get-OzDeliveryCacheSize
                    if ($reported -ge 0) { $bytes = $reported; $unknown = $false }
                    elseif (-not $paths.Count) { $unknown = $true }
                } elseif (-not $paths.Count -and -not $skipped.Count) { continue }
                $item = [pscustomobject]@{
                    Key = ('{0}|{1}' -f $c.Id, $drive); Id = $c.Id; Drive = $drive; Kind = $c.Kind; Name = $c.Name; Desc = $c.Desc; Rec = [bool]$c.Rec
                    Bytes = $(if ($unknown) { [int64]-1 } else { $bytes }); Paths = $paths.ToArray(); Skipped = $skipped.ToArray()
                }
                $out.Add($item)
            }
        }
        $item = [pscustomobject]@{
            Key = ('bin|{0}' -f $drive); Id = 'bin'; Drive = $drive; Kind = 'Bin'; Name = 'Recycle Bin'
            Desc = 'Files you deleted on this drive. Check it first: after this they cannot be brought back.'; Rec = $false
            Bytes = (Get-OzRecycleBinSize $drive); Paths = [string[]]@(('{0}\$Recycle.Bin' -f $drive)); Skipped = @()
        }
        $out.Add($item)
    }
    $out.ToArray()
}

function Invoke-OzCleanRun {
    # Cleans the picked items ('id|drive' keys from Get-OzCleanScan). Every folder is rebuilt from the
    # catalog and checked again here, right before anything is deleted. Writes one log line per item.
    param([string[]]$Picks)
    $win = Get-OzWindowsDrive
    $catalog = @{}
    foreach ($c in @(Get-OzCleanCatalog)) { $catalog[$c.Id] = $c }
    $total = [int64]0
    foreach ($pick in @($Picks)) {
        $parts = ([string]$pick) -split '\|', 2
        if ($parts.Count -ne 2 -or $parts[1] -notmatch '^[A-Za-z]:$') { continue }
        $id = $parts[0]
        $drive = $parts[1].ToUpperInvariant()
        if ($id -eq 'bin') {
            if (-not @(Get-OzCleanDrive | Where-Object Drive -EQ $drive).Count) { '  ! ' + (T 'Drive {0} is not a local drive; its Recycle Bin was left alone.' $drive); continue }
            $before = Get-OzRecycleBinSize $drive
            try {
                Clear-RecycleBin -DriveLetter $drive.Substring(0, 1) -Force -ErrorAction Stop
                $freed = [math]::Max([int64]0, $before - [math]::Max([int64]0, (Get-OzRecycleBinSize $drive)))
                $total += $freed
                '  {0}: {1}' -f (T 'Recycle Bin of drive {0}' $drive), (Format-OzBytes $freed)
            } catch { '  ! ' + (T 'Recycle Bin of drive {0}' $drive) + ': ' + $_.Exception.Message }
            continue
        }
        $c = $catalog[$id]
        if (-not $c -or $drive -ne $win) { continue }
        if ($c.Kind -eq 'DeliveryOpt') {
            $before = Get-OzDeliveryCacheSize
            try {
                Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
                $freed = [int64]0
                $after = Get-OzDeliveryCacheSize
                if ($before -ge 0 -and $after -ge 0) { $freed = [math]::Max([int64]0, $before - $after) }
                $total += $freed
                '  {0}: {1}' -f (T $c.Name), $(if ($before -ge 0) { Format-OzBytes $freed } else { T 'cleared' })
            } catch { '  ! ' + (T $c.Name) + ': ' + $_.Exception.Message }
            continue
        }
        $stop = @($c.Services).Count -gt 0
        if ($stop) {
            T 'Stopping Windows Update to clear its download cache...'
            Stop-Service -Name $c.Services -Force -ErrorAction SilentlyContinue
        }
        $freed = [int64]0
        try {
            foreach ($f in @($c.Folders)) {
                $why = Test-OzCleanPath $f.Path $f.Tail
                if ($why) { if ($f.Path) { '  ' + (T '{0}: skipped ({1}): {2}' (T $c.Name) (T $why) $f.Path) }; continue }
                $freed += (Clear-OzFolder $f.Path $f.Filter)
            }
        } catch { } finally { if ($stop) { Start-Service -Name $c.Services -ErrorAction SilentlyContinue } }
        $total += $freed
        '  {0}: {1}' -f (T $c.Name), (Format-OzBytes $freed)
    }
    [pscustomobject]@{ FreedBytes = $total }
}

function Invoke-OzCleanScan {
    # SCAN button: measures the picked drives in the background and shows the list
    if ($null -eq $Oz.CleanDriveSel) { Show-OzCleanDrives }
    $drives = @($Oz.CleanDriveSel.Keys | Where-Object { $Oz.CleanDriveSel[$_] } | Sort-Object)
    if (-not $drives.Count) { Write-OzLog (T 'Pick at least one drive.') 'WARN'; return }
    $res = Invoke-OzJob -Activity (T 'Measuring what can be cleaned...') -ArgumentList @(, [string[]]$drives) -ScriptBlock {
        param($d)
        Get-OzCleanScan -Drives $d
    }
    $items = @($res | Where-Object { $_ -and $_.Key })
    $Oz.CleanShown = $true
    Show-OzCleanList $items
    $known = [int64]0
    foreach ($i in $items) { if ($i.Bytes -gt 0) { $known += $i.Bytes } }
    Write-OzLog (T 'Cleanup scan of {0}: {1} can be cleaned.' ($drives -join ', ') (Format-OzBytes $known)) 'OK'
}

function Invoke-OzCleanSelected {
    # CLEAN SELECTED button: asks first, cleans in the background, then measures again
    $sel = @($Oz.CleanChecks | Where-Object { $_.IsChecked -and $_.IsEnabled } | ForEach-Object { $_.Tag })
    if (-not $sel.Count) { Write-OzLog (T 'Select at least one item to clean.') 'WARN'; return }
    $rows = foreach ($s in $sel) {
        @{ Text = ('{0}  {1}  -  {2}' -f $s.Drive, (T $s.Name), (Format-OzBytes $s.Bytes)); Color = '#E6F1FF'; Glyph = [char]0xE74D }
    }
    $msg = T 'Delete these {0} item(s)? This cannot be undone. Files that are open right now are skipped.' $sel.Count
    if ((Show-OzDialog -Text $msg -Buttons YesNo -Kind Warning -Rows @($rows) -Labels @((T 'DELETE'), (T 'CANCEL'))) -ne 'Yes') { return }
    $picks = [string[]]@($sel | ForEach-Object { $_.Key })
    $res = Invoke-OzJob -Activity (T 'Cleaning the selected items...') -ArgumentList @(, $picks) -ScriptBlock {
        param($p)
        Invoke-OzCleanRun -Picks $p
    }
    $r = @($res) | Where-Object { $_ -and $null -ne $_.FreedBytes } | Select-Object -First 1
    if ($r) {
        $Oz.LastCleanMB = [math]::Round($r.FreedBytes / 1MB)
        Write-OzLog (T 'Cleanup finished: {0} freed.' (Format-OzBytes $r.FreedBytes)) 'OK'
    }
    Update-OzCleanText
    $Oz.CleanDrives = $null
    Show-OzCleanDrives
    Invoke-OzCleanScan
}
#endregion

#region ============================ DNS ============================
$Oz.DnsChoices = [ordered]@{
    'Automatic (router / ISP)' = @()
    'Cloudflare 1.1.1.1'       = @('1.1.1.1', '1.0.0.1')
    'Google 8.8.8.8'           = @('8.8.8.8', '8.8.4.4')
    'Quad9 (blocks malware)'   = @('9.9.9.9', '149.112.112.112')
    'AdGuard (blocks ads)'     = @('94.140.14.14', '94.140.15.15')
}

function Set-OzDns {
    param([string]$Choice)
    $servers = $Oz.DnsChoices[$Choice]
    $adapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -EQ 'Up')
    if (-not $adapters) { Write-OzLog (T 'No connected network adapter found.') 'WARN'; return }
    foreach ($a in $adapters) {
        if ($servers.Count -eq 0) { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue }
        else { Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $servers -ErrorAction SilentlyContinue }
        Write-OzLog ((T "DNS on '{0}': {1}") -f $a.Name, (T $Choice)) 'OK'
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Get-OzCurrentDns {
    $a = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -EQ 'Up' | Select-Object -First 1
    if (-not $a) { return '' }
    $s = @((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
    foreach ($k in $Oz.DnsChoices.Keys) {
        $v = @($Oz.DnsChoices[$k])
        if ($v.Count -and $s.Count -and $s[0] -eq $v[0]) { return $k }
    }
    if ($s.Count) { return ($s -join ', ') }
    return ''
}
#endregion

#region ============================ STARTUP APPS ============================
function Get-OzStartupApps {
    $items = @()
    $sources = @(
        @{ Scope = 'User'; Kind = 'Run'; Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
        @{ Scope = 'All users'; Kind = 'Run'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
        @{ Scope = 'All users (32-bit)'; Kind = 'Run'; Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
    )
    foreach ($s in $sources) {
        if (-not (Test-Path -LiteralPath $s.Path)) { continue }
        $key = Get-Item -LiteralPath $s.Path
        foreach ($n in $key.GetValueNames()) {
            if (-not $n) { continue }
            $items += [pscustomobject]@{ Name = $n; Command = [string]$key.GetValue($n); Scope = $s.Scope; Approved = $s.Approved; Enabled = (Test-OzStartupEnabled $s.Approved $n) }
        }
    }
    $folders = @(
        @{ Scope = 'User folder'; Path = [Environment]::GetFolderPath('Startup'); Approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' },
        @{ Scope = 'All users folder'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
    )
    foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path -LiteralPath $f.Path)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object Name -NE 'desktop.ini')) {
            $items += [pscustomobject]@{ Name = $file.Name; Command = $file.FullName; Scope = $f.Scope; Approved = $f.Approved; Enabled = (Test-OzStartupEnabled $f.Approved $file.Name) }
        }
    }
    return $items
}

function Test-OzStartupEnabled {
    param([string]$ApprovedKey, [string]$Name)
    $v = (Get-OzReg $ApprovedKey $Name).Value
    if ($v -is [byte[]] -and $v.Length -gt 0) { return (($v[0] -band 1) -eq 0) }
    return $true
}

function Set-OzStartupApp {
    param($Item, [bool]$Enabled)
    if ($Enabled) { $bytes = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
    else { $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())) }
    Set-OzReg $Item.Approved $Item.Name $bytes 'Binary'
    Write-OzLog ($(if ($Enabled) { T "Startup app '{0}' enabled" $Item.Name } else { T "Startup app '{0}' disabled" $Item.Name })) 'OK'
}
#endregion

#region ============================ DEBLOAT ============================
function Get-OzInstalledBloat {
    $res = Invoke-OzJob -Activity (T 'Scanning installed apps...') -ScriptBlock {
        $names = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { -not $_.NonRemovable } | ForEach-Object Name)
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | ForEach-Object DisplayName)
        [pscustomobject]@{ Installed = $names; Provisioned = $prov }
    }
    $r = @($res) | Select-Object -First 1
    $all = @($r.Installed) + @($r.Provisioned) | Select-Object -Unique
    $found = @()
    foreach ($b in $Oz.Bloat) {
        $hits = @($all | Where-Object { $_ -like $b.P })
        if ($hits.Count) { $found += [pscustomobject]@{ Pattern = $b.P; Name = $b.N; Rec = $b.R; Packages = $hits } }
    }
    return $found
}

function Remove-OzBloat {
    param([string[]]$Patterns)
    Invoke-OzJob -Activity ((T 'Removing {0} app(s)...') -f $Patterns.Count) -ArgumentList @(, $Patterns) -ScriptBlock {
        param($pats)
        foreach ($p in $pats) {
            T 'Removing {0}' $p
            $pk = @(Get-AppxPackage -AllUsers -Name $p -ErrorAction SilentlyContinue)
            foreach ($x in $pk) {
                try { Remove-AppxPackage -Package $x.PackageFullName -AllUsers -ErrorAction Stop }
                catch {
                    try { Remove-AppxPackage -Package $x.PackageFullName -ErrorAction Stop }
                    catch { '  ! ' + (T 'could not remove {0}: {1}' $x.Name $_.Exception.Message) }
                }
            }
            foreach ($pp in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $p })) {
                try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null; '  ' + (T 'de-provisioned (will not return for new users)') }
                catch { '  ! ' + (T 'could not de-provision {0}' $pp.DisplayName) }
            }
        }
        T 'Debloat finished.'
    } | Out-Null
}
#endregion

#region ============================ SETUP EXPORT / IMPORT ============================
function Export-OzSetup {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.FileName = 'ozzyhn-setup.json'
    $dlg.Filter = (T 'Ozzyhn setup') + ' (*.json)|*.json'
    if (-not $dlg.ShowDialog()) { return }
    $active = @($Oz.Rows.Values | Where-Object { $_.Applied } | ForEach-Object { $_.Tweak.Id })
    [pscustomobject]@{ App = $Oz.AppName; Brand = $Oz.Brand; Url = $Oz.ProfileUrl; Version = $Oz.Version; Created = (Get-Date).ToString('s'); Machine = $env:COMPUTERNAME; Tweaks = $active } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8
    Write-OzLog ((T 'Exported {0} active tweaks to {1}') -f $active.Count, $dlg.FileName) 'OK'
}

function Import-OzSetup {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = (T 'Ozzyhn setup') + ' (*.json)|*.json'
    if (-not $dlg.ShowDialog()) { return }
    $data = Get-Content -LiteralPath $dlg.FileName -Raw | ConvertFrom-Json
    $n = 0
    foreach ($id in @($data.Tweaks)) {
        $row = $Oz.Rows[[string]$id]
        if ($row -and $row.Applicable -and $row.Tweak.Risk -ne 'Danger' -and -not $row.Check.IsChecked) { $row.Check.IsChecked = $true; Update-OzRowState $row.Tweak.Id; $n++ }
    }
    Write-OzLog ((T 'Imported setup: {0} tweak(s) staged. Review them and press APPLY CHANGES.') -f $n) 'OK'
    Update-OzPendingBar
    Select-OzChip 'PENDING'
    $Oz.UI.NavTweaks.IsChecked = $true
}
#endregion

#region ============================ REVERT EVERYTHING ============================
function Invoke-OzRevertAll {
    $j = Read-OzJournal
    $ids = @($j.Keys)
    if (-not $ids.Count) { Write-OzLog (T 'Nothing to revert - the undo journal is empty.') 'INFO'; return }
    $ok = Show-OzDialog -Text (T "Revert all {0} change(s) made by {1}?`n`nRemoved apps are not reinstalled (get them from the Microsoft Store)." $ids.Count $Oz.AppName) -Buttons YesNo -Kind Warning
    if ($ok -ne 'Yes') { return }
    $tweaks = @()
    foreach ($id in $ids) {
        if ($Oz.TweakIndex.ContainsKey($id)) { $tweaks += $Oz.TweakIndex[$id] }
        else { $j.Remove($id) }
    }
    Save-OzJournal
    Invoke-OzChangeSet -ToRevert $tweaks
}
#endregion

#region ============================ THEMES (RAINMETER) - SKIN FILES ============================
# Rainmeter skins written by the THEMES page into Documents\Rainmeter\Skins\OZZYHN.
# In these templates {{84}} is a size in pixels at 100% scale: it is replaced by 84 x the scale the
# user picked, so every skin is sharp at any size. #Name# values are Rainmeter variables, filled from
# @Resources\Settings.inc, which the app writes. Everything stays plain ASCII; text that can hold
# accents (Spanish words, file names) lives in the .inc files, which are written as UTF-16.
$Oz.ThemeTpl = @{}

$Oz.ThemeTpl['@Resources\Clock.inc'] = @'
; Shared by every OZZYHN clock style: time, greeting and wallpaper-aware text color.
[Variables]
Ink=245,245,245
G1=
G2=

[mDay]
Measure=Time
Format=%A
FormatLocale=#Locale#

[mDayShort]
Measure=Time
Format=%a
FormatLocale=#Locale#
RegExpSubstitute=1
Substitute="\.":""

[mDate]
Measure=Time
Format=#DateFmt#
FormatLocale=#Locale#
RegExpSubstitute=1
Substitute="\.":""

[mTime]
Measure=Time
Format=#TimeFmt#
FormatLocale=#Locale#

[mHM]
Measure=Time
Format=#TimeShort#

[mAmPm]
Measure=Time
Format=%p
FormatLocale=#Locale#

[mHH]
Measure=Time
Format=#HourFmt#

[mMM]
Measure=Time
Format=%M

[mSec]
Measure=Time
Format=%S

[mSecNum]
Measure=Calc
Formula=[mSec]
DynamicVariables=1

[mHourText]
Measure=Time
Format=%H

[mHour]
Measure=Calc
Formula=[mHourText]
DynamicVariables=1
IfCondition=(mHour >= 5) && (mHour < 12)
IfTrueAction=[!SetVariable G1 "#S_G1Morning#"][!SetVariable G2 "#S_G2Morning#"][!UpdateMeterGroup Ink][!Redraw]
IfCondition2=(mHour >= 12) && (mHour < 18)
IfTrueAction2=[!SetVariable G1 "#S_G1Afternoon#"][!SetVariable G2 "#S_G2Afternoon#"][!UpdateMeterGroup Ink][!Redraw]
IfCondition3=(mHour >= 18) && (mHour < 22)
IfTrueAction3=[!SetVariable G1 "#S_G1Evening#"][!SetVariable G2 "#S_G2Evening#"][!UpdateMeterGroup Ink][!Redraw]
IfCondition4=(mHour >= 22) || (mHour < 5)
IfTrueAction4=[!SetVariable G1 "#S_G1Night#"][!SetVariable G2 "#S_G2Night#"][!UpdateMeterGroup Ink][!Redraw]

; Reads the brightness of the middle of the wallpaper (a hidden PowerShell, a fraction of a second)
; and answers which text color fits: 0 dark, 1 mid, 2 light.
[mLuma]
Measure=Plugin
Plugin=RunCommand
Parameter=powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "#@#Scripts\Luma.ps1" -Region #InkRegion# -Mode #InkMode# -Dark #InkDarkTh# -Light #InkLightTh# -Lums "#InkLums#" -Cx #InkCx# -Cy #InkCy#
State=Hide
OutputType=ANSI
Timeout=20000
RegExpSubstitute=1
Substitute="(?s)^\D*([012]).*$":"\1","(?s)^\D*$":"#InkSlot#"
DynamicVariables=1
FinishAction=[!SetVariable InkSlot "[mLuma]"][!WriteKeyValue Variables InkSlot "[mLuma]" "#@#State.inc"][!UpdateMeasure mInk][!UpdateMeterGroup Ink][!Redraw]

; A new wallpaper picked in Settings changes this value
[mWallReg]
Measure=Registry
RegHKey=HKEY_CURRENT_USER
RegKey=Control Panel\Desktop
RegValue=WallPaper
UpdateDivider=2
Disabled=#NoAutoInk#
OnChangeAction=[!CommandMeasure mLuma "Run"]

; Every 10 minutes, for slideshows and Spotlight
[mInkTick]
Measure=Calc
Formula=Counter % 600
Disabled=#NoAutoInk#
IfCondition=mInkTick = 599
IfTrueAction=[!CommandMeasure mLuma "Run"]

[mInk]
Measure=Calc
Formula=(#AutoInk# = 1 ? #InkSlot# : #InkFixed#)
DynamicVariables=1
IfCondition=mInk = 0
IfTrueAction=[!SetVariable Ink "#InkDark#"][!UpdateMeterGroup Ink][!Redraw]
IfCondition2=mInk = 1
IfTrueAction2=[!SetVariable Ink "#InkMid#"][!UpdateMeterGroup Ink][!Redraw]
IfCondition3=mInk = 2
IfTrueAction3=[!SetVariable Ink "#InkLight#"][!UpdateMeterGroup Ink][!Redraw]

[sInk]
FontColor=#Ink#
FontFace=#FontDisplay#
AntiAlias=1
DynamicVariables=1
Group=Ink
StringAlign=#Align#
X=#AX#
'@

$Oz.ThemeTpl['Clock\Horizon.ini'] = @'
; OZZYHN clock - HORIZON: the day spelled wide, date and time underneath
[Rainmeter]
Update=1000
AccurateText=1
Group=OzAll | OzClock
OnRefreshAction=[!SetWindowPosition "#PosX#" "#PosY#" "#AnchorX#" "#AnchorY#"][!ZPos -2][!Draggable 0][!CommandMeasure mLuma "Run"]
ContextTitle=#S_RefreshColors#
ContextAction=[!CommandMeasure mLuma "Run"]
ContextTitle2=#S_NextStyle#
ContextAction2=[!ActivateConfig "#CURRENTCONFIG#" "Blade.ini"]
ContextTitle3=#S_Wallpapers#
ContextAction3=[!ToggleConfig "OZZYHN\Walls" "Walls.ini"]

[Metadata]
Name=OZZYHN Clock - Horizon
Author=OZZYHN TWEAKS
Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page.
Version=1.0
License=MIT

[Variables]
@Include=#@#Settings.inc
@Include2=#@#Strings.inc
@Include3=#@#State.inc
@Include4=#@#Clock.inc
W={{900}}
H={{230}}
Pad={{4}}
AX=(#Pad#+(#W#-2*#Pad#)*#AlignK#)

[mBox]
Meter=Image
W=#W#
H=#H#
SolidColor=0,0,0,0

[tDay]
Meter=String
MeterStyle=sInk
MeasureName=mDay
Y={{0}}
FontSize={{80}}
FontWeight=300
StringCase=Upper
InlineSetting=CharacterSpacing | {{16}} | 0

[tDate]
Meter=String
MeterStyle=sInk
MeasureName=mDate
Y={{2}}R
FontSize={{16}}
FontWeight=400
StringCase=Upper
InlineSetting=CharacterSpacing | {{6}} | 0

[tTime]
Meter=String
MeterStyle=sInk
MeasureName=mTime
Text=-  %1  -
Y={{8}}R
FontSize={{16}}
FontWeight=400
StringCase=Upper
InlineSetting=CharacterSpacing | {{5}} | 0
'@

$Oz.ThemeTpl['Clock\Blade.ini'] = @'
; OZZYHN clock - BLADE: a greeting and the short day between two lines
[Rainmeter]
Update=1000
AccurateText=1
Group=OzAll | OzClock
OnRefreshAction=[!SetWindowPosition "#PosX#" "#PosY#" "#AnchorX#" "#AnchorY#"][!ZPos -2][!Draggable 0][!CommandMeasure mLuma "Run"]
ContextTitle=#S_RefreshColors#
ContextAction=[!CommandMeasure mLuma "Run"]
ContextTitle2=#S_NextStyle#
ContextAction2=[!ActivateConfig "#CURRENTCONFIG#" "Stack.ini"]
ContextTitle3=#S_Wallpapers#
ContextAction3=[!ToggleConfig "OZZYHN\Walls" "Walls.ini"]

[Metadata]
Name=OZZYHN Clock - Blade
Author=OZZYHN TWEAKS
Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page.
Version=1.0
License=MIT

[Variables]
@Include=#@#Settings.inc
@Include2=#@#Strings.inc
@Include3=#@#State.inc
@Include4=#@#Clock.inc
W={{380}}
H={{500}}
Pad={{6}}
AX=(#Pad#+(#W#-2*#Pad#)*#AlignK#)

[mBox]
Meter=Image
W=#W#
H=#H#
SolidColor=0,0,0,0

[lTop]
Meter=Shape
Shape=Line #AX#,0,#AX#,{{78}} | StrokeWidth {{2}} | Stroke Color #Ink#,210
DynamicVariables=1
Group=Ink
Y={{4}}

[tG1]
Meter=String
MeterStyle=sInk
Text=#G1#
Y={{110}}
FontSize={{12}}
FontWeight=700
InlineSetting=CharacterSpacing | {{4}} | 0

[tG2]
Meter=String
MeterStyle=sInk
Text=#G2#
Y={{6}}R
FontSize={{12}}
FontWeight=700
InlineSetting=CharacterSpacing | {{4}} | 0

[tDay]
Meter=String
MeterStyle=sInk
MeasureName=mDayShort
Y={{2}}R
FontSize={{74}}
FontWeight=600
StringCase=Upper
InlineSetting=CharacterSpacing | {{6}} | 0

[tDate]
Meter=String
MeterStyle=sInk
MeasureName=mDate
Y={{0}}R
FontSize={{12}}
FontWeight=700
StringCase=Upper
InlineSetting=CharacterSpacing | {{3}} | 0

[tTime]
Meter=String
MeterStyle=sInk
MeasureName=mTime
Y={{6}}R
FontSize={{12}}
FontWeight=700
StringCase=Upper
InlineSetting=CharacterSpacing | {{3}} | 0

[lBottom]
Meter=Shape
Shape=Line #AX#,0,#AX#,{{78}} | StrokeWidth {{2}} | Stroke Color #Ink#,210
DynamicVariables=1
Group=Ink
X=0
Y={{28}}R
'@

$Oz.ThemeTpl['Clock\Stack.ini'] = @'
; OZZYHN clock - STACK: hours over minutes, day and date below
[Rainmeter]
Update=1000
AccurateText=1
Group=OzAll | OzClock
OnRefreshAction=[!SetWindowPosition "#PosX#" "#PosY#" "#AnchorX#" "#AnchorY#"][!ZPos -2][!Draggable 0][!CommandMeasure mLuma "Run"]
ContextTitle=#S_RefreshColors#
ContextAction=[!CommandMeasure mLuma "Run"]
ContextTitle2=#S_NextStyle#
ContextAction2=[!ActivateConfig "#CURRENTCONFIG#" "Pulse.ini"]
ContextTitle3=#S_Wallpapers#
ContextAction3=[!ToggleConfig "OZZYHN\Walls" "Walls.ini"]

[Metadata]
Name=OZZYHN Clock - Stack
Author=OZZYHN TWEAKS
Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page.
Version=1.0
License=MIT

[Variables]
@Include=#@#Settings.inc
@Include2=#@#Strings.inc
@Include3=#@#State.inc
@Include4=#@#Clock.inc
W={{520}}
H={{400}}
Pad={{4}}
AX=(#Pad#+(#W#-2*#Pad#)*#AlignK#)

[mBox]
Meter=Image
W=#W#
H=#H#
SolidColor=0,0,0,0

[tHH]
Meter=String
MeterStyle=sInk
MeasureName=mHH
Y={{-14}}
FontSize={{120}}
FontWeight=300

[tMM]
Meter=String
MeterStyle=sInk
MeasureName=mMM
FontColor=#Ink#,150
Y={{-62}}R
FontSize={{120}}
FontWeight=300

[tInfo]
Meter=String
MeterStyle=sInk
MeasureName=mDay
MeasureName2=mDate
Text=%1  [\x00B7]  %2
Y={{-14}}R
FontSize={{13}}
FontWeight=600
StringCase=Upper
InlineSetting=CharacterSpacing | {{5}} | 0
'@

$Oz.ThemeTpl['Clock\Pulse.ini'] = @'
; OZZYHN clock - PULSE: neon time with a seconds line (uses the theme accent colors)
[Rainmeter]
Update=1000
AccurateText=1
Group=OzAll | OzClock
OnRefreshAction=[!SetWindowPosition "#PosX#" "#PosY#" "#AnchorX#" "#AnchorY#"][!ZPos -2][!Draggable 0][!CommandMeasure mLuma "Run"]
ContextTitle=#S_RefreshColors#
ContextAction=[!CommandMeasure mLuma "Run"]
ContextTitle2=#S_NextStyle#
ContextAction2=[!ActivateConfig "#CURRENTCONFIG#" "Minimal.ini"]
ContextTitle3=#S_Wallpapers#
ContextAction3=[!ToggleConfig "OZZYHN\Walls" "Walls.ini"]

[Metadata]
Name=OZZYHN Clock - Pulse
Author=OZZYHN TWEAKS
Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page.
Version=1.0
License=MIT

[Variables]
@Include=#@#Settings.inc
@Include2=#@#Strings.inc
@Include3=#@#State.inc
@Include4=#@#Clock.inc
W={{760}}
H={{230}}
Pad={{6}}
AX=(#Pad#+(#W#-2*#Pad#)*#AlignK#)

[mBox]
Meter=Image
W=#W#
H=#H#
SolidColor=0,0,0,0

[tTime]
Meter=String
MeasureName=mHM
X=#AX#
Y={{-10}}
StringAlign=#Align#
FontFace=#FontDisplay#
FontSize={{92}}
FontWeight=600
FontColor=255,255,255
AntiAlias=1
StringCase=Upper
InlineSetting=GradientColor | 180 | #Accent#,255 ; 0.0 | #Accent2#,255 ; 1.0
InlineSetting2=Shadow | 0 | 0 | {{14}} | #Accent#,110

[lTrack]
Meter=Shape
Shape=Rectangle #Pad#,0,(#W#-2*#Pad#),{{3}},{{1.5}} | Fill Color #Ink#,45 | StrokeWidth 0
DynamicVariables=1
Group=Ink
X=0
Y=([tTime:Y]+[tTime:H]+{{2}})

[lSeconds]
Meter=Shape
Shape=Rectangle #Pad#,0,(Max((#W#-2*#Pad#)*[mSecNum]/59,{{3}})),{{3}},{{1.5}} | Fill LinearGradient gPulse | StrokeWidth 0
gPulse=0 | #Accent#,255 ; 0.0 | #Accent2#,255 ; 1.0
DynamicVariables=1
X=0
Y=([tTime:Y]+[tTime:H]+{{2}})

[tInfo]
Meter=String
MeterStyle=sInk
MeasureName=mDay
MeasureName2=mDate
MeasureName3=mAmPm
Text=#PulseInfo#
Y=([tTime:Y]+[tTime:H]+{{18}})
FontSize={{14}}
FontWeight=600
StringCase=Upper
InlineSetting=CharacterSpacing | {{5}} | 0
'@

$Oz.ThemeTpl['Clock\Minimal.ini'] = @'
; OZZYHN clock - MINIMAL: one quiet line
[Rainmeter]
Update=1000
AccurateText=1
Group=OzAll | OzClock
OnRefreshAction=[!SetWindowPosition "#PosX#" "#PosY#" "#AnchorX#" "#AnchorY#"][!ZPos -2][!Draggable 0][!CommandMeasure mLuma "Run"]
ContextTitle=#S_RefreshColors#
ContextAction=[!CommandMeasure mLuma "Run"]
ContextTitle2=#S_NextStyle#
ContextAction2=[!ActivateConfig "#CURRENTCONFIG#" "Horizon.ini"]
ContextTitle3=#S_Wallpapers#
ContextAction3=[!ToggleConfig "OZZYHN\Walls" "Walls.ini"]

[Metadata]
Name=OZZYHN Clock - Minimal
Author=OZZYHN TWEAKS
Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page.
Version=1.0
License=MIT

[Variables]
@Include=#@#Settings.inc
@Include2=#@#Strings.inc
@Include3=#@#State.inc
@Include4=#@#Clock.inc
W={{760}}
H={{40}}
Pad={{4}}
AX=(#Pad#+(#W#-2*#Pad#)*#AlignK#)

[mBox]
Meter=Image
W=#W#
H=#H#
SolidColor=0,0,0,0

[tLine]
Meter=String
MeterStyle=sInk
MeasureName=mDay
MeasureName2=mDate
MeasureName3=mTime
Text=%1   [\x00B7]   %2   [\x00B7]   %3
Y={{6}}
FontSize={{15}}
FontWeight=600
StringCase=Upper
InlineSetting=CharacterSpacing | {{4}} | 0
'@

$Oz.ThemeTpl['Bar\Bar.ini'] = @'
; OZZYHN status bar: wallpapers button, date and time, CPU, RAM, network, volume, battery, settings
[Rainmeter]
Update=1000
AccurateText=1
Group=OzAll
OnRefreshAction=[!SetWindowPosition "50%" "#BarY#" "50%" "0%"][!ZPos #BarZ#][!Draggable 0][!KeepOnScreen 1]
ContextTitle=#S_Wallpapers#
ContextAction=[!ToggleConfig "OZZYHN\Walls" "Walls.ini"]

[Metadata]
Name=OZZYHN Status bar
Author=OZZYHN TWEAKS
Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page.
Version=1.0
License=MIT

[Variables]
@Include=#@#Settings.inc
@Include2=#@#Strings.inc
BW=(#SCREENAREAWIDTH#-2*#BarX#)
PH={{28}}
PR={{14}}
Gap={{6}}
WLeft={{96}}
WMid={{230}}
WCpu={{86}}
WRam={{112}}
WNet={{128}}
WVol={{70}}
WBat={{74}}
WSet={{34}}
XSet=(#BW#-#WSet#)
XBat=(#XSet#-(#Gap#+#WBat#)*#HasBattery#)
XVol=(#XBat#-#Gap#-#WVol#)
XNet=(#XVol#-#Gap#-#WNet#)
XRam=(#XNet#-#Gap#-#WRam#)
XCpu=(#XRam#-#Gap#-#WCpu#)
XMid=((#BW#-#WMid#)/2)
TY=(#PH#/2)
ActWalls=[!ToggleConfig "OZZYHN\Walls" "Walls.ini"]
ActSettings=["ms-settings:"]
ActTaskMgr=["taskmgr.exe"]
ActVolMute=[!CommandMeasure mVol "ToggleMute"]
ActVolUp=[!CommandMeasure mVol "ChangeVolume 2"]
ActVolDown=[!CommandMeasure mVol "ChangeVolume -2"]

; ---------------- measures ----------------
[mClock]
Measure=Time
Format=#BarTimeFmt#
FormatLocale=#Locale#
RegExpSubstitute=1
Substitute="\.":""

[mCpu]
Measure=CPU

[mRamUsed]
Measure=PhysicalMemory
UpdateDivider=2

[mRamGB]
Measure=Calc
Formula=mRamUsed / 1073741824
UpdateDivider=2

[mNetIn]
Measure=NetIn

[mVol]
Measure=Plugin
Plugin=Win7AudioPlugin

; Volume as a number only (-1 = muted or no sound device)
[mVolNum]
Measure=Calc
Formula=mVol
IfCondition=mVolNum < 0
IfTrueAction=[!SetOption tVolIcon Text "[\xE74F]"][!SetOption tVol Text "#S_Mute#"][!UpdateMeter tVolIcon][!UpdateMeter tVol]
IfFalseAction=[!SetOption tVolIcon Text "[\xE767]"][!SetOption tVol Text "%1%"][!UpdateMeter tVolIcon][!UpdateMeter tVol]

[mBat]
Measure=Plugin
Plugin=PowerPlugin
PowerState=Percent
Disabled=#NoBattery#

; ---------------- pill style ----------------
[sPillText]
FontFace=#FontBody#
FontSize={{9.5}}
FontWeight=600
FontColor=#TextMain#
AntiAlias=1
StringAlign=CenterCenter
Y=#TY#
[sPillLabel]
FontFace=#FontBody#
FontSize={{8}}
FontWeight=700
FontColor=#TextSub#
AntiAlias=1
StringAlign=LeftCenter
Y=#TY#
InlineSetting=CharacterSpacing | {{1.5}} | 0
[sPillIcon]
FontFace=#FontIcons#
FontSize={{10}}
FontColor=#TextSub#
AntiAlias=1
StringAlign=LeftCenter
Y=#TY#

; ---------------- size of the bar ----------------
[mBox]
Meter=Image
W=#BW#
H=#PH#
SolidColor=0,0,0,0

; ---------------- left: wallpapers ----------------
[pLeft]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WLeft#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
LeftMouseUpAction=#ActWalls#
ToolTipText=#S_Wallpapers#
MouseActionCursor=1
X=0
[tLeftMark]
Meter=String
Text=OZ
FontFace=#FontDisplay#
FontSize={{11}}
FontWeight=700
FontColor=#Accent#
AntiAlias=1
StringAlign=LeftCenter
X={{14}}
Y=#TY#
LeftMouseUpAction=#ActWalls#
[tLeftIcon]
Meter=String
MeterStyle=sPillIcon
Text=[\xE8B9]
FontColor=#TextMain#
X={{8}}R
LeftMouseUpAction=#ActWalls#

; ---------------- middle: date and time ----------------
[pMid]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WMid#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
X=#XMid#
Y=0
[tMid]
Meter=String
MeterStyle=sPillText
MeasureName=mClock
X=(#XMid#+#WMid#/2)
StringCase=Upper
InlineSetting=CharacterSpacing | {{1}} | 0

; ---------------- right ----------------
[pCpu]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WCpu#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
X=#XCpu#
Y=0
LeftMouseUpAction=#ActTaskMgr#
MouseActionCursor=1
[tCpuL]
Meter=String
MeterStyle=sPillLabel
Text=CPU
X=(#XCpu#+{{12}})
LeftMouseUpAction=#ActTaskMgr#
[tCpu]
Meter=String
MeterStyle=sPillText
MeasureName=mCpu
Text=%1%
NumOfDecimals=0
StringAlign=RightCenter
X=(#XCpu#+#WCpu#-{{12}})
LeftMouseUpAction=#ActTaskMgr#

[pRam]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WRam#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
X=#XRam#
Y=0
LeftMouseUpAction=#ActTaskMgr#
MouseActionCursor=1
[tRamL]
Meter=String
MeterStyle=sPillLabel
Text=RAM
X=(#XRam#+{{12}})
LeftMouseUpAction=#ActTaskMgr#
[tRam]
Meter=String
MeterStyle=sPillText
MeasureName=mRamGB
Text=%1 GB
NumOfDecimals=1
StringAlign=RightCenter
X=(#XRam#+#WRam#-{{12}})
LeftMouseUpAction=#ActTaskMgr#

[pNet]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WNet#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
X=#XNet#
Y=0
[tNetIcon]
Meter=String
MeterStyle=sPillIcon
Text=[\xE896]
X=(#XNet#+{{11}})
[tNet]
Meter=String
MeterStyle=sPillText
MeasureName=mNetIn
Text=%1B/s
AutoScale=1
NumOfDecimals=1
StringAlign=RightCenter
X=(#XNet#+#WNet#-{{12}})

[pVol]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WVol#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
X=#XVol#
Y=0
LeftMouseUpAction=#ActVolMute#
MouseScrollUpAction=#ActVolUp#
MouseScrollDownAction=#ActVolDown#
MouseActionCursor=1
[tVolIcon]
Meter=String
MeterStyle=sPillIcon
Text=[\xE767]
X=(#XVol#+{{11}})
LeftMouseUpAction=#ActVolMute#
MouseScrollUpAction=#ActVolUp#
MouseScrollDownAction=#ActVolDown#
[tVol]
Meter=String
MeterStyle=sPillText
MeasureName=mVolNum
Text=%1%
NumOfDecimals=0
StringAlign=RightCenter
X=(#XVol#+#WVol#-{{12}})
LeftMouseUpAction=#ActVolMute#
MouseScrollUpAction=#ActVolUp#
MouseScrollDownAction=#ActVolDown#

[pBat]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WBat#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
X=#XBat#
Y=0
Hidden=#NoBattery#
[tBatIcon]
Meter=String
MeterStyle=sPillIcon
Text=[\xE83F]
X=(#XBat#+{{11}})
Hidden=#NoBattery#
[tBat]
Meter=String
MeterStyle=sPillText
MeasureName=mBat
Text=%1%
NumOfDecimals=0
StringAlign=RightCenter
X=(#XBat#+#WBat#-{{12}})
Hidden=#NoBattery#

[pSet]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#WSet#-1),(#PH#-1),#PR# | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1
X=#XSet#
Y=0
LeftMouseUpAction=#ActSettings#
ToolTipText=#S_Settings#
MouseActionCursor=1
[tSet]
Meter=String
MeterStyle=sPillIcon
Text=[\xE713]
FontColor=#TextMain#
StringAlign=CenterCenter
X=(#XSet#+#WSet#/2)
LeftMouseUpAction=#ActSettings#
'@

$Oz.ThemeTpl['Walls\Walls.ini'] = @'
; OZZYHN wallpaper picker: slanted cards, color filters, scroll or click to browse, click the middle card to use it
[Rainmeter]
Update=-1
AccurateText=1
Group=OzAll
OnRefreshAction=[!SetWindowPosition "50%" "#WallsY#" "50%" "0%"][!ZPos 1][!Draggable 0][!KeepOnScreen 1][!CommandMeasure mWalls "Render()"]
ContextTitle=#S_Rescan#
ContextAction=[!CommandMeasure mWalls "StartIndex()"]
ContextTitle2=#S_OpenFolder#
ContextAction2=["#WallFolderMain#"]

[Metadata]
Name=OZZYHN Wallpapers
Author=OZZYHN TWEAKS
Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page.
Version=1.0
License=MIT

[Variables]
@Include=#@#Settings.inc
@Include2=#@#Strings.inc
@Include3=#@#Walls\Index.inc
W={{1120}}
H={{340}}
Slot1=0
Slot2=0
Slot3=0
Slot4=0
Slot5=0
Filter=A
Count=

[mWalls]
Measure=Script
ScriptFile=#@#Scripts\Walls.lua

; The app asks for a fresh list after APPLY THEME (NeedIndex=1 in Index.inc)
[mNeed]
Measure=Calc
Formula=#NeedIndex#
IfCondition=mNeed = 1
IfTrueAction=[!CommandMeasure mWalls "StartIndex()"]

; Rebuilds the list and thumbnails after you add pictures to the folder
[mIndex]
Measure=Plugin
Plugin=RunCommand
Parameter=powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "#@#Scripts\WallIndex.ps1" -Out "#@#Walls"
State=Hide
OutputType=ANSI
Timeout=180000
FinishAction=[!UpdateMeasure mIndex][!CommandMeasure mWalls "AfterIndex()"]

[sCard]
PreserveAspectRatio=2
DynamicVariables=1
Group=Cards
MouseActionCursor=1
AntiAlias=1

; ---------------- panel ----------------
[mBox]
Meter=Image
W=#W#
H=#H#
SolidColor=0,0,0,0

[pPanel]
Meter=Shape
Shape=Rectangle 0.5,0.5,(#W#-1),(#H#-1),{{22}} | Fill Color #PanelBg# | Stroke Color #PillLine# | StrokeWidth 1
MouseScrollUpAction=[!CommandMeasure mWalls "Move(-1)"]
MouseScrollDownAction=[!CommandMeasure mWalls "Move(1)"]

; ---------------- filters ----------------
[dAll]
Meter=Shape
Shape=Ellipse {{9}},{{9}},{{7}} | Fill Color 0,0,0,0 | Stroke Color #TextMain# | StrokeWidth {{1.5}}
Shape2=Ellipse {{9}},{{9}},{{3}} | Fill Color #TextMain# | StrokeWidth 0
X=((#W#-{{128}})/2)
Y={{18}}
LeftMouseUpAction=[!CommandMeasure mWalls "SetFilter('A')"]
ToolTipText=#S_FilterAll#
MouseActionCursor=1
[dLight]
Meter=Shape
Shape=Ellipse {{9}},{{9}},{{7}} | Fill Color 236,236,236 | Stroke Color 255,255,255,90 | StrokeWidth 1
X=((#W#-{{128}})/2+{{28}})
Y={{18}}
LeftMouseUpAction=[!CommandMeasure mWalls "SetFilter('L')"]
ToolTipText=#S_FilterLight#
MouseActionCursor=1
[dDark]
Meter=Shape
Shape=Ellipse {{9}},{{9}},{{7}} | Fill Color 16,16,18 | Stroke Color 255,255,255,110 | StrokeWidth 1
X=((#W#-{{128}})/2+{{56}})
Y={{18}}
LeftMouseUpAction=[!CommandMeasure mWalls "SetFilter('D')"]
ToolTipText=#S_FilterDark#
MouseActionCursor=1
[dWarm]
Meter=Shape
Shape=Ellipse {{9}},{{9}},{{7}} | Fill Color 232,48,60 | Stroke Color 255,255,255,60 | StrokeWidth 1
X=((#W#-{{128}})/2+{{84}})
Y={{18}}
LeftMouseUpAction=[!CommandMeasure mWalls "SetFilter('W')"]
ToolTipText=#S_FilterWarm#
MouseActionCursor=1
[dCool]
Meter=Shape
Shape=Ellipse {{9}},{{9}},{{7}} | Fill Color 0,200,230 | Stroke Color 255,255,255,60 | StrokeWidth 1
X=((#W#-{{128}})/2+{{112}})
Y={{18}}
LeftMouseUpAction=[!CommandMeasure mWalls "SetFilter('C')"]
ToolTipText=#S_FilterCool#
MouseActionCursor=1
[dRing]
Meter=Shape
Shape=Ellipse {{12}},{{12}},{{10.5}} | Fill Color 0,0,0,0 | Stroke Color #Accent# | StrokeWidth {{1.5}}
X=((#W#-{{128}})/2-{{3}})
Y={{15}}
DynamicVariables=1

[bFolder]
Meter=String
Text=[\xE8B7]
FontFace=#FontIcons#
FontSize={{11}}
FontColor=#TextSub#
AntiAlias=1
X={{22}}
Y={{17}}
LeftMouseUpAction=["#WallFolderMain#"]
ToolTipText=#S_OpenFolder#
MouseActionCursor=1
[bRescan]
Meter=String
Text=[\xE72C]
FontFace=#FontIcons#
FontSize={{11}}
FontColor=#TextSub#
AntiAlias=1
X={{16}}R
Y={{17}}
LeftMouseUpAction=[!CommandMeasure mWalls "StartIndex()"]
ToolTipText=#S_Rescan#
MouseActionCursor=1
[bClose]
Meter=String
Text=[\xE711]
FontFace=#FontIcons#
FontSize={{10}}
FontColor=#TextSub#
AntiAlias=1
StringAlign=Right
X=(#W#-{{22}})
Y={{18}}
LeftMouseUpAction=[!DeactivateConfig]
ToolTipText=#S_Close#
MouseActionCursor=1

; ---------------- cards (the script moves and fills them) ----------------
[c1]
Meter=Image
MeterStyle=sCard
ImageName=[#Thumb[#Slot1]]
X={{70}}
Y={{110}}
W={{150}}
H={{96}}
ImageAlpha=110
TransformationMatrix=1;0;-0.18;1;{{28}};0
LeftMouseUpAction=[!CommandMeasure mWalls "Move(-2)"]
[c5]
Meter=Image
MeterStyle=sCard
ImageName=[#Thumb[#Slot5]]
X={{900}}
Y={{110}}
W={{150}}
H={{96}}
ImageAlpha=110
TransformationMatrix=1;0;-0.18;1;{{28}};0
LeftMouseUpAction=[!CommandMeasure mWalls "Move(2)"]
[c2]
Meter=Image
MeterStyle=sCard
ImageName=[#Thumb[#Slot2]]
X={{200}}
Y={{88}}
W={{230}}
H={{140}}
ImageAlpha=190
TransformationMatrix=1;0;-0.18;1;{{28}};0
LeftMouseUpAction=[!CommandMeasure mWalls "Move(-1)"]
[c4]
Meter=Image
MeterStyle=sCard
ImageName=[#Thumb[#Slot4]]
X={{690}}
Y={{88}}
W={{230}}
H={{140}}
ImageAlpha=190
TransformationMatrix=1;0;-0.18;1;{{28}};0
LeftMouseUpAction=[!CommandMeasure mWalls "Move(1)"]
[c3]
Meter=Image
MeterStyle=sCard
ImageName=[#Thumb[#Slot3]]
X={{390}}
Y={{60}}
W={{340}}
H={{210}}
TransformationMatrix=1;0;-0.18;1;{{30}};0
LeftMouseUpAction=[!SetWallpaper "[#Wall[#Slot3]]" "#WallFit#"][!RefreshGroup OzClock]
ToolTipText=#S_UseWallpaper#
MouseScrollUpAction=[!CommandMeasure mWalls "Move(-1)"]
MouseScrollDownAction=[!CommandMeasure mWalls "Move(1)"]

[cGlow]
Meter=Shape
Shape=Path pGlow | Fill Color 0,0,0,0 | Stroke Color #Accent#,230 | StrokeWidth {{2}}
pGlow={{409}},{{60}} | LineTo {{749}},{{60}} | LineTo {{711}},{{270}} | LineTo {{371}},{{270}} | ClosePath 1
Hidden=1
Group=Cards
DynamicVariables=1
; ---------------- captions ----------------
[tName]
Meter=String
Text=[#Name[#Slot3]]
FontFace=#FontBody#
FontSize={{10}}
FontWeight=600
FontColor=#TextMain#
AntiAlias=1
StringAlign=Center
ClipString=1
W={{520}}
X=(#W#/2)
Y={{282}}
DynamicVariables=1
Group=Cards
[tEmpty]
Meter=String
Text=#S_NoWalls#
FontFace=#FontBody#
FontSize={{10}}
FontColor=#TextSub#
AntiAlias=1
StringAlign=CenterCenter
W={{700}}
ClipString=2
X=(#W#/2)
Y={{165}}
Hidden=1
[tScan]
Meter=String
Text=#S_Scanning#
FontFace=#FontBody#
FontSize={{10}}
FontColor=#TextSub#
AntiAlias=1
StringAlign=CenterCenter
W={{700}}
ClipString=2
X=(#W#/2)
Y={{165}}
Hidden=1
[tFail]
Meter=String
Text=#S_IndexFailed#
FontFace=#FontBody#
FontSize={{10}}
FontColor=#TextSub#
AntiAlias=1
StringAlign=CenterCenter
W={{700}}
ClipString=2
X=(#W#/2)
Y={{165}}
Hidden=1
[tCount]
Meter=String
Text=#Count#
FontFace=#FontBody#
FontSize={{8.5}}
FontColor=#TextSub#
AntiAlias=1
StringAlign=Center
X=(#W#/2)
Y={{306}}
DynamicVariables=1
Group=Cards
'@

$Oz.ThemeTpl['@Resources\Scripts\Walls.lua'] = @'
-- OZZYHN wallpaper picker. Keeps a list of wallpaper numbers for the chosen color filter and puts
-- five of them on the cards. Only numbers pass through here: file names stay in Index.inc, so names
-- with accents or other alphabets work.
local count, tags, list, pos, filter, scanning = 0, {}, {}, 1, 'A', false
local dots = { A = 'dAll', L = 'dLight', D = 'dDark', W = 'dWarm', C = 'dCool' }

local function build()
  list = {}
  for i = 1, count do
    if filter == 'A' or string.find(tags[i], filter, 1, true) then list[#list + 1] = i end
  end
  if pos > #list then pos = 1 end
end

function Render()
  local n = #list
  for s = -2, 2 do
    local meter = 'c' .. (s + 3)
    local idx = 0
    if n > 0 then
      if n >= 5 then
        idx = list[((pos - 1 + s) % n) + 1]
      elseif pos + s >= 1 and pos + s <= n then
        idx = list[pos + s]
      end
    end
    SKIN:Bang('!SetVariable', 'Slot' .. (s + 3), tostring(idx))
    if idx > 0 then SKIN:Bang('!ShowMeter', meter) else SKIN:Bang('!HideMeter', meter) end
  end
  if n > 0 then
    SKIN:Bang('!ShowMeter', 'cGlow')
    SKIN:Bang('!HideMeter', 'tEmpty')
    SKIN:Bang('!SetVariable', 'Count', pos .. ' / ' .. n)
  else
    SKIN:Bang('!HideMeter', 'cGlow')
    if not scanning then SKIN:Bang('!ShowMeter', 'tEmpty') end
    SKIN:Bang('!SetVariable', 'Count', '')
  end
  local dot = SKIN:GetMeter(dots[filter])
  if dot then
    SKIN:Bang('!SetOption', 'dRing', 'X', tostring(dot:GetX() - 3 * tonumber(SKIN:GetVariable('S', '1'))))
  end
  SKIN:Bang('!UpdateMeterGroup', 'Cards')
  SKIN:Bang('!UpdateMeter', 'dRing')
  SKIN:Bang('!Redraw')
end

function Initialize()
  count = tonumber(SKIN:GetVariable('WallCount', '0')) or 0
  for i = 1, count do tags[i] = SKIN:GetVariable('Tag' .. i, '') end
  build()
end

function Update()
  return #list
end

function StartIndex()
  scanning = true
  SKIN:Bang('!HideMeter', 'tEmpty')
  SKIN:Bang('!HideMeter', 'tFail')
  SKIN:Bang('!ShowMeter', 'tScan')
  SKIN:Bang('!Redraw')
  SKIN:Bang('!CommandMeasure', 'mIndex', 'Run')
end

-- The list script prints how many pictures it found. Nothing printed means it could not run
-- (PowerShell blocked, for example): then the picker says so instead of trying again forever.
function AfterIndex()
  local m = SKIN:GetMeasure('mIndex')
  local out = ''
  if m then out = m:GetStringValue() or '' end
  if string.find(out, '%d') then
    SKIN:Bang('!Refresh')
  else
    scanning = false
    SKIN:Bang('!HideMeter', 'tScan')
    SKIN:Bang('!HideMeter', 'tEmpty')
    SKIN:Bang('!ShowMeter', 'tFail')
    SKIN:Bang('!Redraw')
  end
end

function Move(d)
  local n = #list
  if n == 0 then return end
  pos = ((pos - 1 + d) % n) + 1
  Render()
end

function SetFilter(f)
  if not dots[f] then return end
  filter = f
  pos = 1
  build()
  Render()
end
'@

# Scripts the skins run themselves (as you, never as administrator). Written as they are, no sizes inside.
$Oz.ThemeScripts = @{}

$Oz.ThemeScripts['@Resources\Scripts\Luma.ps1'] = @'
# OZZYHN theme (Optimizaciones de Ozzyhn): how bright is the wallpaper where the clock sits?
# Prints "<color> <brightness>": color 0 = use the dark text, 1 = mid, 2 = light. Reads only.
param([int]$Region = 20, [string]$Mode = 'contrast', [double]$Dark = 0.2, [double]$Light = 0.8,
    [string]$Lums = '0.006,0.066,0.913', [double]$Cx = 0.5, [double]$Cy = 0.5)
$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture
function Get-Lin([double]$c) { $c = $c / 255; if ($c -le 0.04045) { $c / 12.92 } else { [math]::Pow(($c + 0.055) / 1.055, 2.4) } }
try {
    $sumY = 0.0; $sumB = 0.0; $n = 0
    $wp = [string](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).WallPaper
    $file = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
    if (-not $wp) { $file = '' } elseif (-not [IO.File]::Exists($file)) { $file = $wp }
    if ($file -and [IO.File]::Exists($file)) {
        Add-Type -AssemblyName System.Drawing
        $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
        try {
            $img = [System.Drawing.Image]::FromStream($fs, $false, $false)
            $Region = [math]::Max(5, [math]::Min(100, $Region))
            $rw = [math]::Max(1, [int]($img.Width * $Region / 100)); $rh = [math]::Max(1, [int]($img.Height * $Region / 100))
            $x0 = [int][math]::Min([math]::Max(0, $img.Width * $Cx - $rw / 2), $img.Width - $rw)
            $y0 = [int][math]::Min([math]::Max(0, $img.Height * $Cy - $rh / 2), $img.Height - $rh)
            $bmp = New-Object System.Drawing.Bitmap 24, 24
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
            $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, 24, 24), (New-Object System.Drawing.Rectangle $x0, $y0, $rw, $rh), [System.Drawing.GraphicsUnit]::Pixel)
            $g.Dispose(); $img.Dispose()
            for ($x = 0; $x -lt 24; $x++) {
                for ($y = 0; $y -lt 24; $y++) {
                    $p = $bmp.GetPixel($x, $y)
                    $sumY += 0.2126 * (Get-Lin $p.R) + 0.7152 * (Get-Lin $p.G) + 0.0722 * (Get-Lin $p.B)
                    $sumB += (0.2126 * $p.R + 0.7152 * $p.G + 0.0722 * $p.B) / 255
                    $n++
                }
            }
            $bmp.Dispose()
        } finally { $fs.Dispose() }
    } else {
        # No picture: a solid color background
        $c = @(([string](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Colors' -ErrorAction Stop).Background).Trim() -split '\s+' | ForEach-Object { [double]$_ })
        $sumY = 0.2126 * (Get-Lin $c[0]) + 0.7152 * (Get-Lin $c[1]) + 0.0722 * (Get-Lin $c[2])
        $sumB = (0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2]) / 255
        $n = 1
    }
    $Y = $sumY / $n; $B = $sumB / $n
    $slot = 2
    if ($Mode -eq 'threshold') {
        if ($B -lt $Dark) { $slot = 2 } elseif ($B -gt $Light) { $slot = 0 } else { $slot = 1 }
    } else {
        # The text color with the highest contrast against this part of the wallpaper (WCAG ratio)
        $best = -1.0
        $i = 0
        foreach ($l in ($Lums -split ',')) {
            $L = [double]::Parse($l, $inv)
            $ratio = ([math]::Max($Y, $L) + 0.05) / ([math]::Min($Y, $L) + 0.05)
            if ($ratio -gt $best) { $best = $ratio; $slot = $i }
            $i++
        }
    }
    Write-Output ('{0} {1}' -f $slot, $B.ToString('0.000', $inv))
} catch { }
'@

$Oz.ThemeScripts['@Resources\Scripts\WallIndex.ps1'] = @'
# OZZYHN theme (Optimizaciones de Ozzyhn): lists the pictures in your wallpaper folders for the picker,
# makes small previews and sorts them by color. Your pictures are only read, never changed.
param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$res = Split-Path -Parent $Root
$out = Join-Path $res 'Walls'
$cache = Join-Path $out 'Cache'
Add-Type -AssemblyName System.Drawing
foreach ($d in $out, $cache) {
    if (-not [IO.Directory]::Exists($d)) { [void][IO.Directory]::CreateDirectory($d) }
    if (([IO.File]::GetAttributes($d) -band [IO.FileAttributes]::ReparsePoint)) { throw "Links are not used: $d" }
}
# Folders come from Settings.inc (written by the app): WallFolder1=..., WallFolder2=...
$folders = @()
foreach ($line in [IO.File]::ReadAllLines((Join-Path $res 'Settings.inc'))) {
    if ($line -match '^\s*WallFolder\d+\s*=\s*(.+?)\s*$' -and [IO.Directory]::Exists($Matches[1])) { $folders += $Matches[1] }
}
$files = New-Object System.Collections.Generic.List[object]
foreach ($f in $folders) {
    foreach ($fi in @(Get-ChildItem -LiteralPath $f -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        # # and [ ] mean something to Rainmeter, so such names are left out
        if ($fi.Extension -notin '.jpg', '.jpeg', '.png', '.bmp' -or $fi.Name -match '[#\[\]]') { continue }
        $files.Add($fi)
        if ($files.Count -ge 300) { break }
    }
}
$sha = [Security.Cryptography.SHA256]::Create()
$keep = @{}
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('[Variables]')
[void]$sb.AppendLine('NeedIndex=0')
[void]$sb.AppendLine('Wall0=')
[void]$sb.AppendLine('Thumb0=')
[void]$sb.AppendLine('Name0=')
[void]$sb.AppendLine('Tag0=')
$n = 0
foreach ($fi in $files) {
    try {
        $key = '{0}|{1}|{2}' -f $fi.FullName, $fi.Length, $fi.LastWriteTimeUtc.Ticks
        $h = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($key))[0..9] | ForEach-Object { $_.ToString('x2') })
        $thumb = Join-Path $cache ($h + '.jpg')
        if (-not [IO.File]::Exists($thumb)) {
            $fs = [IO.File]::Open($fi.FullName, 'Open', 'Read', 'ReadWrite')
            try {
                $img = [System.Drawing.Image]::FromStream($fs, $false, $false)
                $tw = 448; $th = 252
                $scale = [math]::Max($tw / $img.Width, $th / $img.Height)
                $sw = [int]($tw / $scale); $sh = [int]($th / $scale)
                $sx = [int](($img.Width - $sw) / 2); $sy = [int](($img.Height - $sh) / 2)
                $bmp = New-Object System.Drawing.Bitmap $tw, $th
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $tw, $th), (New-Object System.Drawing.Rectangle $sx, $sy, $sw, $sh), [System.Drawing.GraphicsUnit]::Pixel)
                $g.Dispose(); $img.Dispose()
                $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
                $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
                $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [int64]84)
                $bmp.Save($thumb, $codec, $ep)
                $bmp.Dispose()
            } finally { $fs.Dispose() }
        }
        # Color tags from the preview: L light, D dark, W warm (red / orange), C cool (blue / cyan / green)
        $src = [System.Drawing.Image]::FromFile($thumb)
        $s = New-Object System.Drawing.Bitmap 32, 18
        $g = [System.Drawing.Graphics]::FromImage($s)
        $g.DrawImage($src, 0, 0, 32, 18)
        $g.Dispose(); $src.Dispose()
        $sumB = 0.0; $warm = 0; $cool = 0; $tot = 0
        for ($x = 0; $x -lt 32; $x++) {
            for ($y = 0; $y -lt 18; $y++) {
                $p = $s.GetPixel($x, $y)
                $sumB += (0.2126 * $p.R + 0.7152 * $p.G + 0.0722 * $p.B) / 255
                if ($p.GetSaturation() -gt 0.35 -and $p.GetBrightness() -gt 0.15) {
                    $hue = $p.GetHue()
                    if ($hue -lt 50 -or $hue -ge 330) { $warm++ } elseif ($hue -ge 160 -and $hue -lt 260) { $cool++ }
                }
                $tot++
            }
        }
        $s.Dispose()
        $b = $sumB / $tot
        $tag = ''
        if ($b -ge 0.58) { $tag += 'L' }
        if ($b -le 0.30) { $tag += 'D' }
        if ($warm / $tot -ge 0.18) { $tag += 'W' }
        if ($cool / $tot -ge 0.18) { $tag += 'C' }
        $n++
        $keep[$thumb] = $true
        $name = [IO.Path]::GetFileNameWithoutExtension($fi.Name)
        if ($name.Length -gt 60) { $name = $name.Substring(0, 60) }
        [void]$sb.AppendLine(('Wall{0}={1}' -f $n, $fi.FullName))
        [void]$sb.AppendLine(('Thumb{0}={1}' -f $n, $thumb))
        [void]$sb.AppendLine(('Name{0}={1}' -f $n, $name))
        [void]$sb.AppendLine(('Tag{0}={1}' -f $n, $tag))
    } catch { }
}
[void]$sb.AppendLine(('WallCount={0}' -f $n))
[IO.File]::WriteAllText((Join-Path $out 'Index.inc'), $sb.ToString(), [Text.Encoding]::Unicode)
foreach ($old in @(Get-ChildItem -LiteralPath $cache -File -Filter '*.jpg' -ErrorAction SilentlyContinue)) {
    if (-not $keep.ContainsKey($old.FullName)) { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue }
}
Write-Output $n
'@
#endregion

#region ============================ THEMES (RAINMETER) ============================
# Desktop themes for Rainmeter (rainmeter.net, free and open source). The app never downloads or
# installs Rainmeter: it sends you to the official site. It writes its own skins into the Rainmeter
# skins folder (OZZYHN), loads them, and removes them again with REMOVE THEME. Rainmeter is always
# started as you, not as administrator, and the scripts inside the skins are never run by the app.

# Color sets for the bar, dock and wallpaper picker. Colors are Rainmeter "r,g,b,alpha".
$Oz.ThemeLooks = [ordered]@{
    'mono-dark'  = @{ Name = 'MONO DARK'; Swatch = '#141416'; Edge = '#EEEEEE'; PillBg = '16,16,18,205'; PillLine = '255,255,255,28'; PanelBg = '12,12,14,228'
        TextMain = '238,238,238'; TextSub = '238,238,238,150'; Accent = '255,255,255'; Accent2 = '150,150,150' }
    'mono-light' = @{ Name = 'MONO LIGHT'; Swatch = '#F2F2F2'; Edge = '#202020'; PillBg = '245,245,245,215'; PillLine = '0,0,0,24'; PanelBg = '246,246,246,235'
        TextMain = '24,24,24'; TextSub = '24,24,24,150'; Accent = '20,20,20'; Accent2 = '120,120,120' }
    'neon'       = @{ Name = 'OZZYHN NEON'; Swatch = '#05070D'; Edge = '#00E5FF'; PillBg = '5,7,13,215'; PillLine = '0,229,255,64'; PanelBg = '5,7,13,235'
        TextMain = '230,241,255'; TextSub = '138,155,191'; Accent = '0,229,255'; Accent2 = '255,43,214' }
    'crimson'    = @{ Name = 'CRIMSON'; Swatch = '#140C0E'; Edge = '#FF3B50'; PillBg = '14,10,11,215'; PillLine = '255,59,80,58'; PanelBg = '12,8,9,235'
        TextMain = '242,232,232'; TextSub = '242,232,232,140'; Accent = '255,59,80'; Accent2 = '255,150,80' }
    'arctic'     = @{ Name = 'ARCTIC'; Swatch = '#0A1520'; Edge = '#78D2FF'; PillBg = '10,18,28,208'; PillLine = '120,200,255,52'; PanelBg = '8,14,22,232'
        TextMain = '226,240,250'; TextSub = '160,190,210'; Accent = '120,210,255'; Accent2 = '180,140,255' }
}
$Oz.ThemeStyles = @('Horizon', 'Blade', 'Stack', 'Pulse', 'Minimal')
$Oz.ThemePositions = @('TL', 'T', 'TR', 'L', 'C', 'R', 'BL', 'B', 'BR')
# Rainmeter time formats and the .NET formats used to show an example in the app
$Oz.ThemeDateFormats = @(
    @{ Rm = '%d %b %Y'; Net = 'dd MMM yyyy' }, @{ Rm = '%#d %B'; Net = 'd MMMM' }, @{ Rm = '%b %d, %Y'; Net = 'MMM dd, yyyy' },
    @{ Rm = '%d/%m/%Y'; Net = 'dd/MM/yyyy' }, @{ Rm = '%Y-%m-%d'; Net = 'yyyy-MM-dd' })

# Words shown inside the skins. Spanish accents are HTML entities here and become real letters
# when Strings.inc is written (as UTF-16).
$Oz.ThemeWords = @{
    en = [ordered]@{
        S_RefreshColors = 'Refresh colors'; S_NextStyle = 'Next clock style'; S_Wallpapers = 'Wallpapers'; S_Settings = 'Windows Settings'
        S_Mute = 'MUTE'; S_Rescan = 'Look for new pictures'; S_OpenFolder = 'Open the wallpaper folder'; S_Close = 'Close'
        S_FilterAll = 'All'; S_FilterLight = 'Light'; S_FilterDark = 'Dark'; S_FilterWarm = 'Warm colors'; S_FilterCool = 'Cool colors'
        S_UseWallpaper = 'Use as wallpaper'; S_NoWalls = 'No pictures yet. Add some to the wallpaper folder, then press the refresh button.'
        S_Scanning = 'Looking for pictures...'; S_AllApps = 'All apps'
        S_IndexFailed = 'The pictures could not be read. Check that PowerShell can run, then press the refresh button.'
        S_G1Morning = 'GOOD'; S_G2Morning = 'MORNING'; S_G1Afternoon = 'GOOD'; S_G2Afternoon = 'AFTERNOON'
        S_G1Evening = 'GOOD'; S_G2Evening = 'EVENING'; S_G1Night = 'GOOD'; S_G2Night = 'NIGHT'
    }
    es = [ordered]@{
        S_RefreshColors = 'Actualizar colores'; S_NextStyle = 'Siguiente estilo de reloj'; S_Wallpapers = 'Fondos de pantalla'; S_Settings = 'Configuraci&oacute;n de Windows'
        S_Mute = 'SILENCIO'; S_Rescan = 'Buscar im&aacute;genes nuevas'; S_OpenFolder = 'Abrir la carpeta de fondos'; S_Close = 'Cerrar'
        S_FilterAll = 'Todos'; S_FilterLight = 'Claros'; S_FilterDark = 'Oscuros'; S_FilterWarm = 'Colores c&aacute;lidos'; S_FilterCool = 'Colores fr&iacute;os'
        S_UseWallpaper = 'Usar como fondo'; S_NoWalls = 'A&uacute;n no hay im&aacute;genes. Agrega algunas a la carpeta de fondos y pulsa el bot&oacute;n de actualizar.'
        S_Scanning = 'Buscando im&aacute;genes...'; S_AllApps = 'Todas las apps'
        S_IndexFailed = 'No se pudieron leer las im&aacute;genes. Comprueba que PowerShell pueda ejecutarse y pulsa el bot&oacute;n de actualizar.'
        S_G1Morning = 'BUENOS'; S_G2Morning = 'D&Iacute;AS'; S_G1Afternoon = 'BUENAS'; S_G2Afternoon = 'TARDES'
        S_G1Evening = 'BUENAS'; S_G2Evening = 'NOCHES'; S_G1Night = 'BUENAS'; S_G2Night = 'NOCHES'
    }
}

function Get-OzThemeDefaults {
    $pics = [Environment]::GetFolderPath('MyPictures')
    if (-not $pics) { $pics = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Pictures' }
    $h24 = $true
    try { $h24 = (Get-Culture).DateTimeFormat.ShortTimePattern -notmatch 'h' } catch { }
    # Rainmeter draws in real pixels, so on a 125% / 150% screen the skins are made that much bigger
    $scale = 100
    try {
        $dpi = [int](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction Stop).AppliedDPI
        if ($dpi -ge 96) { $scale = [int]([math]::Round($dpi / 96 * 4) * 25) }
    } catch { }
    [ordered]@{
        Look = 'mono-dark'; Scale = [math]::Min(200, [math]::Max(75, $scale)); Clock = $true; Style = 'Horizon'; Pos = 'C'
        MarginX = 160; MarginY = 120; Hour24 = [bool]$h24; DateFmt = 0
        AutoInk = $true; InkMode = 'contrast'; InkRegion = 20; InkDarkTh = 0.2; InkLightTh = 0.8; InkFixed = 2
        InkDark = '#141414'; InkMid = '#4A4A4A'; InkLight = '#F5F5F5'
        Bar = $true; BarOnTop = $false; Dock = $true; DockApps = @(); DockCustom = @(); HideSamples = $true
        WallFolders = @((Join-Path $pics 'OZZYHN Wallpapers')); WallFit = 'Fill'
    }
}

function Read-OzThemeSettings {
    # The THEMES page settings (C:\ProgramData\Ozzyhn\theme.json), with defaults for anything missing
    $cfg = Get-OzThemeDefaults
    $file = Join-Path $Oz.DataDir 'theme.json'
    try {
        if (Test-Path -LiteralPath $file) {
            $j = Get-Content -LiteralPath $file -Raw -ErrorAction Stop | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { if ($cfg.Contains($p.Name)) { $cfg[$p.Name] = $p.Value } }
        }
    } catch { }
    if (-not $Oz.ThemeLooks.Contains([string]$cfg.Look)) { $cfg.Look = 'mono-dark' }
    if ($Oz.ThemeStyles -notcontains [string]$cfg.Style) { $cfg.Style = 'Horizon' }
    if ($Oz.ThemePositions -notcontains [string]$cfg.Pos) { $cfg.Pos = 'C' }
    $cfg.Scale = [int][math]::Min(200, [math]::Max(75, [int]$cfg.Scale))
    $cfg.MarginX = [int][math]::Min(2000, [math]::Max(0, [int]$cfg.MarginX))
    $cfg.MarginY = [int][math]::Min(2000, [math]::Max(0, [int]$cfg.MarginY))
    $cfg.DateFmt = [int][math]::Min($Oz.ThemeDateFormats.Count - 1, [math]::Max(0, [int]$cfg.DateFmt))
    $cfg.InkRegion = [int][math]::Min(100, [math]::Max(5, [int]$cfg.InkRegion))
    $cfg.InkDarkTh = [math]::Round([math]::Min(1, [math]::Max(0, [double]$cfg.InkDarkTh)), 2)
    $cfg.InkLightTh = [math]::Round([math]::Min(1, [math]::Max($cfg.InkDarkTh, [double]$cfg.InkLightTh)), 2)
    $cfg.InkFixed = [int][math]::Min(2, [math]::Max(0, [int]$cfg.InkFixed))
    if ($cfg.InkMode -notin 'contrast', 'threshold') { $cfg.InkMode = 'contrast' }
    foreach ($k in 'InkDark', 'InkMid', 'InkLight') { if ([string]$cfg[$k] -notmatch '^#[0-9A-Fa-f]{6}$') { $cfg[$k] = (Get-OzThemeDefaults)[$k] } }
    if ($cfg.WallFit -notin 'Fill', 'Fit', 'Stretch', 'Center', 'Span') { $cfg.WallFit = 'Fill' }
    $cfg.WallFolders = @(@($cfg.WallFolders) | Where-Object { $_ -and [string]$_ -match '^[A-Za-z]:\\' } | ForEach-Object { [string]$_ } | Select-Object -Unique -First 8)
    $cfg.DockApps = @(@($cfg.DockApps) | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $cfg.DockCustom = @(@($cfg.DockCustom) | Where-Object { $_ -and $_.Target } | Select-Object -First 12)
    $cfg
}

function Save-OzThemeSettings {
    param($Cfg)
    try {
        if (-not (Test-Path -LiteralPath $Oz.DataDir)) { New-Item -ItemType Directory -Path $Oz.DataDir -Force | Out-Null }
        [pscustomobject]$Cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Oz.DataDir 'theme.json') -Encoding UTF8
    } catch { Write-OzLog "Could not save theme settings: $($_.Exception.Message)" 'WARN' }
}

function Expand-OzThemeText {
    # {{84}} -> 84 x scale, as whole pixels (one decimal for sizes under 10)
    param([string]$Text, [double]$Scale)
    $sb = New-Object System.Text.StringBuilder
    $last = 0
    foreach ($m in [regex]::Matches($Text, '\{\{(-?\d+(?:\.\d+)?)\}\}')) {
        [void]$sb.Append($Text, $last, $m.Index - $last)
        $v = [double]::Parse($m.Groups[1].Value, $Oz.Inv) * $Scale
        if ([math]::Abs($v) -ge 10 -or [math]::Abs($v - [math]::Round($v)) -lt 0.05) { [void]$sb.Append([string][int][math]::Round($v)) }
        else { [void]$sb.Append($v.ToString('0.0', $Oz.Inv)) }
        $last = $m.Index + $m.Length
    }
    [void]$sb.Append($Text, $last, $Text.Length - $last)
    $sb.ToString()
}

function ConvertTo-OzRmColor {
    # '#F5F5F5' -> '245,245,245'
    param([string]$Hex)
    $h = $Hex.TrimStart('#')
    '{0},{1},{2}' -f [Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)
}

function Get-OzRelLum {
    # WCAG relative luminance of '#RRGGBB'
    param([string]$Hex)
    $h = $Hex.TrimStart('#')
    $sum = 0.0
    $w = 0.2126, 0.7152, 0.0722
    for ($i = 0; $i -lt 3; $i++) {
        $c = [Convert]::ToInt32($h.Substring($i * 2, 2), 16) / 255
        $lin = if ($c -le 0.04045) { $c / 12.92 } else { [math]::Pow(($c + 0.055) / 1.055, 2.4) }
        $sum += $w[$i] * $lin
    }
    $sum
}

function Get-OzThemePlace {
    # Where the clock sits: Rainmeter window position, anchor, text alignment and the part of the
    # wallpaper to read for its color (Cx, Cy as fractions of the screen)
    param([string]$Pos, [int]$MarginX, [int]$MarginY)
    $i = [array]::IndexOf($Oz.ThemePositions, $Pos)
    if ($i -lt 0) { $i = 4 }
    $col = $i % 3; $row = [math]::Floor($i / 3)
    $x = @(('(#WORKAREAX#+{0})' -f $MarginX), '(#WORKAREAX#+#WORKAREAWIDTH#/2)', ('(#WORKAREAX#+#WORKAREAWIDTH#-{0})' -f $MarginX))[$col]
    $y = @(('(#WORKAREAY#+{0})' -f $MarginY), '(#WORKAREAY#+#WORKAREAHEIGHT#/2)', ('(#WORKAREAY#+#WORKAREAHEIGHT#-{0})' -f $MarginY))[$row]
    [pscustomobject]@{
        PosX = $x; PosY = $y; AnchorX = @('0%', '50%', '100%')[$col]; AnchorY = @('0%', '50%', '100%')[$row]
        Align = @('Left', 'Center', 'Right')[$col]; AlignK = @('0', '0.5', '1')[$col]
        Cx = @('0.2', '0.5', '0.8')[$col]; Cy = @('0.22', '0.5', '0.78')[$row]
    }
}

function Get-OzDockCatalog {
    # Apps that can go on the dock, only those installed on this PC. Default = on the dock at first.
    $sys = $env:SystemRoot
    $pf = $env:ProgramFiles; $pf86 = ${env:ProgramFiles(x86)}; $la = $env:LOCALAPPDATA; $ra = $env:APPDATA
    $steam = $null
    try { $steam = [string](Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamExe } catch { }
    if ($steam) { $steam = $steam -replace '/', '\' }
    $list = @(
        @{ Id = 'explorer'; Name = 'File Explorer'; Target = "$sys\explorer.exe"; Args = ''; Icon = ''; Default = $true }
        @{ Id = 'edge'; Name = 'Microsoft Edge'; Target = "$pf86\Microsoft\Edge\Application\msedge.exe"; Args = ''; Icon = ''; Default = $false }
        @{ Id = 'chrome'; Name = 'Google Chrome'; Target = @("$pf\Google\Chrome\Application\chrome.exe", "$la\Google\Chrome\Application\chrome.exe"); Args = ''; Icon = ''; Default = $true }
        @{ Id = 'firefox'; Name = 'Firefox'; Target = "$pf\Mozilla Firefox\firefox.exe"; Args = ''; Icon = ''; Default = $true }
        @{ Id = 'brave'; Name = 'Brave'; Target = @("$pf\BraveSoftware\Brave-Browser\Application\brave.exe", "$la\BraveSoftware\Brave-Browser\Application\brave.exe"); Args = ''; Icon = ''; Default = $true }
        @{ Id = 'operagx'; Name = 'Opera GX'; Target = "$la\Programs\Opera GX\launcher.exe"; Args = ''; Icon = ''; Default = $true }
        @{ Id = 'steam'; Name = 'Steam'; Target = @($steam, "$pf86\Steam\steam.exe"); Args = ''; Icon = ''; Default = $true }
        @{ Id = 'epic'; Name = 'Epic Games'; Target = @("$pf86\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe", "$pf86\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe"); Args = ''; Icon = ''; Default = $false }
        @{ Id = 'discord'; Name = 'Discord'; Target = "$la\Discord\Update.exe"; Args = '--processStart Discord.exe'; Icon = "$la\Discord\app.ico"; Default = $true }
        @{ Id = 'spotify'; Name = 'Spotify'; Target = "$ra\Spotify\Spotify.exe"; Args = ''; Icon = ''; Default = $true }
        @{ Id = 'obs'; Name = 'OBS Studio'; Target = "$pf\obs-studio\bin\64bit\obs64.exe"; Args = ''; Icon = ''; Default = $false }
        @{ Id = 'vscode'; Name = 'VS Code'; Target = @("$la\Programs\Microsoft VS Code\Code.exe", "$pf\Microsoft VS Code\Code.exe"); Args = ''; Icon = ''; Default = $false }
        @{ Id = 'taskmgr'; Name = 'Task Manager'; Target = "$sys\System32\Taskmgr.exe"; Args = ''; Icon = ''; Default = $false }
        @{ Id = 'settings'; Name = 'Settings'; Target = "$sys\explorer.exe"; Args = 'ms-settings:'; Icon = "$sys\ImmersiveControlPanel\SystemSettings.exe,0"; Default = $true }
        @{ Id = 'recycle'; Name = 'Recycle Bin'; Target = "$sys\explorer.exe"; Args = 'shell:RecycleBinFolder'; Icon = "$sys\System32\imageres.dll,-55"; Default = $true }
    )
    $found = @()
    foreach ($a in $list) {
        $t = @($a.Target) | Where-Object { $_ -and [IO.File]::Exists([string]$_) } | Select-Object -First 1
        if (-not $t) { continue }
        $icon = [string]$a.Icon
        if ($icon -and -not [IO.File]::Exists(($icon -replace ',-?\d+$', ''))) { $icon = '' }
        $found += [pscustomobject]@{ Id = $a.Id; Name = $a.Name; Target = [string]$t; Args = $a.Args; Icon = $icon; Default = $a.Default }
    }
    # Only one browser on by default: the first one found after Edge
    $firstBrowser = $found | Where-Object { $_.Id -in 'chrome', 'firefox', 'brave', 'operagx' } | Select-Object -First 1
    foreach ($a in $found) {
        if ($a.Id -in 'chrome', 'firefox', 'brave', 'operagx' -and $firstBrowser -and $a.Id -ne $firstBrowser.Id) { $a.Default = $false }
    }
    if (-not $firstBrowser) { foreach ($a in $found) { if ($a.Id -eq 'edge') { $a.Default = $true } } }
    $found
}

function Get-OzDockApps {
    # The apps that go on the dock for these settings, in dock order
    param($Cfg)
    $cat = @(Get-OzDockCatalog)
    $chosen = @($Cfg.DockApps)
    $apps = @()
    if ($chosen.Count) { foreach ($id in $chosen) { $apps += @($cat | Where-Object Id -EQ $id) } }
    else { $apps = @($cat | Where-Object Default) }
    foreach ($c in @($Cfg.DockCustom)) {
        if ($c.Target -and [IO.File]::Exists([string]$c.Target)) {
            $apps += [pscustomobject]@{ Id = 'custom'; Name = [string]$c.Name; Target = [string]$c.Target; Args = ''; Icon = ''; Default = $true }
        }
    }
    @($apps | Select-Object -First 14)
}

function New-OzDockIni {
    # The dock skin is written for the exact number of apps, so it needs no script
    param([object[]]$Apps)
    $n = $Apps.Count
    $I = 46; $Gap = 12; $Pad = 12
    $iconsW = $n * $I + [math]::Max(0, $n - 1) * $Gap
    $W = 2 * $Pad + $iconsW + $Gap + 1 + $Gap + $I
    $sb = New-Object System.Text.StringBuilder
    $add = { param($l) [void]$sb.AppendLine($l) }
    & $add '; OZZYHN dock: your apps in a floating bar. Choose the apps on the THEMES page.'
    & $add '[Rainmeter]'
    & $add 'Update=1000'
    & $add 'AccurateText=1'
    & $add 'Group=OzAll'
    & $add 'OnRefreshAction=[!SetWindowPosition "(#WORKAREAX#+#WORKAREAWIDTH#/2)" "(#WORKAREAY#+#WORKAREAHEIGHT#-#DockM#)" "50%" "100%"][!ZPos -2][!Draggable 0]'
    & $add ''
    & $add '[Metadata]'
    & $add 'Name=OZZYHN Dock'
    & $add 'Author=OZZYHN TWEAKS'
    & $add "Information=Made by Optimizaciones de Ozzyhn. Change it from the app's THEMES page."
    & $add 'Version=1.0'
    & $add 'License=MIT'
    & $add ''
    & $add '[Variables]'
    & $add '@Include=#@#Settings.inc'
    & $add '@Include2=#@#Strings.inc'
    & $add ''
    & $add '[mFolder]'
    & $add 'Measure=Plugin'
    & $add 'Plugin=FileView'
    & $add 'Path=#@#Dock\Apps\'
    & $add 'ShowDotDot=0'
    & $add 'ShowFolder=0'
    & $add 'SortType=Name'
    & $add ('Count={0}' -f [math]::Max(1, $n))
    for ($k = 1; $k -le $n; $k++) {
        & $add ''
        & $add ('[mIcon{0}]' -f $k)
        & $add 'Measure=Plugin'
        & $add 'Plugin=FileView'
        & $add 'Path=[mFolder]'
        & $add 'Type=Icon'
        & $add 'IconSize=ExtraLarge'
        & $add ('Index={0}' -f $k)
        & $add ('IconPath=#@#Dock\Icons\{0}.ico' -f $k)
    }
    & $add ''
    & $add '[mBox]'
    & $add 'Meter=Image'
    & $add ('W={{{{{0}}}}}' -f $W)
    & $add ('H={{{{{0}}}}}' -f (10 + $I + 2 * $Pad))
    & $add 'SolidColor=0,0,0,0'
    & $add ''
    & $add '[pDock]'
    & $add 'Meter=Shape'
    & $add ('Shape=Rectangle 0.5,{{{{10}}}},{{{{{0}}}}},{{{{{1}}}}},{{{{20}}}} | Fill Color #PillBg# | Stroke Color #PillLine# | StrokeWidth 1' -f ($W - 1), ($I + 2 * $Pad))
    $x = $Pad
    for ($k = 1; $k -le $n; $k++) {
        $a = $Apps[$k - 1]
        $lnk = '#@#Dock\Apps\{0:D2}.lnk' -f $k
        & $add ''
        & $add ('[i{0}]' -f $k)
        & $add 'Meter=Image'
        & $add ('MeasureName=mIcon{0}' -f $k)
        & $add ('X={{{{{0}}}}}' -f $x)
        & $add ('Y={{{{{0}}}}}' -f (10 + $Pad))
        & $add ('W={{{{{0}}}}}' -f $I)
        & $add ('H={{{{{0}}}}}' -f $I)
        & $add 'PreserveAspectRatio=1'
        & $add 'AntiAlias=1'
        & $add ('ToolTipText={0}' -f ([string]$a.Name -replace '[\r\n#\[\]]', ''))
        & $add ('LeftMouseUpAction=["{0}"]' -f $lnk)
        & $add 'MouseActionCursor=1'
        & $add ('MouseOverAction=[!SetOption i{0} X "{{{{{1}}}}}"][!SetOption i{0} Y "{{{{{2}}}}}"][!SetOption i{0} W "{{{{{3}}}}}"][!SetOption i{0} H "{{{{{3}}}}}"][!UpdateMeter i{0}][!Redraw]' -f $k, ($x - 4), (10 + $Pad - 9), ($I + 8))
        & $add ('MouseLeaveAction=[!SetOption i{0} X "{{{{{1}}}}}"][!SetOption i{0} Y "{{{{{2}}}}}"][!SetOption i{0} W "{{{{{3}}}}}"][!SetOption i{0} H "{{{{{3}}}}}"][!UpdateMeter i{0}][!Redraw]' -f $k, $x, (10 + $Pad), $I)
        $x += $I + $Gap
    }
    $sepX = $Pad + $iconsW + $Gap
    & $add ''
    & $add '[lSep]'
    & $add 'Meter=Shape'
    & $add ('Shape=Line {{{{{0}}}}},{{{{{1}}}}},{{{{{0}}}}},{{{{{2}}}}} | StrokeWidth 1 | Stroke Color #PillLine#' -f $sepX, (10 + $Pad + 8), (10 + $Pad + $I - 8))
    & $add ''
    & $add '[bApps]'
    & $add 'Meter=String'
    & $add 'Text=[\xE71D]'
    & $add 'FontFace=#FontIcons#'
    & $add 'FontSize={{18}}'
    & $add 'FontColor=#TextMain#'
    & $add 'AntiAlias=1'
    & $add 'StringAlign=CenterCenter'
    & $add ('X={{{{{0}}}}}' -f ($sepX + $Gap + $I / 2))
    & $add ('Y={{{{{0}}}}}' -f (10 + $Pad + $I / 2))
    & $add 'ToolTipText=#S_AllApps#'
    & $add 'LeftMouseUpAction=["explorer.exe" "shell:AppsFolder"]'
    & $add 'MouseActionCursor=1'
    $sb.ToString()
}

function New-OzThemeFiles {
    # Every file of the theme as text, by path inside Skins\OZZYHN. Unicode = written as UTF-16
    # (Rainmeter reads that for names with accents); the rest is plain ASCII.
    param($Cfg, [int]$InkSlot = 2)
    $s = [double]$Cfg.Scale / 100
    $look = $Oz.ThemeLooks[[string]$Cfg.Look]
    $place = Get-OzThemePlace $Cfg.Pos $Cfg.MarginX $Cfg.MarginY
    $lang = if ($Oz.Lang -eq 'es') { 'es' } else { 'en' }
    $hasBat = [bool]($Oz.Sys -and $Oz.Sys.Battery -and $Oz.Sys.Battery.Present)
    $date = $Oz.ThemeDateFormats[[int]$Cfg.DateFmt].Rm
    $time = if ($Cfg.Hour24) { '%H:%M' } else { '%#I:%M %p' }
    $folders = @($Cfg.WallFolders)
    $files = [ordered]@{}

    $set = New-Object System.Text.StringBuilder
    $line = { param($k, $v) [void]$set.AppendLine(('{0}={1}' -f $k, $v)) }
    [void]$set.AppendLine('; Written by Optimizaciones de Ozzyhn (THEMES page). Change it there: this file is replaced on APPLY.')
    [void]$set.AppendLine('[Variables]')
    & $line 'S' $s.ToString('0.##', $Oz.Inv)
    & $line 'Locale' $(if ($lang -eq 'es') { 'es-ES' } else { 'en-US' })
    & $line 'TimeFmt' $time
    & $line 'HourFmt' $(if ($Cfg.Hour24) { '%H' } else { '%#I' })
    & $line 'TimeShort' $(if ($Cfg.Hour24) { '%H:%M' } else { '%#I:%M' })
    & $line 'PulseInfo' $(if ($Cfg.Hour24) { '%1  [\x00B7]  %2' } else { '%1  [\x00B7]  %2  [\x00B7]  %3' })
    & $line 'DateFmt' $date
    & $line 'BarTimeFmt' ('%a %d %b   ' + $(if ($Cfg.Hour24) { '%H:%M:%S' } else { '%#I:%M:%S %p' }))
    foreach ($p in 'PosX', 'PosY', 'AnchorX', 'AnchorY', 'Align', 'AlignK') { & $line $p $place.$p }
    & $line 'AutoInk' $(if ($Cfg.AutoInk) { 1 } else { 0 })
    & $line 'NoAutoInk' $(if ($Cfg.AutoInk) { 0 } else { 1 })
    & $line 'InkMode' $Cfg.InkMode
    & $line 'InkRegion' $Cfg.InkRegion
    & $line 'InkDarkTh' ([double]$Cfg.InkDarkTh).ToString('0.00', $Oz.Inv)
    & $line 'InkLightTh' ([double]$Cfg.InkLightTh).ToString('0.00', $Oz.Inv)
    & $line 'InkFixed' $Cfg.InkFixed
    & $line 'InkCx' $place.Cx
    & $line 'InkCy' $place.Cy
    & $line 'InkDark' (ConvertTo-OzRmColor $Cfg.InkDark)
    & $line 'InkMid' (ConvertTo-OzRmColor $Cfg.InkMid)
    & $line 'InkLight' (ConvertTo-OzRmColor $Cfg.InkLight)
    & $line 'InkLums' ((@($Cfg.InkDark, $Cfg.InkMid, $Cfg.InkLight) | ForEach-Object { (Get-OzRelLum $_).ToString('0.0000', $Oz.Inv) }) -join ',')
    foreach ($k in 'PillBg', 'PillLine', 'PanelBg', 'TextMain', 'TextSub', 'Accent', 'Accent2') { & $line $k $look[$k] }
    & $line 'FontDisplay' 'Bahnschrift'
    & $line 'FontBody' 'Segoe UI'
    & $line 'FontIcons' 'Segoe MDL2 Assets'
    & $line 'HasBattery' $(if ($hasBat) { 1 } else { 0 })
    & $line 'NoBattery' $(if ($hasBat) { 0 } else { 1 })
    & $line 'BarX' ([int][math]::Round(12 * $s))
    & $line 'BarY' ('(#WORKAREAY#+{0})' -f [int][math]::Round(8 * $s))
    & $line 'BarZ' $(if ($Cfg.BarOnTop) { 1 } else { -2 })
    & $line 'DockM' ([int][math]::Round(12 * $s))
    & $line 'WallsY' ('(#WORKAREAY#+{0})' -f [int][math]::Round(64 * $s))
    & $line 'WallFit' $Cfg.WallFit
    & $line 'WallFolderMain' $(if ($folders.Count) { $folders[0] } else { [Environment]::GetFolderPath('MyPictures') })
    for ($i = 0; $i -lt $folders.Count; $i++) { & $line ('WallFolder{0}' -f ($i + 1)) $folders[$i] }
    $files['@Resources\Settings.inc'] = @{ Text = $set.ToString(); Unicode = $true }

    $str = New-Object System.Text.StringBuilder
    [void]$str.AppendLine('[Variables]')
    foreach ($k in $Oz.ThemeWords[$lang].Keys) { [void]$str.AppendLine(('{0}={1}' -f $k, [System.Net.WebUtility]::HtmlDecode($Oz.ThemeWords[$lang][$k]))) }
    $files['@Resources\Strings.inc'] = @{ Text = $str.ToString(); Unicode = $true }
    $files['@Resources\State.inc'] = @{ Text = ("[Variables]`r`nInkSlot={0}`r`n" -f $InkSlot); Unicode = $true }
    $files['@Resources\Walls\Index.inc'] = @{ Text = "[Variables]`r`nNeedIndex=1`r`nWallCount=0`r`nWall0=`r`nThumb0=`r`nName0=`r`nTag0=`r`n"; Unicode = $true }

    foreach ($k in $Oz.ThemeTpl.Keys) { $files[$k] = @{ Text = (Expand-OzThemeText $Oz.ThemeTpl[$k] $s); Unicode = $false } }
    foreach ($k in $Oz.ThemeScripts.Keys) { $files[$k] = @{ Text = $Oz.ThemeScripts[$k]; Unicode = $false } }
    $dock = @(Get-OzDockApps $Cfg)
    $files['Dock\Dock.ini'] = @{ Text = (Expand-OzThemeText (New-OzDockIni $dock) $s); Unicode = $true }
    $files
}

function Get-OzRainmeter {
    # Finds Rainmeter (installed or portable), its settings and skins folders, and which of our skins are loaded
    $r = [ordered]@{ Installed = $false; Exe = ''; Version = ''; Running = $false; SettingsDir = ''; Ini = ''; SkinPath = ''; Active = @{}; Samples = @() }
    $dirs = @()
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Rainmeter', 'HKLM:\SOFTWARE\Rainmeter') {
        try { $v = (Get-Item -LiteralPath $k -ErrorAction Stop).GetValue(''); if ($v) { $dirs += [string]$v } } catch { }
    }
    $proc = @(Get-Process -Name Rainmeter -ErrorAction SilentlyContinue)
    foreach ($p in $proc) { try { if ($p.Path) { $dirs += (Split-Path -Parent $p.Path) } } catch { } }
    $dirs += (Join-Path $env:ProgramFiles 'Rainmeter')
    if (${env:ProgramFiles(x86)}) { $dirs += (Join-Path ${env:ProgramFiles(x86)} 'Rainmeter') }
    foreach ($d in $dirs) {
        if ($d -and [IO.File]::Exists((Join-Path $d 'Rainmeter.exe'))) { $r.Exe = Join-Path $d 'Rainmeter.exe'; break }
    }
    if (-not $r.Exe) { return [pscustomobject]$r }
    $r.Installed = $true
    try { $r.Version = [string](Get-Item -LiteralPath $r.Exe).VersionInfo.ProductVersion } catch { }
    $r.Running = $proc.Count -gt 0
    $dir = Split-Path -Parent $r.Exe
    # Portable copies keep Rainmeter.ini next to Rainmeter.exe
    $r.SettingsDir = if ([IO.File]::Exists((Join-Path $dir 'Rainmeter.ini'))) { $dir } else { Join-Path $env:APPDATA 'Rainmeter' }
    $r.Ini = Join-Path $r.SettingsDir 'Rainmeter.ini'
    $skins = ''
    $section = ''
    if ([IO.File]::Exists($r.Ini)) {
        foreach ($line in [IO.File]::ReadAllLines($r.Ini)) {
            if ($line -match '^\s*\[(.+)\]\s*$') { $section = $Matches[1]; continue }
            if ($section -eq 'Rainmeter' -and $line -match '^\s*SkinPath\s*=\s*(.+?)\s*$') { $skins = $Matches[1] }
            if ($line -match '^\s*Active\s*=\s*(\d+)') {
                $n = [int]$Matches[1]
                if ($n -gt 0 -and $section -like 'OZZYHN\*') { $r.Active[$section] = $n }
                if ($n -gt 0 -and $section -like 'illustro\*') { $r.Samples += $section }
            }
        }
    }
    if (-not $skins) {
        $skins = if ($r.SettingsDir -eq $dir) { Join-Path $dir 'Skins' } else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Rainmeter\Skins' }
    }
    $r.SkinPath = [Environment]::ExpandEnvironmentVariables($skins).TrimEnd('\')
    [pscustomobject]$r
}

function Get-OzActiveClockStyle {
    # Rainmeter.ini stores the loaded file as its position in the folder (alphabetical)
    param($Rm)
    if (-not $Rm.Active.ContainsKey('OZZYHN\Clock')) { return $null }
    $sorted = @($Oz.ThemeStyles | Sort-Object)
    $i = [int]$Rm.Active['OZZYHN\Clock'] - 1
    if ($i -ge 0 -and $i -lt $sorted.Count) { return $sorted[$i] }
    $null
}

function Test-OzNoLinkPath {
    # True when no folder on the way to $Path is a junction or symbolic link. The app writes there as
    # administrator, so a link planted by another program must never redirect it somewhere else.
    param([string]$Path)
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $false }
    $root = [IO.Path]::GetPathRoot($full).TrimEnd('\')
    for ($d = $full; $d -and $d.Length -gt $root.Length; $d = [IO.Path]::GetDirectoryName($d)) {
        if (-not ([IO.Directory]::Exists($d) -or [IO.File]::Exists($d))) { continue }
        try {
            $item = Get-Item -LiteralPath $d -Force -ErrorAction Stop
            if ([string]$item.LinkType -in 'Junction', 'SymbolicLink') { return $false }
        } catch { return $false }
    }
    $true
}

function Write-OzThemeFile {
    param([string]$Path, [string]$Text, [bool]$Unicode)
    $dir = Split-Path -Parent $Path
    if (-not (Test-OzNoLinkPath $dir)) { throw "A folder on the way to $dir is a link, so nothing was written there." }
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    if ([IO.File]::Exists($Path) -and -not (Test-OzNoLinkPath $Path)) { throw "$Path is a link, so it was not replaced." }
    $enc = if ($Unicode) { [Text.Encoding]::Unicode } else { New-Object Text.UTF8Encoding($false) }
    [IO.File]::WriteAllText($Path, ($Text -replace "`r?`n", "`r`n"), $enc)
}

function Start-OzRainmeterUser {
    # Starts Rainmeter as the signed-in user, never as administrator: dock clicks and skin scripts
    # then run without admin rights. Explorer starts it for us; a one-time task is the fallback.
    param($Rm)
    if (@(Get-Process -Name Rainmeter -ErrorAction SilentlyContinue).Count) { return $true }
    $wait = {
        for ($i = 0; $i -lt 40; $i++) {
            if (@(Get-Process -Name Rainmeter -ErrorAction SilentlyContinue).Count) { Start-Sleep -Milliseconds 1500; return $true }
            Start-Sleep -Milliseconds 250
        }
        $false
    }
    if (@(Get-Process -Name explorer -ErrorAction SilentlyContinue).Count) {
        try { Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"{0}"' -f $Rm.Exe) -ErrorAction Stop } catch { }
        if (& $wait) { return $true }
    }
    $task = 'Ozzyhn - start Rainmeter'
    try {
        $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $act = New-ScheduledTaskAction -Execute $Rm.Exe
        $pr = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $task -TaskPath '\' -Action $act -Principal $pr -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction Stop
        $ok = & $wait
    } catch { $ok = $false }
    finally { try { Unregister-ScheduledTask -TaskName $task -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue } catch { } }
    $ok
}

function Send-OzRainmeterBang {
    # Hands one bang to the running Rainmeter (Rainmeter.exe forwards it and exits)
    param($Rm, [string]$Bang, [string[]]$Arguments = @())
    $line = (@($Bang) + @($Arguments | ForEach-Object { '"{0}"' -f ($_ -replace '"', '') })) -join ' '
    try {
        $p = Start-Process -FilePath $Rm.Exe -ArgumentList $line -PassThru -WindowStyle Hidden -ErrorAction Stop
        if (-not $p.WaitForExit(15000)) { Write-OzLog "Rainmeter did not answer: $line" 'WARN' }
    } catch { Write-OzLog "Rainmeter bang failed ($line): $($_.Exception.Message)" 'WARN' }
}

function New-OzDockShortcuts {
    # Dock\Apps\01.lnk, 02.lnk... in dock order. The dock reads their icons with Rainmeter's FileView.
    param([string]$Dir, [object[]]$Apps)
    if (-not (Test-OzNoLinkPath $Dir)) { throw "A folder on the way to $Dir is a link, so the dock was not written." }
    if ([IO.Directory]::Exists($Dir)) { [void](Clear-OzFolder -Path $Dir -Filter '*.lnk') }
    else { [void][IO.Directory]::CreateDirectory($Dir) }
    $sh = New-Object -ComObject WScript.Shell
    try {
        for ($k = 1; $k -le $Apps.Count; $k++) {
            $a = $Apps[$k - 1]
            $l = $sh.CreateShortcut((Join-Path $Dir ('{0:D2}.lnk' -f $k)))
            $l.TargetPath = $a.Target
            if ($a.Args) { $l.Arguments = $a.Args }
            if ($a.Icon) { $l.IconLocation = $a.Icon }
            $l.WorkingDirectory = Split-Path -Parent $a.Target
            $l.Description = $a.Name
            $l.Save()
        }
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
}

function Get-OzWallLuma {
    # Same reading as the skins' Luma.ps1: brightness (0-1) and the best text color (0 dark, 1 mid, 2 light)
    # for the part of the wallpaper at Cx, Cy. Used for the preview and the first color after APPLY.
    param($Cfg)
    $place = Get-OzThemePlace $Cfg.Pos $Cfg.MarginX $Cfg.MarginY
    $res = [pscustomobject]@{ Slot = 2; Brightness = 0.0; File = '' }
    try {
        $wp = [string](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).WallPaper
        $file = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
        if (-not $wp) { $file = '' } elseif (-not [IO.File]::Exists($file)) { $file = $wp }
        $lin = { param([double]$c) $c = $c / 255; if ($c -le 0.04045) { $c / 12.92 } else { [math]::Pow(($c + 0.055) / 1.055, 2.4) } }
        $sumY = 0.0; $sumB = 0.0; $n = 0
        if ($file -and [IO.File]::Exists($file)) {
            $res.File = $file
            Add-Type -AssemblyName System.Drawing
            # A 384 x 216 copy of the wallpaper is kept between calls on the window's thread, so the
            # preview follows each click without decoding the full picture again
            $key = '{0}|{1}' -f $file, ([IO.File]::GetLastWriteTimeUtc($file).Ticks)
            $small = $null
            if (-not $OzWorker -and $Oz.ThemeLumaKey -eq $key -and $Oz.ThemeLumaSmall) { $small = $Oz.ThemeLumaSmall }
            else {
                $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
                try {
                    $img = [System.Drawing.Image]::FromStream($fs, $false, $false)
                    $small = New-Object System.Drawing.Bitmap 384, 216
                    $g = [System.Drawing.Graphics]::FromImage($small)
                    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
                    $g.DrawImage($img, 0, 0, 384, 216)
                    $g.Dispose(); $img.Dispose()
                } finally { $fs.Dispose() }
                if (-not $OzWorker) {
                    if ($Oz.ThemeLumaSmall) { try { $Oz.ThemeLumaSmall.Dispose() } catch { } }
                    $Oz.ThemeLumaSmall = $small; $Oz.ThemeLumaKey = $key
                }
            }
            $rw = [math]::Max(1, [int](384 * $Cfg.InkRegion / 100)); $rh = [math]::Max(1, [int](216 * $Cfg.InkRegion / 100))
            $x0 = [int][math]::Min([math]::Max(0, 384 * [double]$place.Cx - $rw / 2), 384 - $rw)
            $y0 = [int][math]::Min([math]::Max(0, 216 * [double]$place.Cy - $rh / 2), 216 - $rh)
            $bmp = New-Object System.Drawing.Bitmap 24, 24
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
            $g.DrawImage($small, (New-Object System.Drawing.Rectangle 0, 0, 24, 24), (New-Object System.Drawing.Rectangle $x0, $y0, $rw, $rh), [System.Drawing.GraphicsUnit]::Pixel)
            $g.Dispose()
            if ($OzWorker) { $small.Dispose() }
            for ($x = 0; $x -lt 24; $x++) {
                for ($y = 0; $y -lt 24; $y++) {
                    $p = $bmp.GetPixel($x, $y)
                    $sumY += 0.2126 * (& $lin $p.R) + 0.7152 * (& $lin $p.G) + 0.0722 * (& $lin $p.B)
                    $sumB += (0.2126 * $p.R + 0.7152 * $p.G + 0.0722 * $p.B) / 255
                    $n++
                }
            }
            $bmp.Dispose()
        } else {
            $c = @(([string](Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Colors' -ErrorAction Stop).Background).Trim() -split '\s+' | ForEach-Object { [double]$_ })
            $sumY = 0.2126 * (& $lin $c[0]) + 0.7152 * (& $lin $c[1]) + 0.0722 * (& $lin $c[2])
            $sumB = (0.2126 * $c[0] + 0.7152 * $c[1] + 0.0722 * $c[2]) / 255
            $n = 1
        }
        $Y = $sumY / $n; $B = $sumB / $n
        $res.Brightness = $B
        if ($Cfg.InkMode -eq 'threshold') {
            $res.Slot = if ($B -lt $Cfg.InkDarkTh) { 2 } elseif ($B -gt $Cfg.InkLightTh) { 0 } else { 1 }
        } else {
            $best = -1.0; $i = 0
            foreach ($h in @($Cfg.InkDark, $Cfg.InkMid, $Cfg.InkLight)) {
                $L = Get-OzRelLum $h
                $ratio = ([math]::Max($Y, $L) + 0.05) / ([math]::Min($Y, $L) + 0.05)
                if ($ratio -gt $best) { $best = $ratio; $res.Slot = $i }
                $i++
            }
        }
    } catch { }
    $res
}

function Install-OzTheme {
    # Writes the skins for these settings, starts Rainmeter as the user if needed and loads them
    param($Cfg)
    $rm = Get-OzRainmeter
    if (-not $rm.Installed) { throw (T 'Rainmeter is not installed. Press GET RAINMETER, install it, then try again.') }
    $root = Join-Path $rm.SkinPath 'OZZYHN'
    $ink = Get-OzWallLuma $Cfg
    $files = New-OzThemeFiles -Cfg $Cfg -InkSlot $ink.Slot
    foreach ($k in $files.Keys) { Write-OzThemeFile -Path (Join-Path $root $k) -Text $files[$k].Text -Unicode $files[$k].Unicode }
    foreach ($d in 'Dock\Icons', 'Walls\Cache') {
        $p = Join-Path $root "@Resources\$d"
        if (-not (Test-OzNoLinkPath $p)) { throw "A folder on the way to $p is a link." }
        if (-not [IO.Directory]::Exists($p)) { [void][IO.Directory]::CreateDirectory($p) }
    }
    New-OzDockShortcuts -Dir (Join-Path $root '@Resources\Dock\Apps') -Apps @(Get-OzDockApps $Cfg)
    foreach ($f in @($Cfg.WallFolders)) {
        if ($f -and -not [IO.Directory]::Exists($f) -and $f -match 'OZZYHN Wallpapers$' -and (Test-OzNoLinkPath (Split-Path -Parent $f))) {
            [void][IO.Directory]::CreateDirectory($f)
        }
    }
    Write-OzLog ((T 'Theme files written to {0}') -f $root) 'OK'

    if (-not (Start-OzRainmeterUser $rm)) { throw (T 'Rainmeter did not start. Open it from the Start menu, then press APPLY THEME again.') }
    Send-OzRainmeterBang $rm '!RefreshApp'
    Start-Sleep -Milliseconds 1500
    $rm = Get-OzRainmeter
    $want = [ordered]@{ 'OZZYHN\Clock' = $(if ($Cfg.Clock) { "$($Cfg.Style).ini" }); 'OZZYHN\Bar' = $(if ($Cfg.Bar) { 'Bar.ini' }); 'OZZYHN\Dock' = $(if ($Cfg.Dock) { 'Dock.ini' }) }
    $clockNow = Get-OzActiveClockStyle $rm
    foreach ($c in $want.Keys) {
        if ($want[$c]) {
            # Loading a skin that is already loaded makes Rainmeter log a warning, so it is refreshed instead
            $same = $rm.Active.ContainsKey($c) -and ($c -ne 'OZZYHN\Clock' -or "$clockNow.ini" -eq $want[$c])
            if ($same) { Send-OzRainmeterBang $rm '!Refresh' @($c) } else { Send-OzRainmeterBang $rm '!ActivateConfig' @($c, $want[$c]) }
        } elseif ($rm.Active.ContainsKey($c)) { Send-OzRainmeterBang $rm '!DeactivateConfig' @($c) }
    }
    if ($Cfg.HideSamples) { foreach ($c in @($rm.Samples)) { Send-OzRainmeterBang $rm '!DeactivateConfig' @($c) } }
    Save-OzThemeSettings $Cfg
    Write-OzLog (T 'Theme applied.') 'OK'
}

function Remove-OzTheme {
    # Unloads every OZZYHN skin and deletes the OZZYHN skins folder (links inside are never followed)
    $rm = Get-OzRainmeter
    if (-not $rm.Installed) { return }
    $root = Join-Path $rm.SkinPath 'OZZYHN'
    if ($rm.Running) {
        foreach ($c in @($rm.Active.Keys)) { Send-OzRainmeterBang $rm '!DeactivateConfig' @($c) }
        Start-Sleep -Milliseconds 800
    } elseif ($rm.Active.Count -and [IO.File]::Exists($rm.Ini) -and (Test-OzNoLinkPath $rm.Ini)) {
        # Rainmeter is closed: mark the OZZYHN skins as not loaded, so it does not look for them next time
        $lines = [IO.File]::ReadAllLines($rm.Ini)
        $section = ''
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*\[(.+)\]\s*$') { $section = $Matches[1]; continue }
            if ($section -like 'OZZYHN\*' -and $lines[$i] -match '^\s*Active\s*=') { $lines[$i] = 'Active=0' }
        }
        [IO.File]::WriteAllLines($rm.Ini, $lines, [Text.Encoding]::Unicode)
    }
    if ([IO.Directory]::Exists($root)) {
        if (-not (Test-OzNoLinkPath $root)) { throw "$root is a link, so it was not deleted." }
        [void](Clear-OzFolder -Path $root)
        try { [IO.Directory]::Delete($root, $false) } catch { }
    }
    if ($rm.Running) { Send-OzRainmeterBang $rm '!RefreshApp' }
    Write-OzLog (T 'Theme removed. Your wallpaper and your own Rainmeter skins were not touched.') 'OK'
}

function New-OzWallpaperArt {
    # Draws the OZZYHN wallpaper set (original art made here, nothing downloaded) as JPG files.
    # Only files named ozzyhn-*.jpg are ever written. Returns the paths.
    param([string]$Folder, [int]$Width = 2560, [int]$Height = 1440)
    if (-not (Test-OzNoLinkPath $Folder)) { throw "A folder on the way to $Folder is a link, so no wallpapers were written there." }
    if (-not [IO.Directory]::Exists($Folder)) { [void][IO.Directory]::CreateDirectory($Folder) }
    Add-Type -AssemblyName System.Drawing
    $W = $Width; $H = $Height
    $col = { param([string]$hex, [int]$a = 255) $c = [System.Drawing.ColorTranslator]::FromHtml($hex); [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B) }
    $vgrad = {
        param($g, [single]$y0, [single]$y1, $c0, $c1, $rect)
        $b = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF(0, $y0)), (New-Object System.Drawing.PointF(0, $y1)), $c0, $c1)
        $b.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY
        $g.FillRectangle($b, $rect); $b.Dispose()
    }
    $wavePath = {
        # A soft hill line across the screen, closed down to the bottom
        param([double]$base, [double]$amp, [double]$f1, [double]$p1, [double]$f2, [double]$p2, [double]$dy)
        $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($x = -20; $x -le $W + 20; $x += 10) {
            $t = $x / $W
            $y = $base + $dy + $amp * [math]::Sin(2 * [math]::PI * ($t * $f1 + $p1)) + 0.45 * $amp * [math]::Sin(2 * [math]::PI * ($t * $f2 + $p2))
            $pts.Add((New-Object System.Drawing.PointF([single]$x, [single]$y)))
        }
        $pts.Add((New-Object System.Drawing.PointF([single]($W + 20), [single]($H + 20))))
        $pts.Add((New-Object System.Drawing.PointF(-20, [single]($H + 20))))
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddLines($pts.ToArray()); $p.CloseFigure()
        $p
    }
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
    $ep = New-Object System.Drawing.Imaging.EncoderParameters 1
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [int64]95)
    $made = @()
    $designs = 'dunes-light', 'dunes-night', 'neon-horizon', 'crimson-slash', 'arctic-ridges', 'hex-field'
    foreach ($name in $designs) {
        $bmp = New-Object System.Drawing.Bitmap $W, $H
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $all = New-Object System.Drawing.Rectangle 0, 0, $W, $H
        $rnd = New-Object System.Random ($name.Length * 7919)
        try {
            switch ($name) {
                { $_ -in 'dunes-light', 'dunes-night' } {
                    $night = $name -eq 'dunes-night'
                    if ($night) { & $vgrad $g 0 $H (& $col '#1B1C20') (& $col '#08080A') $all }
                    else { & $vgrad $g 0 $H (& $col '#F4F4F4') (& $col '#C9C9C9') $all }
                    for ($k = 0; $k -lt 7; $k++) {
                        $base = $H * (0.40 + $k * 0.085); $amp = $H * (0.035 + 0.01 * $k)
                        $f1 = 0.8 + $rnd.NextDouble() * 0.9; $p1 = $rnd.NextDouble(); $f2 = 1.6 + $rnd.NextDouble() * 1.4; $p2 = $rnd.NextDouble()
                        # soft shadow cast on the hill behind
                        foreach ($s in @(@(26, 10), @(16, 22), @(9, 40))) {
                            $sp = & $wavePath $base $amp $f1 $p1 $f2 $p2 (-$s[1])
                            $sb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($(if ($night) { [int]($s[0] * 1.6) } else { $s[0] }), 0, 0, 0))
                            $g.FillPath($sb, $sp); $sb.Dispose(); $sp.Dispose()
                        }
                        $path = & $wavePath $base $amp $f1 $p1 $f2 $p2 0
                        $top = [single]($base - $amp * 1.5); $bot = [single]($base + $amp * 2.5)
                        if ($night) { $c0 = & $col '#34353B'; $c1 = & $col '#0B0B0D' } else { $c0 = & $col '#FBFBFB'; $c1 = & $col '#A9A9A9' }
                        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF(0, $top)), (New-Object System.Drawing.PointF(0, $bot)), $c0, $c1)
                        $br.WrapMode = [System.Drawing.Drawing2D.WrapMode]::TileFlipXY
                        $g.FillPath($br, $path); $br.Dispose()
                        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($(if ($night) { 40 } else { 120 }), 255, 255, 255)), 2
                        $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
                    }
                }
                'neon-horizon' {
                    & $vgrad $g 0 ($H * 0.62) (& $col '#05070D') (& $col '#1A0626') $all
                    $hy = [single]($H * 0.62)
                    $r = [single]($H * 0.24); $cx = [single]($W / 2); $cy = [single]($hy - $r * 0.35)
                    $sun = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF(0, ($cy - $r))), (New-Object System.Drawing.PointF(0, $hy)), (& $col '#FF2BD6'), (& $col '#FFB020'))
                    $g.SetClip((New-Object System.Drawing.RectangleF(0, 0, $W, $hy)))
                    $g.FillEllipse($sun, $cx - $r, $cy - $r, 2 * $r, 2 * $r); $sun.Dispose()
                    $bg = New-Object System.Drawing.SolidBrush (& $col '#14051F')
                    for ($i = 0; $i -lt 7; $i++) {
                        $yy = $cy + $r * (0.05 + $i * 0.13); $hh = 3 + $i * 3
                        $g.FillRectangle($bg, $cx - $r, [single]$yy, 2 * $r, [single]$hh)
                    }
                    $bg.Dispose(); $g.ResetClip()
                    $floor = New-Object System.Drawing.Rectangle 0, ([int]$hy), $W, ($H - [int]$hy)
                    & $vgrad $g $hy $H (& $col '#0A0214') (& $col '#05070D') $floor
                    foreach ($pass in @(@(60, 7), @(220, 2))) {
                        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb($pass[0], 0, 229, 255)), $pass[1]
                        for ($i = 1; $i -le 14; $i++) { $t = [math]::Pow($i / 14, 2.2); $y = [single]($hy + ($H - $hy) * $t); $g.DrawLine($pen, 0, $y, $W, $y) }
                        for ($i = -16; $i -le 16; $i++) { $g.DrawLine($pen, $cx, $hy, [single]($cx + $i * $W / 9), [single]$H) }
                        $pen.Dispose()
                    }
                    $hz = New-Object System.Drawing.Pen ((& $col '#FF2BD6' 230)), 3
                    $g.DrawLine($hz, 0, $hy, $W, $hy); $hz.Dispose()
                }
                'crimson-slash' {
                    & $vgrad $g 0 $H (& $col '#17171A') (& $col '#0A0A0B') $all
                    $band = New-Object System.Drawing.Drawing2D.GraphicsPath
                    $band.AddPolygon([System.Drawing.PointF[]]@((New-Object System.Drawing.PointF([single]($W * 0.56), 0)), (New-Object System.Drawing.PointF([single]($W * 0.74), 0)), (New-Object System.Drawing.PointF([single]($W * 0.46), [single]$H)), (New-Object System.Drawing.PointF([single]($W * 0.28), [single]$H))))
                    $rb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF(0, 0)), (New-Object System.Drawing.PointF([single]$W, [single]$H)), (& $col '#FF3B50'), (& $col '#5E0612'))
                    $g.FillPath($rb, $band); $rb.Dispose(); $band.Dispose()
                    $pen = New-Object System.Drawing.Pen ((& $col '#FFFFFF' 200)), 2
                    $g.DrawLine($pen, [single]($W * 0.79), 0, [single]($W * 0.51), [single]$H); $pen.Dispose()
                    $pen = New-Object System.Drawing.Pen ((& $col '#FF3B50' 160)), 6
                    $g.DrawLine($pen, [single]($W * 0.22), 0, [single]($W * 0.06), [single]($H * 0.58)); $pen.Dispose()
                }
                'arctic-ridges' {
                    & $vgrad $g 0 ($H * 0.7) (& $col '#E4EEF6') (& $col '#93ABC2') $all
                    $layers = '#B6C8D8', '#8EA6BD', '#667F98', '#3D536B', '#1C2A3A', '#0C141E'
                    for ($k = 0; $k -lt $layers.Count; $k++) {
                        $n = 129; $ys = New-Object double[] $n
                        $ys[0] = 0; $ys[$n - 1] = 0
                        $step = $n - 1; $rough = $H * (0.16 - $k * 0.012)
                        while ($step -gt 1) {
                            $half = [int]($step / 2)
                            for ($i = $half; $i -lt $n; $i += $step) { $ys[$i] = ($ys[$i - $half] + $ys[[math]::Min($n - 1, $i + $half)]) / 2 + ($rnd.NextDouble() - 0.5) * $rough }
                            $rough *= 0.55; $step = $half
                        }
                        $base = $H * (0.45 + $k * 0.085)
                        $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
                        for ($i = 0; $i -lt $n; $i++) { $pts.Add((New-Object System.Drawing.PointF([single]($i * $W / ($n - 1)), [single]($base + $ys[$i] - [math]::Abs($ys[$i]) * 0.6)))) }
                        $pts.Add((New-Object System.Drawing.PointF([single]$W, [single]$H))); $pts.Add((New-Object System.Drawing.PointF(0, [single]$H)))
                        $sb = New-Object System.Drawing.SolidBrush (& $col $layers[$k])
                        $g.FillPolygon($sb, $pts.ToArray()); $sb.Dispose()
                        if ($k -lt $layers.Count - 1) {
                            $mist = New-Object System.Drawing.Rectangle 0, ([int]($base - $H * 0.05)), $W, ([int]($H * 0.18))
                            $mb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF(0, [single]$mist.Top)), (New-Object System.Drawing.PointF(0, [single]$mist.Bottom)), ([System.Drawing.Color]::FromArgb(0, 230, 240, 248)), ([System.Drawing.Color]::FromArgb(70, 230, 240, 248)))
                            $g.FillRectangle($mb, $mist); $mb.Dispose()
                        }
                    }
                }
                'hex-field' {
                    & $vgrad $g 0 $H (& $col '#0D1015') (& $col '#06070A') $all
                    $r = 58.0; $hw = [math]::Sqrt(3) * $r
                    $edge = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 5, 6, 8)), 5
                    $shine = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(22, 255, 255, 255)), 1.5
                    for ($row = -1; $row * 1.5 * $r -lt $H + $r; $row++) {
                        for ($c = -1; $c * $hw -lt $W + $hw; $c++) {
                            $x = $c * $hw + $(if ($row % 2) { $hw / 2 } else { 0 }); $y = $row * 1.5 * $r
                            $pts = [System.Drawing.PointF[]]@(0..5 | ForEach-Object { $a = [math]::PI / 180 * (60 * $_ - 30); New-Object System.Drawing.PointF([single]($x + $r * [math]::Cos($a)), [single]($y + $r * [math]::Sin($a))) })
                            $lift = $rnd.Next(0, 18)
                            $accent = $rnd.NextDouble() -lt 0.025
                            $c0 = if ($accent) { & $col '#00E5FF' 90 } else { [System.Drawing.Color]::FromArgb(255, 28 + $lift, 31 + $lift, 38 + $lift) }
                            $c1 = if ($accent) { & $col '#0B2730' } else { [System.Drawing.Color]::FromArgb(255, 12, 14, 18) }
                            $hb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF([single]($x - $r), [single]($y - $r))), (New-Object System.Drawing.PointF([single]($x + $r), [single]($y + $r))), $c0, $c1)
                            $g.FillPolygon($hb, $pts); $hb.Dispose()
                            $g.DrawPolygon($edge, $pts)
                            $g.DrawLine($shine, $pts[3], $pts[4]); $g.DrawLine($shine, $pts[4], $pts[5])
                        }
                    }
                    $edge.Dispose(); $shine.Dispose()
                }
            }
            $out = Join-Path $Folder ("ozzyhn-$name.jpg")
            if ([IO.File]::Exists($out) -and -not (Test-OzNoLinkPath $out)) { throw "$out is a link." }
            $bmp.Save($out, $codec, $ep)
            $made += $out
        } finally { $g.Dispose(); $bmp.Dispose() }
    }
    $made
}
#endregion

#region ============================ SPANISH ============================
# Spanish UI text. Each entry: the English line, the Spanish line, then a blank line.
# Accents are written as HTML entities (&aacute; = a with accent) so the file stays plain ASCII,
# which is what keeps "irm ... | iex" and Windows PowerShell 5.1 reading it correctly.
$Oz.SpanishPairs = @'
Busy - wait for the current task to finish.
Ocupado: espera a que termine la tarea actual.

{0} failed: {1}
{0} fall&oacute;: {1}

Could not open the link, so it was copied to the clipboard: {0}
No se pudo abrir el enlace, as&iacute; que se copi&oacute; al portapapeles: {0}

Opened console: {0}
Consola abierta: {0}

  task is protected by Windows, skipped: {0}
  Windows protege esta tarea, se omiti&oacute;: {0}

  setting is protected by Windows, skipped: {0}
  Windows protege este ajuste, se omiti&oacute;: {0}

  could not restore {0}
  no se pudo restaurar {0}

  could not re-enable task: {0}
  no se pudo reactivar la tarea: {0}

This PC blocks custom power plans (Modern Standby). The settings were applied to its own plan instead.
Esta PC bloquea los planes de energ&iacute;a personalizados (Modern Standby). Los ajustes se aplicaron a su propio plan.

Restore point already made in this session - reusing it.
Ya se cre&oacute; un punto de restauraci&oacute;n en esta sesi&oacute;n; se reutiliza.

Creating a System Restore point (can take a minute)...
Creando un punto de restauraci&oacute;n del sistema (puede tardar un minuto)...

Using the restore point from {0} ({1}) - it already covers these changes.
Se usa el punto de restauraci&oacute;n del {0} ({1}); ya cubre estos cambios.

Restore point created.
Punto de restauraci&oacute;n creado.

unknown error
error desconocido

Restore point not created ({0}). Changes are still tracked in the undo journal.
No se cre&oacute; el punto de restauraci&oacute;n ({0}). Los cambios siguen guardados en el registro para deshacer.

Virtual machine detected
M&aacute;quina virtual detectada

Hardware-specific tweaks (power plans, NIC, GPU) are skipped automatically. Privacy and debloat work normally.
Los ajustes de hardware (planes de energ&iacute;a, red, GPU) se omiten autom&aacute;ticamente. Privacidad y limpieza de apps funcionan normal.

Windows is on a hard disk (HDD)
Windows est&aacute; en un disco duro (HDD)

This is the #1 slowdown on this PC. Even a basic SATA SSD makes boot and app launches dramatically faster. REVIVE tunes Windows for HDDs until then.
Es la causa n&uacute;mero 1 de lentitud en esta PC. Hasta un SSD SATA b&aacute;sico hace que el arranque y las apps abran much&iacute;simo m&aacute;s r&aacute;pido. REVIVIR ajusta Windows para HDD mientras tanto.

Windows is on slow eMMC storage
Windows est&aacute; en almacenamiento eMMC lento

Keep at least 10 GB free and use CompactOS in TOOLS to free 2-4 GB.
Mant&eacute;n al menos 10 GB libres y usa CompactOS en HERRAMIENTAS para liberar 2-4 GB.

NVMe SSD detected
SSD NVMe detectado

Storage is fast. Tweaks that only help hard disks are not recommended here.
El almacenamiento es r&aacute;pido. Los ajustes que solo ayudan a discos duros no se recomiendan aqu&iacute;.

Only {0} GB of RAM
Solo {0} GB de RAM

Windows will swap constantly. REVIVE trims background apps; adding RAM is the best hardware fix.
Windows usar&aacute; el disco como memoria todo el tiempo. REVIVIR reduce las apps en segundo plano; agregar RAM es la mejor soluci&oacute;n de hardware.

{0} GB of RAM
{0} GB de RAM

Windows feels smooth from 8 GB. REVIVE disables background apps and visual effects to save memory.
Windows va fluido desde 8 GB. REVIVIR desactiva apps en segundo plano y efectos visuales para ahorrar memoria.

Plenty of memory for gaming and multitasking.
Memoria de sobra para jugar y hacer varias cosas a la vez.

RAM is running single-channel
La RAM funciona en un solo canal

Only one memory module is installed. Adding a matching second module doubles memory bandwidth, which is often a big FPS gain on integrated graphics.
Solo hay un m&oacute;dulo de memoria. Agregar un segundo m&oacute;dulo igual duplica el ancho de banda, y suele dar muchos m&aacute;s FPS con gr&aacute;ficos integrados.

RAM runs at {0} MT/s
La RAM funciona a {0} MT/s

If the sticker on your RAM shows a higher speed, enable XMP / EXPO in the BIOS. It is free performance and runs within the kit rating.
Si la etiqueta de tu RAM indica una velocidad mayor, activa XMP / EXPO en la BIOS. Es rendimiento gratis dentro de la especificaci&oacute;n del kit.

Drive {0} is almost full ({1} GB free)
La unidad {0} est&aacute; casi llena ({1} GB libres)

Low free space slows Windows and updates. Use CLEAN UP FILES in TOOLS.
Poco espacio libre vuelve lentos a Windows y a las actualizaciones. Usa LIMPIAR ARCHIVOS en HERRAMIENTAS.

Windows 10 is past end of support
Windows 10 ya no tiene soporte

Standard security updates ended in October 2025. If this PC meets the Windows 11 requirements, upgrading keeps it protected.
Las actualizaciones de seguridad normales terminaron en octubre de 2025. Si esta PC cumple los requisitos de Windows 11, actualizar la mantiene protegida.

Unsupported Windows version
Versi&oacute;n de Windows no compatible

This tool targets Windows 10 and 11. Some features will not work.
Esta herramienta es para Windows 10 y 11. Algunas funciones no van a funcionar.

Memory Integrity (VBS / HVCI) is ON
La integridad de memoria (VBS / HVCI) est&aacute; ACTIVADA

It protects against kernel attacks and costs a few % of FPS in some games. The switch is in the DANGER ZONE - only turn it off if you accept that trade.
Protege contra ataques al kernel y cuesta un poco de FPS en algunos juegos. El interruptor est&aacute; en la ZONA DE PELIGRO: desact&iacute;valo solo si aceptas ese intercambio.

Power Saver plan on a desktop
Plan de ahorro de energ&iacute;a en una PC de escritorio

Your CPU is being held back. Apply the OZZYHN PERFORMANCE plan.
Tu CPU est&aacute; limitada. Aplica el plan OZZYHN RENDIMIENTO.

Laptop detected
Laptop detectada

Use COOL & QUIET for lower temperatures and battery life. MAX PERFORMANCE is best only while plugged in.
Usa FRESCO Y SILENCIOSO para menos temperatura y m&aacute;s bater&iacute;a. M&Aacute;XIMO RENDIMIENTO conviene solo con el cargador conectado.

Battery has {0}% wear
La bater&iacute;a tiene {0}% de desgaste

A worn battery holds less charge and can make some laptops throttle. Consider a replacement.
Una bater&iacute;a desgastada guarda menos carga y puede hacer que algunas laptops bajen su rendimiento. Considera cambiarla.

Graphics driver is {0} days old
El driver de gr&aacute;ficos tiene {0} d&iacute;as

New {0} drivers often fix stutter and add FPS. See the DRIVERS tab for the official download.
Los drivers nuevos de {0} suelen quitar tirones y dar m&aacute;s FPS. Mira la pesta&ntilde;a DRIVERS para la descarga oficial.

{0} apps start with Windows
{0} apps inician con Windows

Each one slows boot and eats RAM. Turn off the ones you do not need in TOOLS > STARTUP APPS.
Cada una hace m&aacute;s lento el arranque y consume RAM. Desactiva las que no necesites en HERRAMIENTAS > APPS DE INICIO.

High-end hardware
Hardware de gama alta

Focus on latency and smoothness: COMPETITIVE GAMING or MAX PERFORMANCE profiles.
Enf&oacute;cate en latencia y fluidez: perfiles GAMING COMPETITIVO o M&Aacute;XIMO RENDIMIENTO.

Revive mode recommended
Se recomienda el modo revivir

Weakest part: {0}. The REVIVE profile strips Windows down so this PC feels usable again.
Parte m&aacute;s d&eacute;bil: {0}. El perfil REVIVIR aligera Windows para que esta PC vuelva a ser usable.

Installed driver {0}. Get the latest Game Ready / Studio driver directly from NVIDIA.
Driver instalado {0}. Descarga el &uacute;ltimo driver Game Ready / Studio directo de NVIDIA.

NVIDIA DRIVERS
DRIVERS NVIDIA

NVCleanstall (optional)
NVCleanstall (opcional)

Installs the NVIDIA driver without telemetry and extras. Good for lean, low-latency setups.
Instala el driver de NVIDIA sin telemetr&iacute;a ni extras. Ideal para equipos ligeros y de baja latencia.

Installed driver {0}. AMD Software: Adrenalin Edition from AMD (auto-detect tool available).
Driver instalado {0}. AMD Software: Adrenalin Edition desde AMD (tiene herramienta de detecci&oacute;n autom&aacute;tica).

AMD DRIVERS
DRIVERS AMD

Installed driver {0}. Intel Driver & Support Assistant finds the right Intel graphics driver.
Driver instalado {0}. Intel Driver & Support Assistant encuentra el driver de gr&aacute;ficos Intel correcto.

Qualcomm graphics drivers are delivered by your laptop maker and Windows Update.
Los drivers de gr&aacute;ficos Qualcomm los entrega el fabricante de tu laptop y Windows Update.

OPTIONAL UPDATES
ACTUALIZACIONES OPCIONALES

Display Driver Uninstaller (clean reinstall)
Display Driver Uninstaller (reinstalaci&oacute;n limpia)

Fixes broken or stuttering GPU drivers by removing every trace before a fresh install. Use it offline, then install the new driver.
Arregla drivers de GPU da&ntilde;ados o con tirones borrando todo rastro antes de una instalaci&oacute;n limpia. &Uacute;salo sin internet y luego instala el driver nuevo.

Intel chipset / ME / Wi-Fi / Bluetooth
Chipset Intel / ME / Wi-Fi / Bluetooth

Intel DSA scans and updates Intel chipset, Management Engine, Wi-Fi and Bluetooth drivers.
Intel DSA revisa y actualiza los drivers de chipset, Management Engine, Wi-Fi y Bluetooth de Intel.

AMD Ryzen chipset driver
Driver de chipset AMD Ryzen

Includes the AMD power plans and scheduler support that Ryzen CPUs need for full boost and correct core parking.
Incluye los planes de energ&iacute;a de AMD y el soporte del planificador que los Ryzen necesitan para el boost completo y el estacionamiento correcto de n&uacute;cleos.

AMD CHIPSET
CHIPSET AMD

Laptops and brand PCs need the maker's drivers for touchpad, hotkeys, audio, fans and power. Always check here first.
Las laptops y PCs de marca necesitan los drivers del fabricante para touchpad, teclas especiales, audio, ventiladores y energ&iacute;a. Revisa aqu&iacute; primero.

SUPPORT PAGE
P&Aacute;GINA DE SOPORTE

BIOS {0}. Board page has LAN, audio and BIOS updates. Newer BIOS can improve RAM stability and CPU support.
BIOS {0}. La p&aacute;gina de la placa tiene actualizaciones de LAN, audio y BIOS. Una BIOS m&aacute;s nueva puede mejorar la estabilidad de la RAM y el soporte de CPU.

BOARD SUPPORT
SOPORTE DE LA PLACA

Intel / Killer network adapters are updated with Intel DSA.
Los adaptadores de red Intel / Killer se actualizan con Intel DSA.

Get this driver from your board or laptop support page (above), or Windows Update optional drivers.
Descarga este driver desde la p&aacute;gina de soporte de tu placa o laptop (arriba), o desde los drivers opcionales de Windows Update.

Windows Update - optional drivers
Windows Update: drivers opcionales

Microsoft-certified drivers for your exact hardware. Safe and easy.
Drivers certificados por Microsoft para tu hardware exacto. Seguro y f&aacute;cil.

OPEN
ABRIR

Scanning drivers and devices...
Analizando drivers y dispositivos...

Reading installed drivers...
Leyendo los drivers instalados...

Checking for devices with problems...
Buscando dispositivos con problemas...

Cleaning temporary files...
Limpiando archivos temporales...

Thumbnail cache
Cach&eacute; de miniaturas

Stopping Windows Update to clear its download cache...
Deteniendo Windows Update para vaciar su cach&eacute; de descargas...

Windows Update downloads
Descargas de Windows Update

Delivery Optimization cache cleared
Cach&eacute; de Optimizaci&oacute;n de distribuci&oacute;n vaciada

{0}: skipped ({1}): {2}
{0}: no se limpi&oacute; ({1}): {2}

not a full path
no es una ruta completa

not a valid path
no es una ruta v&aacute;lida

not on the Windows drive
no est&aacute; en la unidad de Windows

a whole drive
es una unidad completa

not the expected Windows folder
no es la carpeta de Windows esperada

it holds personal or system files
contiene archivos personales o del sistema

it is a link to another place
es un enlace a otro lugar

it could not be checked
no se pudo revisar

Quick clean finished: {0:N0} MB freed.
Limpieza r&aacute;pida terminada: {0:N0} MB liberados.

size unknown
tama&ntilde;o desconocido

Leftovers from installers and apps. Files that are open right now are skipped.
Restos de instaladores y apps. Los archivos abiertos en este momento se saltan.

Leftovers from Windows itself and from installers that ran as administrator.
Restos de Windows y de instaladores que se ejecutaron como administrador.

Update files that are already installed. Windows downloads again anything it still needs.
Archivos de actualizaciones ya instaladas. Windows vuelve a descargar lo que todav&iacute;a necesite.

Delivery Optimization cache
Cach&eacute; de Optimizaci&oacute;n de distribuci&oacute;n

Pieces of updates Windows keeps to share with other PCs.
Partes de actualizaciones que Windows guarda para compartir con otras PCs.

Picture and video previews. Windows makes them again, so big picture folders open slower once.
Vistas previas de fotos y videos. Windows las vuelve a crear, as&iacute; que las carpetas grandes de fotos abren m&aacute;s lento una vez.

Memory dumps from apps that crashed. Only needed to send a crash to the app maker.
Volcados de memoria de apps que se cerraron por un error. Solo sirven para enviar el fallo a quien hizo la app.

Error reports
Informes de errores

Problem reports already sent to Microsoft or waiting to be sent.
Informes de problemas ya enviados a Microsoft o pendientes de enviar.

Cache of Internet Explorer and older apps that still use it. Edge, Chrome and Firefox keep their own.
Cach&eacute; de Internet Explorer y de apps antiguas que todav&iacute;a la usan. Edge, Chrome y Firefox tienen la suya.

Logs from installing Windows updates. Only useful when an update fails.
Registros de la instalaci&oacute;n de actualizaciones de Windows. Solo sirven cuando una actualizaci&oacute;n falla.

Graphics shader caches
Cach&eacute;s de shaders de gr&aacute;ficos

Shaders compiled by DirectX and the graphics driver. Games build them again, so their first launch can stutter.
Shaders compilados por DirectX y el driver de gr&aacute;ficos. Los juegos los vuelven a crear, as&iacute; que su primer inicio puede dar tirones.

Recycle Bin
Papelera de reciclaje

Files you deleted on this drive. Check it first: after this they cannot be brought back.
Archivos que borraste en esta unidad. Rev&iacute;sala primero: despu&eacute;s no se pueden recuperar.

Drive {0} is not a local drive; its Recycle Bin was left alone.
La unidad {0} no es local; su Papelera no se toc&oacute;.

Recycle Bin of drive {0}
Papelera de la unidad {0}

cleared
vaciada

Pick at least one drive.
Elige al menos una unidad.

Measuring what can be cleaned...
Midiendo lo que se puede limpiar...

Cleanup scan of {0}: {1} can be cleaned.
An&aacute;lisis de limpieza de {0}: se pueden limpiar {1}.

Select at least one item to clean.
Selecciona al menos un elemento para limpiar.

Delete these {0} item(s)? This cannot be undone. Files that are open right now are skipped.
&iquest;Borrar estos {0} elemento(s)? No se puede deshacer. Los archivos abiertos en este momento se saltan.

DELETE
BORRAR

Cleaning the selected items...
Limpiando los elementos seleccionados...

Cleanup finished: {0} freed.
Limpieza terminada: {0} liberados.

No local drives found.
No se encontraron unidades locales.

{0}  Windows drive
{0}  Unidad de Windows

{0}  Local drive
{0}  Unidad local

{0:N1} GB free of {1:N1} GB
{0:N1} GB libres de {1:N1} GB

Nothing to clean on the drives you picked.
No hay nada que limpiar en las unidades que elegiste.

Tick what you want to delete. Recommended items that have something to clean are already ticked.
Marca lo que quieres borrar. Los recomendados que tienen algo que limpiar ya est&aacute;n marcados.

{0}  WINDOWS DRIVE
{0}  UNIDAD DE WINDOWS

{0}  OTHER DRIVE  -  only its Recycle Bin can be emptied here, your files are never listed
{0}  OTRA UNIDAD  -  aqu&iacute; solo se puede vaciar su Papelera, tus archivos nunca aparecen

+{0} more
+{0} m&aacute;s

Left alone: {0} ({1})
No se toca: {0} ({1})

nothing to clean
nada que limpiar

Selected: {0} item(s), about {1}
Seleccionado: {0} elemento(s), unos {1}

Pick the drives, then press SCAN to see what can be cleaned on them.
Elige las unidades y presiona ANALIZAR para ver qu&eacute; se puede limpiar en ellas.

CLEAN UP FILES
LIMPIAR ARCHIVOS

Pick the drives, press SCAN, then tick what to delete. Only Windows cache folders and Recycle Bins are listed - never your own files. Recommended items are ticked for you.
Elige las unidades, presiona ANALIZAR y marca lo que quieres borrar. Solo aparecen carpetas de cach&eacute; de Windows y Papeleras, nunca tus archivos. Los recomendados ya vienen marcados.

DRIVES
UNIDADES

SCAN
ANALIZAR

CLEAN SELECTED
LIMPIAR SELECCIONADOS

WINDOWS CLEANUP TOOLS
HERRAMIENTAS DE LIMPIEZA DE WINDOWS

Cleanup scan
An&aacute;lisis de limpieza

Cleanup
Limpieza

No connected network adapter found.
No se encontr&oacute; ning&uacute;n adaptador de red conectado.

Scanning installed apps...
Analizando las apps instaladas...

Removing {0} app(s)...
Quitando {0} app(s)...

Removing {0}
Quitando {0}

could not remove {0}: {1}
no se pudo quitar {0}: {1}

de-provisioned (will not return for new users)
desaprovisionada (no volver&aacute; para usuarios nuevos)

could not de-provision {0}
no se pudo desaprovisionar {0}

Debloat finished.
Limpieza de apps terminada.

Ozzyhn setup
Configuraci&oacute;n de Ozzyhn

Exported {0} active tweaks to {1}
Se exportaron {0} ajustes activos a {1}

Imported setup: {0} tweak(s) staged. Review them and press APPLY CHANGES.
Configuraci&oacute;n importada: {0} ajuste(s) preparados. Rev&iacute;salos y presiona APLICAR CAMBIOS.

Nothing to revert - the undo journal is empty.
Nada que revertir: el registro para deshacer est&aacute; vac&iacute;o.

Search tweaks...
Buscar ajustes...

ADMIN MODE
MODO ADMINISTRADOR

SCANNING HARDWARE...
ANALIZANDO EL HARDWARE...

SCANNING...
ANALIZANDO...

Press SCAN INSTALLED APPS to list removable apps.
Presiona ANALIZAR APPS INSTALADAS para ver las apps que se pueden quitar.

Faster, more private name resolution for every connected adapter.
Resoluci&oacute;n de nombres m&aacute;s r&aacute;pida y privada para cada adaptador conectado.

Language: English
Idioma: espa&ntilde;ol

ON
ACTIVADO

OFF
APAGADO

Entry-level hardware. REVIVE mode strips Windows down so this PC feels fast again.
Hardware b&aacute;sico. El modo REVIVIR aligera Windows para que esta PC se sienta r&aacute;pida otra vez.

Solid everyday machine with room to gain. Auto-Tune removes the overhead holding it back.
Buena PC para el d&iacute;a a d&iacute;a con margen para mejorar. El Auto-Ajuste quita lo que la frena.

Strong hardware. Focus on latency, background noise and smart power for max FPS at sane temps.
Hardware potente. Enf&oacute;cate en latencia, procesos de fondo y energ&iacute;a inteligente para el m&aacute;ximo de FPS con temperaturas sanas.

Enthusiast-class rig. Unlock every frame: competitive latency tweaks and the Performance plan.
Equipo de entusiasta. Saca cada frame: ajustes de latencia competitiva y el plan de Rendimiento.

Weakest part: {0}.
Parte m&aacute;s d&eacute;bil: {0}.

PROCESSOR
PROCESADOR

{0} cores / {1} threads  -  {2:N1} GHz base
{0} n&uacute;cleos / {1} hilos  -  {2:N1} GHz base

Socket {0}  -  Virtualization {1}
Socket {0}  -  Virtualizaci&oacute;n {1}

dedicated
dedicada

integrated
integrada

Driver {0}
Driver {0}

GRAPHICS
GR&Aacute;FICOS

Unknown
Desconocido

soldered
soldada

dual / multi-channel
doble / multicanal

SINGLE-channel
UN SOLO canal

{0} MT/s  -  {1} of {2} slots  -  {3}
{0} MT/s  -  {1} de {2} ranuras  -  {3}

MEMORY
MEMORIA

{0} GB free of {1} GB ({2}%)
{0} GB libres de {1} GB ({2}%)

SYSTEM DRIVE
UNIDAD DEL SISTEMA

BOARD & SYSTEM
PLACA Y SISTEMA

Battery {0}%  -  wear {1}%
Bater&iacute;a {0}%  -  desgaste {1}%

WINDOWS & SECURITY
WINDOWS Y SEGURIDAD

VBS {0}  -  Memory Integrity {1}
VBS {0}  -  Integridad de memoria {1}

Secure Boot {0}  -  TPM {1}
Arranque seguro {0}  -  TPM {1}

none
ninguno

Power plan: {0}
Plan de energ&iacute;a: {0}

GO TO {0}
IR A {0}

Below base clock under load: throttling?
Debajo de la frecuencia base con carga: &iquest;throttling?

base {0:N2} GHz
base {0:N2} GHz

ACPI thermal zone
Zona t&eacute;rmica ACPI

Sensor hidden by firmware. HWiNFO shows exact temps.
El firmware oculta el sensor. HWiNFO muestra las temperaturas exactas.

{0} processes running
{0} procesos en ejecuci&oacute;n

NOTE:
NOTA:

RECOMMENDED
RECOMENDADO

REBOOT
REINICIO

WILL APPLY
SE APLICAR&Aacute;

WILL REVERT
SE REVERTIR&Aacute;

ACTIVE
ACTIVO

CHANGED BACK
REVERTIDO

BLOCKED
BLOQUEADO

Not present on this PC - nothing to change here.
No existe en esta PC: no hay nada que cambiar.

Needs a newer Windows build.
Necesita una versi&oacute;n de Windows m&aacute;s nueva.

Not applicable to this hardware.
No aplica a este hardware.

Something outside the app (Windows, an update or another program) changed this back. Turn it on and apply, or use RE-APPLY below.
Algo fuera de la app (Windows, una actualizaci&oacute;n u otro programa) lo regres&oacute; como estaba. Act&iacute;valo y aplica, o usa REAPLICAR abajo.

Windows did not accept this change on this PC (edition, policy or a protected setting). It is not counted as active.
Windows no acept&oacute; este cambio en esta PC (edici&oacute;n, directiva o ajuste protegido). No se cuenta como activo.

Could not read the current state this time.
No se pudo leer el estado actual esta vez.

{0} change(s) pending   +{1} apply   -{2} revert
{0} cambio(s) pendiente(s)   +{1} aplicar   -{2} revertir

No pending changes
Sin cambios pendientes

RE-APPLY {0} CHANGED BACK
REAPLICAR {0} REVERTIDOS

These trade security for speed or convenience. They are never part of a profile and always ask for confirmation. Only use them if you understand the risk.
Estos cambian seguridad por velocidad o comodidad. Nunca forman parte de un perfil y siempre piden confirmaci&oacute;n. &Uacute;salos solo si entiendes el riesgo.

Reading the real state of every tweak...
Leyendo el estado real de cada ajuste...

No pending changes.
No hay cambios pendientes.

Restarting Explorer to show UI changes...
Reiniciando el Explorador para mostrar los cambios...

Cancelled.
Cancelado.

Applying {0} change(s)...
Aplicando {0} cambio(s)...

Apply
Aplicar

Revert
Revertir

  failed: {0}
  fall&oacute;: {0}

Done: {0} succeeded, {1} failed.
Listo: {0} correctos, {1} fallidos.

Windows did not accept these on this PC, so they stay OFF: {0}
Windows no acept&oacute; estos en esta PC, as&iacute; que siguen APAGADOS: {0}

RECOMMENDED FOR YOUR PC
RECOMENDADO PARA TU PC

PREVIEW
VISTA PREVIA

APPLY {0}
APLICAR {0}

plan: {0}
plan: {0}

{0} tweaks  |  {1} not active yet
{0} ajustes  |  {1} a&uacute;n sin activar

{0}: {1} switch(es) staged. Review them, then press APPLY CHANGES.
{0}: {1} interruptor(es) preparados. Rev&iacute;salos y luego presiona APLICAR CAMBIOS.

{0}: everything in this profile is already active.
{0}: todo lo de este perfil ya est&aacute; activo.

Laptop detected: the Performance plan runs hotter. Use it while plugged in, or switch to COOL & QUIET later.
Laptop detectada: el plan de Rendimiento calienta m&aacute;s. &Uacute;salo con el cargador conectado, o cambia a FRESCO Y SILENCIOSO despu&eacute;s.

A System Restore point is created first.
Primero se crea un punto de restauraci&oacute;n del sistema.

No known bloat found - this Windows is already clean.
No se encontr&oacute; bloatware conocido: este Windows ya est&aacute; limpio.

{0} removable app(s) found. Recommended ones are pre-selected.
Se encontraron {0} app(s) que se pueden quitar. Las recomendadas ya est&aacute;n seleccionadas.

No devices with problems. Every device has a working driver.
No hay dispositivos con problemas. Todos tienen un driver que funciona.

error code {0}
c&oacute;digo de error {0}

Code {0}: {1}
C&oacute;digo {0}: {1}

Driver scan: {0} key drivers, {1} problem device(s).
An&aacute;lisis de drivers: {0} drivers clave, {1} dispositivo(s) con problemas.

Active plan: {0}. PERFORMANCE = max boost, cool idle. SMART = fast + cool (best for laptops). COOL = turbo off, much cooler and quieter.
Plan activo: {0}. RENDIMIENTO = boost m&aacute;ximo, fresco en reposo. INTELIGENTE = r&aacute;pido + fresco (ideal para laptops). FRESCO = turbo apagado, mucho m&aacute;s fresco y silencioso.

Last clean freed {0:N0} MB
La &uacute;ltima limpieza liber&oacute; {0:N0} MB

Now: {0}. Pick a resolver and apply it to every connected adapter.
Ahora: {0}. Elige un DNS y apl&iacute;calo a cada adaptador conectado.

Could not open {0}
No se pudo abrir {0}

No startup apps found.
No se encontraron apps de inicio.

{0} change(s) tracked. Journal file: {1}
{0} cambio(s) registrados. Archivo del registro: {1}

Nothing applied yet. Changes you make will appear here with a one-click revert.
A&uacute;n no se aplic&oacute; nada. Los cambios que hagas aparecer&aacute;n aqu&iacute; con reversi&oacute;n en un clic.

REVERT
REVERTIR

Spec sheet copied to clipboard.
Ficha t&eacute;cnica copiada al portapapeles.

This PC is already fully tuned. Nothing to change.
Esta PC ya est&aacute; totalmente optimizada. No hay nada que cambiar.

{0} recommended switch(es) staged.
{0} interruptor(es) recomendados preparados.

Select at least one app.
Selecciona al menos una app.

Asking Windows to detect new hardware...
Pidiendo a Windows que detecte hardware nuevo...

Hardware detection finished.
Detecci&oacute;n de hardware terminada.

Resetting network stack...
Restableciendo la pila de red...

DNS cache flushed
Cach&eacute; DNS vaciada

Winsock reset
Winsock restablecido

TCP/IP reset
TCP/IP restablecido

Network stack reset. Restart the PC to finish.
Pila de red restablecida. Reinicia la PC para terminar.

Pick a DNS option first.
Primero elige una opci&oacute;n de DNS.

Restore the Windows default power plans? Custom plans (including Ozzyhn ones) are removed.
&iquest;Restaurar los planes de energ&iacute;a predeterminados de Windows? Se borran los planes personalizados (incluidos los de Ozzyhn).

Default power plans restored.
Planes de energ&iacute;a predeterminados restaurados.

No battery on this PC.
Esta PC no tiene bater&iacute;a.

Log copied.
Registro copiado.

Closed.
Cerrado.

Scanning hardware: CPU, GPU, RAM, storage, board, battery...
Analizando el hardware: CPU, GPU, RAM, almacenamiento, placa, bater&iacute;a...

Scanning hardware...
Analizando el hardware...

The hardware scan did not return a result.
El an&aacute;lisis de hardware no devolvi&oacute; resultados.

Detected: {0} | {1} {2} | {3} | {4} | {5} GB {6} | {7}
Detectado: {0} | {1} {2} | {3} | {4} | {5} GB {6} | {7}

no GPU
sin GPU

OZ Score {0}/100 -> {1} (weakest part: {2})
OZ Score {0}/100 -> {1} (parte m&aacute;s d&eacute;bil: {2})

Not present on this PC, so skipped and not counted: {0}
No existen en esta PC, as&iacute; que se omiten y no se cuentan: {0}

Applied before but OFF now (see NEEDS ATTENTION in TWEAKS): {0}
Aplicados antes pero APAGADOS ahora (ver REQUIERE ATENCI&Oacute;N en AJUSTES): {0}

Ready. {0} tweaks loaded, {1} already active on this PC.
Listo. {0} ajustes cargados, {1} ya activos en esta PC.

DNS on '{0}': {1}
DNS en '{0}': {1}

Startup app '{0}' enabled
App de inicio '{0}' activada

Startup app '{0}' disabled
App de inicio '{0}' desactivada

Revert all {0} change(s) made by {1}?\n\nRemoved apps are not reinstalled (get them from the Microsoft Store).
&iquest;Revertir los {0} cambio(s) hechos por {1}?\n\nLas apps quitadas no se reinstalan (desc&aacute;rgalas de Microsoft Store).

You are about to change DANGER ZONE settings:\n\n{0}\n\nThese lower the security of this PC. Continue?
Vas a cambiar ajustes de la ZONA DE PELIGRO:\n\n{0}\n\nReducen la seguridad de esta PC. &iquest;Continuar?

Some changes take effect after a restart.\n\nRestart now?
Algunos cambios se aplican despu&eacute;s de reiniciar.\n\n&iquest;Reiniciar ahora?

Apply {0}?\n\n{1} change(s) will be made on this PC.
&iquest;Aplicar {0}?\n\nSe har&aacute;n {1} cambio(s) en esta PC.

AUTO-TUNE found {0} improvement(s) for this {1} ({2}).\n\nYES  = apply them now (restore point first)\nNO   = show me the list first\nCANCEL = do nothing
AUTO-AJUSTE encontr&oacute; {0} mejora(s) para esta {1} ({2}).\n\nS&Iacute;  = aplicarlas ahora (primero un punto de restauraci&oacute;n)\nNO  = mostrarme la lista primero\nCANCELAR = no hacer nada

Remove these {0} app(s) for all users?\n\n{1}\n\nYou can reinstall them from the Microsoft Store.
&iquest;Quitar estas {0} app(s) para todos los usuarios?\n\n{1}\n\nPuedes reinstalarlas desde Microsoft Store.

Try Microsoft's official Edge uninstall through winget?\n\nThis only works where Microsoft allows it (European Economic Area). WebView2, which other apps need, stays installed.
&iquest;Probar la desinstalaci&oacute;n oficial de Edge de Microsoft con winget?\n\nSolo funciona donde Microsoft lo permite (Espacio Econ&oacute;mico Europeo). WebView2, que otras apps necesitan, se queda instalado.

Reset Winsock, TCP/IP and the DNS cache?\n\nUse this when internet is broken or slow for no reason. A restart is required after.
&iquest;Restablecer Winsock, TCP/IP y la cach&eacute; DNS?\n\n&Uacute;salo cuando internet falla o va lento sin raz&oacute;n. Despu&eacute;s hay que reiniciar.

Disable telemetry
Desactivar telemetr&iacute;a

Stops the Connected User Experiences & Telemetry service and sets diagnostic data to the lowest level your edition allows.
Detiene el servicio de Experiencias del usuario conectado y telemetr&iacute;a, y pone los datos de diagn&oacute;stico en el nivel m&aacute;s bajo que permite tu edici&oacute;n.

Disable telemetry scheduled tasks
Desactivar tareas programadas de telemetr&iacute;a

Turns off the compatibility appraiser, CEIP, disk diagnostics, feedback and error-report upload tasks that wake the PC in the background.
Apaga las tareas de evaluaci&oacute;n de compatibilidad, CEIP, diagn&oacute;stico de disco, comentarios y env&iacute;o de errores que despiertan la PC en segundo plano.

Disable Customer Experience Improvement Program
Desactivar el Programa de mejora de la experiencia del cliente

Opts out of CEIP / SQM usage collection.
Sale de la recolecci&oacute;n de uso de CEIP / SQM.

Disable app-compatibility telemetry
Desactivar la telemetr&iacute;a de compatibilidad de apps

Stops the inventory collector and steps recorder from reporting the apps you use.
Evita que el recolector de inventario y la grabaci&oacute;n de pasos informen qu&eacute; apps usas.

Disable Windows Error Reporting
Desactivar el Informe de errores de Windows

Crashes are no longer packaged and uploaded to Microsoft. Saves disk writes after crashes.
Los cierres inesperados ya no se empaquetan ni se env&iacute;an a Microsoft. Ahorra escrituras en disco.

Disable advertising ID
Desactivar el ID de publicidad

Apps can no longer use a per-user ID to target ads.
Las apps ya no pueden usar un ID por usuario para mostrarte anuncios.

Disable tailored experiences
Desactivar experiencias personalizadas

Microsoft stops using your diagnostic data for personalized tips, ads and recommendations.
Microsoft deja de usar tus datos de diagn&oacute;stico para consejos, anuncios y recomendaciones personalizadas.

Disable activity history
Desactivar el historial de actividad

Windows stops recording and uploading the apps, files and sites you open.
Windows deja de registrar y subir las apps, archivos y sitios que abres.

Stop feedback requests
Detener las solicitudes de comentarios

No more "How likely are you to recommend Windows" pop-ups.
Se acabaron las ventanas de "&iquest;Qu&eacute; tan probable es que recomiendes Windows?".

Disable inking & typing personalization
Desactivar la personalizaci&oacute;n de escritura a mano y teclado

Stops sending typing and handwriting samples to improve recognition.
Deja de enviar muestras de lo que escribes y de tu escritura a mano.

Disable online speech recognition
Desactivar el reconocimiento de voz en l&iacute;nea

Voice is not sent to the cloud. Offline voice typing still works.
Tu voz no se env&iacute;a a la nube. El dictado sin conexi&oacute;n sigue funcionando.

Hide language list from websites
Ocultar tu lista de idiomas a los sitios web

Sites can no longer read your installed language list to fingerprint you.
Los sitios ya no pueden leer tus idiomas instalados para identificarte.

Stop tracking app launches
Dejar de registrar las apps que abres

Windows stops logging which programs you start. Start no longer shows "Most used".
Windows deja de anotar qu&eacute; programas abres. Inicio ya no muestra "M&aacute;s usadas".

Deny location to apps
Negar la ubicaci&oacute;n a las apps

Apps can no longer read your location. Maps, weather and Find My Device lose it.
Las apps ya no pueden leer tu ubicaci&oacute;n. Mapas, el clima y Buscar mi dispositivo la pierden.

Restrict app access to personal data
Restringir el acceso de apps a datos personales

Store apps lose access to account info, contacts, calendar, call history, email, messages, tasks and app diagnostics. Camera and microphone are untouched.
Las apps de la Store pierden acceso a tu cuenta, contactos, calendario, historial de llamadas, correo, mensajes, tareas y diagn&oacute;sticos. La c&aacute;mara y el micr&oacute;fono no se tocan.

Disable cloud clipboard sync
Desactivar la sincronizaci&oacute;n del portapapeles en la nube

Clipboard history stays on this PC and is not synced to other devices.
El historial del portapapeles se queda en esta PC y no se sincroniza con otros dispositivos.

Disable settings sync
Desactivar la sincronizaci&oacute;n de configuraci&oacute;n

Theme, passwords and preferences are no longer synced through your Microsoft account.
El tema, las contrase&ntilde;as y las preferencias ya no se sincronizan con tu cuenta Microsoft.

Disable Copilot in Windows
Desactivar Copilot en Windows

Turns off the Windows Copilot sidebar and hides its taskbar button. Remove the Copilot app in DEBLOAT.
Apaga el panel de Copilot de Windows y oculta su bot&oacute;n en la barra de tareas. Quita la app de Copilot en LIMPIAR APPS.

Disable Recall (screen snapshots)
Desactivar Recall (capturas de pantalla)

Blocks Recall from being enabled and stops AI snapshot analysis (Copilot+ PCs).
Impide que Recall se active y detiene el an&aacute;lisis de capturas con IA (PCs Copilot+).

Disable Click to Do
Desactivar Click to Do

Turns off the AI screen-analysis overlay (Pro / Enterprise honor this policy).
Apaga la capa de an&aacute;lisis de pantalla con IA (Pro / Enterprise respetan esta directiva).

Disable Edge sidebar & Copilot pane
Desactivar la barra lateral de Edge y Copilot

Removes the Edge sidebar (Copilot, Shopping, Tools). Edge may show "managed by your organization".
Quita la barra lateral de Edge (Copilot, Compras, Herramientas). Edge puede mostrar "administrado por tu organizaci&oacute;n".

Visual effects: best performance
Efectos visuales: mejor rendimiento

Turns off animations, fades, shadows and Aero Peek but keeps smooth fonts and thumbnails. Big win on weak GPUs.
Apaga animaciones, transiciones, sombras y Aero Peek, pero mantiene las fuentes suavizadas y las miniaturas. Gran mejora en GPUs d&eacute;biles.

Sign out once for every effect to apply.
Cierra sesi&oacute;n una vez para que se apliquen todos los efectos.

Disable transparency
Desactivar la transparencia

Solid taskbar and Start. Saves GPU work on integrated graphics.
Barra de tareas e Inicio s&oacute;lidos. Ahorra trabajo a la GPU integrada.

Faster menus
Men&uacute;s m&aacute;s r&aacute;pidos

Cuts the menu hover delay from 400 ms to 50 ms. Windows feels snappier.
Baja la espera de los men&uacute;s de 400 ms a 50 ms. Windows se siente m&aacute;s &aacute;gil.

Block background Store apps
Bloquear apps de la Store en segundo plano

Store apps stop running when closed. Saves RAM, CPU and battery.
Las apps de la Store dejan de ejecutarse al cerrarlas. Ahorra RAM, CPU y bater&iacute;a.

Phone Link / Mail notifications only arrive while the app is open.
Las notificaciones de V&iacute;nculo m&oacute;vil / Correo solo llegan con la app abierta.

Remove startup app delay
Quitar la espera de las apps de inicio

Startup apps launch right away instead of waiting ~10 s. Best on SSDs.
Las apps de inicio abren de inmediato en lugar de esperar ~10 s. Mejor en SSD.

Foreground priority boost
Prioridad para la app en primer plano

Locks the scheduler to short, variable quanta with a 3:1 boost for the app you are using (0x26).
Fija el planificador en intervalos cortos y variables con un impulso 3:1 para la app que est&aacute;s usando (0x26).

Disable SysMain (Superfetch)
Desactivar SysMain (Superfetch)

Stops RAM prefetching and its disk activity. Fine on fast NVMe with plenty of RAM.
Detiene la precarga en RAM y su actividad de disco. Bien con NVMe r&aacute;pido y mucha RAM.

Keep ON for hard disks: it makes HDD PCs faster.
D&eacute;jalo ACTIVADO con discos duros: hace m&aacute;s r&aacute;pidas las PCs con HDD.

Disable search indexing
Desactivar la indexaci&oacute;n de b&uacute;squeda

Stops the indexer from grinding the disk. Huge relief on hard disks.
Evita que el indexador sature el disco. Gran alivio en discos duros.

File search in Start and Outlook gets slower.
La b&uacute;squeda de archivos en Inicio y Outlook se vuelve m&aacute;s lenta.

Disable Fault Tolerant Heap
Desactivar Fault Tolerant Heap

Stops Windows from silently slowing down apps that crashed before.
Evita que Windows haga m&aacute;s lentas, sin avisar, las apps que fallaron antes.

Group service host processes
Agrupar los procesos de servicio (svchost)

Raises the svchost split threshold to your RAM size so services share fewer processes (lower process count and overhead).
Sube el l&iacute;mite de divisi&oacute;n de svchost al tama&ntilde;o de tu RAM para que los servicios compartan menos procesos (menos procesos y menos carga).

Disable memory compression
Desactivar la compresi&oacute;n de memoria

Trades RAM for a little CPU time. Only for 16 GB+ PCs.
Cambia RAM por un poco de CPU. Solo para PCs con 16 GB o m&aacute;s.

Keep ON with 8 GB or less: compression helps low-RAM PCs.
D&eacute;jalo ACTIVADO con 8 GB o menos: la compresi&oacute;n ayuda a PCs con poca RAM.

Keep kernel in RAM
Mantener el kernel en RAM

Kernel and drivers are never paged to disk (DisablePagingExecutive). Only for 16 GB+.
El kernel y los drivers nunca se pasan al disco (DisablePagingExecutive). Solo con 16 GB o m&aacute;s.

Global timer resolution requests
Resoluci&oacute;n del temporizador global

Restores pre-Windows 11 behaviour so a timer-resolution request applies system-wide. Only matters if you use a timer tool.
Vuelve al comportamiento anterior a Windows 11 para que una petici&oacute;n de resoluci&oacute;n del temporizador aplique a todo el sistema. Solo importa si usas una herramienta de timer.

Disable dynamic tick
Desactivar el dynamic tick

Keeps the system timer ticking at a steady rate. Can smooth frame pacing on some desktops.
Mantiene el temporizador del sistema a un ritmo constante. Puede suavizar el ritmo de frames en algunas PCs de escritorio.

Suspend BitLocker before changing boot settings. Desktop only.
Suspende BitLocker antes de cambiar opciones de arranque. Solo escritorio.

Game Mode ON
Modo de juego ACTIVADO

Windows prioritizes the game and pauses update installs and notifications while you play.
Windows da prioridad al juego y pausa instalaciones de actualizaciones y notificaciones mientras juegas.

Disable Game DVR background recording
Desactivar la grabaci&oacute;n en segundo plano de Game DVR

Stops the always-on capture buffer that costs FPS and VRAM. Use OBS or your GPU app to record.
Detiene la grabaci&oacute;n continua que cuesta FPS y VRAM. Usa OBS o la app de tu GPU para grabar.

Hide Game Bar startup tips
Ocultar los consejos de la Game Bar

No Game Bar pop-up when a game starts.
Sin ventana de la Game Bar al abrir un juego.

Hardware-accelerated GPU scheduling
Programaci&oacute;n de GPU acelerada por hardware

The GPU manages its own memory queue: lower latency, and required for DLSS Frame Generation.
La GPU maneja su propia cola de memoria: menos latencia, y es necesaria para DLSS Frame Generation.

Multimedia scheduler: games first
Planificador multimedia: juegos primero

Gives games high CPU/GPU/IO priority in MMCSS and lowers the CPU share reserved for background tasks from 20% to 10%.
Da a los juegos prioridad alta de CPU/GPU/IO en MMCSS y baja la CPU reservada para tareas de fondo del 20% al 10%.

Optimizations for windowed games
Optimizaciones para juegos en ventana

Older DX10/11 games in windowed / borderless mode use the low-latency flip model.
Los juegos DX10/11 en ventana o sin bordes usan el modelo flip de baja latencia.

Disable fullscreen optimizations (global)
Desactivar optimizaciones de pantalla completa (global)

Forces true exclusive fullscreen in older games.
Fuerza la pantalla completa exclusiva real en juegos antiguos.

Windows 11 is usually smoother with them ON. Try only if a game stutters or alt-tab misbehaves.
Windows 11 suele ir m&aacute;s fluido con ellas ACTIVADAS. Pru&eacute;balo solo si un juego da tirones o el alt-tab falla.

Raw mouse input (no acceleration)
Mouse sin aceleraci&oacute;n (raw input)

Turns off "Enhance pointer precision" for 1:1 aim.
Desactiva "Mejorar la precisi&oacute;n del puntero" para una punter&iacute;a 1:1.

Disable Sticky / Filter / Toggle key prompts
Desactivar los avisos de Teclas especiales / filtro / alternancia

Pressing Shift 5 times no longer pops a dialog mid-game.
Presionar Shift 5 veces ya no abre una ventana en medio del juego.

OZZYHN PERFORMANCE power plan
Plan de energ&iacute;a OZZYHN RENDIMIENTO

Max boost and unparked cores under load, but 5% minimum state so the CPU idles cool. PCIe/USB/disk power saving off while plugged in.
Boost m&aacute;ximo y n&uacute;cleos activos con carga, pero con 5% de estado m&iacute;nimo para que la CPU est&eacute; fresca en reposo. Ahorro de energ&iacute;a de PCIe/USB/disco apagado con el cargador conectado.

OZZYHN SMART power plan (fast + cool)
Plan de energ&iacute;a OZZYHN INTELIGENTE (r&aacute;pido + fresco)

Efficient-aggressive boost: near full speed when you need it, much less heat and fan noise the rest of the time. Fans spin up before the CPU throttles.
Boost eficiente y agresivo: casi toda la velocidad cuando la necesitas y mucho menos calor y ruido el resto del tiempo. Los ventiladores suben antes de que la CPU baje su velocidad.

Laptop maker apps (Armoury Crate, Vantage, MSI Center...) can switch the plan back. Use their Balanced / Auto mode with this.
Las apps del fabricante (Armoury Crate, Vantage, MSI Center...) pueden regresar el plan. Usa su modo Equilibrado / Auto junto con este.

OZZYHN COOL power plan (turbo off)
Plan de energ&iacute;a OZZYHN FRESCO (turbo apagado)

Disables CPU turbo boost. Load temperatures often drop by 10 C or more and fans calm down, in exchange for lower peak speed. Rescue mode for overheating laptops.
Desactiva el turbo de la CPU. Las temperaturas con carga suelen bajar 10 C o m&aacute;s y los ventiladores se calman, a cambio de menos velocidad m&aacute;xima. Modo rescate para laptops que se calientan.

Disable power throttling
Desactivar la limitaci&oacute;n de energ&iacute;a

Background apps are never forced onto slow efficiency mode. Desktop only - laptops lose battery life.
Las apps en segundo plano nunca se fuerzan al modo de eficiencia lento. Solo escritorio: en laptops se pierde bater&iacute;a.

Disable hibernation
Desactivar la hibernaci&oacute;n

Deletes hiberfil.sys and frees disk space (about 40% of your RAM size). Also disables Fast Startup.
Borra hiberfil.sys y libera espacio en disco (cerca del 40% de tu RAM). Tambi&eacute;n desactiva el Inicio r&aacute;pido.

Disable Fast Startup
Desactivar el Inicio r&aacute;pido

Shut down really shuts down: fixes stale drivers, dual-boot and "uptime never resets" issues.
Apagar realmente apaga: arregla drivers atascados, problemas con arranque dual y el "tiempo activo que nunca se reinicia".

Fax service OFF
Servicio de fax APAGADO

Nobody faxes from a PC.
Nadie manda faxes desde una PC.

Retail Demo service OFF
Servicio de demostraci&oacute;n de tienda APAGADO

Store-display demo mode.
Modo demostraci&oacute;n para exhibici&oacute;n en tiendas.

Downloaded Maps Manager OFF
Administrador de mapas descargados APAGADO

Stops background offline-map updates.
Detiene las actualizaciones de mapas sin conexi&oacute;n en segundo plano.

Media Player network sharing OFF
Uso compartido en red del Reproductor APAGADO

Legacy Windows Media Player library sharing.
Uso compartido de la biblioteca del antiguo Reproductor de Windows Media.

Windows Insider service OFF
Servicio de Windows Insider APAGADO

Only needed for Insider preview builds.
Solo se necesita para las versiones preliminares de Insider.

Diagnostic services OFF
Servicios de diagn&oacute;stico APAGADOS

Diagnostic Policy + Diagnostic hosts. Saves RAM on low-end PCs.
Directiva de diagn&oacute;stico + hosts de diagn&oacute;stico. Ahorra RAM en PCs b&aacute;sicas.

Built-in troubleshooters and network diagnostics stop working.
Los solucionadores de problemas y el diagn&oacute;stico de red dejan de funcionar.

Print Spooler OFF
Cola de impresi&oacute;n APAGADA

Frees RAM and closes the PrintNightmare attack surface.
Libera RAM y cierra la puerta de ataque de PrintNightmare.

You will not be able to print or use "Print to PDF".
No podr&aacute;s imprimir ni usar "Imprimir a PDF".

Xbox Live services OFF
Servicios de Xbox Live APAGADOS

Xbox auth, cloud saves and networking services.
Autenticaci&oacute;n de Xbox, partidas en la nube y servicios de red.

Breaks Game Pass, the Xbox app and achievements.
Rompe Game Pass, la app de Xbox y los logros.

Phone service OFF
Servicio de tel&eacute;fono APAGADO

Telephony for Phone Link calls. Safe on desktops without Phone Link.
Telefon&iacute;a para llamadas de V&iacute;nculo m&oacute;vil. Seguro en PCs de escritorio sin V&iacute;nculo m&oacute;vil.

Geolocation service OFF
Servicio de geolocalizaci&oacute;n APAGADO

No location for any app or Windows feature.
Sin ubicaci&oacute;n para ninguna app ni funci&oacute;n de Windows.

Parental Controls service OFF
Servicio de control parental APAGADO

Only needed for Microsoft Family child accounts.
Solo se necesita para cuentas infantiles de Microsoft Family.

Smart card services OFF
Servicios de tarjeta inteligente APAGADOS

Only used by corporate smart-card logins.
Solo los usan inicios de sesi&oacute;n corporativos con tarjeta inteligente.

Disable network throttling
Desactivar la limitaci&oacute;n de red

Windows stops limiting network packet processing while media plays.
Windows deja de limitar el procesamiento de paquetes de red mientras se reproduce multimedia.

Disable Nagle (TCP no-delay)
Desactivar Nagle (TCP sin retraso)

Sends small TCP packets immediately instead of batching them. Helps TCP-based games and remote desktop.
Env&iacute;a los paquetes TCP peque&ntilde;os de inmediato en lugar de agruparlos. Ayuda a juegos por TCP y al escritorio remoto.

Network adapter never sleeps
El adaptador de red nunca se suspende

Windows can no longer turn off the network card to save power - prevents random disconnects and latency spikes.
Windows ya no puede apagar la tarjeta de red para ahorrar energ&iacute;a: evita desconexiones y picos de latencia.

Disable Ethernet power saving (EEE / Green)
Desactivar el ahorro de energ&iacute;a de Ethernet (EEE / Green)

Turns off Energy-Efficient Ethernet and Green Ethernet, a common cause of ping spikes on Realtek / Intel LAN.
Apaga Energy-Efficient Ethernet y Green Ethernet, causa com&uacute;n de picos de ping en LAN Realtek / Intel.

Faster network file copies
Copias de archivos en red m&aacute;s r&aacute;pidas

Disables SMB bandwidth throttling for large transfers to NAS / other PCs.
Quita la limitaci&oacute;n de ancho de banda SMB en transferencias grandes a NAS u otras PCs.

Stop uploading updates to other PCs
Dejar de subir actualizaciones a otras PCs

Delivery Optimization stops seeding Windows Updates to strangers using your upload bandwidth.
Optimizaci&oacute;n de distribuci&oacute;n deja de compartir actualizaciones de Windows con desconocidos usando tu internet de subida.

Disable Teredo tunneling
Desactivar el t&uacute;nel Teredo

Turns off the IPv6-over-IPv4 tunnel adapter.
Apaga el adaptador de t&uacute;nel IPv6 sobre IPv4.

Xbox app party chat and some P2P games use Teredo.
El chat de grupo de la app de Xbox y algunos juegos P2P usan Teredo.

Classic right-click menu
Men&uacute; contextual cl&aacute;sico

Restores the full Windows 10 context menu - no more "Show more options".
Recupera el men&uacute; contextual completo de Windows 10: sin m&aacute;s "Mostrar m&aacute;s opciones".

Show file extensions
Mostrar las extensiones de archivo

See .exe/.pdf/.lnk. Also protects against "invoice.pdf.exe" tricks.
Ve .exe/.pdf/.lnk. Tambi&eacute;n protege contra trucos como "factura.pdf.exe".

Show hidden files
Mostrar archivos ocultos

Shows hidden files and folders.
Muestra los archivos y carpetas ocultos.

Explorer opens to This PC
El Explorador abre en Este equipo

Instead of Home / Quick access.
En lugar de Inicio / Acceso r&aacute;pido.

Hide recent files in Explorer
Ocultar archivos recientes en el Explorador

Home / Quick access stops listing recent files and frequent folders.
Inicio / Acceso r&aacute;pido deja de mostrar archivos recientes y carpetas frecuentes.

No OneDrive / Microsoft 365 ads in Explorer
Sin anuncios de OneDrive / Microsoft 365 en el Explorador

Removes sync-provider banners in File Explorer.
Quita los avisos de proveedores de sincronizaci&oacute;n en el Explorador de archivos.

Hide Gallery from Explorer
Ocultar Galer&iacute;a en el Explorador

Removes the Gallery entry in the navigation pane.
Quita la entrada Galer&iacute;a del panel de navegaci&oacute;n.

Dark mode
Modo oscuro

Dark theme for Windows and apps.
Tema oscuro para Windows y las apps.

No "- Shortcut" suffix
Sin el sufijo "- Acceso directo"

New shortcuts keep a clean name.
Los accesos directos nuevos conservan un nombre limpio.

Alt+Tab shows windows only
Alt+Tab muestra solo ventanas

Edge tabs no longer flood Alt+Tab.
Las pesta&ntilde;as de Edge ya no llenan el Alt+Tab.

No "suggested" notifications
Sin notificaciones "sugeridas"

Stops Windows suggestion toasts.
Detiene las notificaciones de sugerencias de Windows.

Show seconds in the clock
Mostrar los segundos en el reloj

Taskbar clock shows seconds.
El reloj de la barra de tareas muestra los segundos.

Detailed blue-screen info
Pantalla azul con detalles

Blue screens show the technical parameters - easier to troubleshoot.
Las pantallas azules muestran los par&aacute;metros t&eacute;cnicos: m&aacute;s f&aacute;cil encontrar el problema.

Verbose startup / shutdown messages
Mensajes detallados al iniciar / apagar

See what Windows is doing when boot or shutdown is slow.
Ve qu&eacute; est&aacute; haciendo Windows cuando el arranque o el apagado van lentos.

Num Lock on at sign-in
Bloq Num activado al iniciar sesi&oacute;n

Number pad works on the login screen.
El teclado num&eacute;rico funciona en la pantalla de inicio de sesi&oacute;n.

Faster shutdown
Apagado m&aacute;s r&aacute;pido

Services get 2 s instead of 5 s to stop at shutdown.
Los servicios tienen 2 s en lugar de 5 s para detenerse al apagar.

No Bing web results in Start search
Sin resultados web de Bing en la b&uacute;squeda de Inicio

Start search only finds your apps, files and settings. Faster and private.
La b&uacute;squeda de Inicio solo encuentra tus apps, archivos y configuraci&oacute;n. M&aacute;s r&aacute;pida y privada.

Disable Cortana
Desactivar Cortana

Turns off the retired Cortana assistant.
Apaga el asistente Cortana, ya retirado.

No search highlights
Sin destacados en la b&uacute;squeda

Removes trending doodles and news from the search box.
Quita las im&aacute;genes y noticias de tendencia del cuadro de b&uacute;squeda.

No cloud content in search
Sin contenido de la nube en la b&uacute;squeda

Search stops looking in OneDrive / Outlook / work accounts.
La b&uacute;squeda deja de buscar en OneDrive / Outlook / cuentas de trabajo.

Disable Widgets / News and Interests
Desactivar Widgets / Noticias e intereses

Removes the weather/news panel and its background web process (saves 100-300 MB RAM).
Quita el panel de clima/noticias y su proceso web en segundo plano (ahorra 100-300 MB de RAM).

Remove Chat / Teams taskbar icon
Quitar el &iacute;cono de Chat / Teams de la barra de tareas

Hides the consumer Teams Chat button.
Oculta el bot&oacute;n de Chat de Teams personal.

Hide Task View button
Ocultar el bot&oacute;n Vista de tareas

Win+Tab still works.
Win+Tab sigue funcionando.

Left-aligned taskbar
Barra de tareas alineada a la izquierda

Classic Start button position on Windows 11.
Posici&oacute;n cl&aacute;sica del bot&oacute;n Inicio en Windows 11.

Search box as icon only
B&uacute;squeda solo como &iacute;cono

Saves taskbar space.
Ahorra espacio en la barra de tareas.

"End task" on taskbar right-click
"Finalizar tarea" al hacer clic derecho en la barra de tareas

Kill frozen apps without Task Manager.
Cierra apps congeladas sin el Administrador de tareas.

Clean Start menu (no recommendations)
Men&uacute; Inicio limpio (sin recomendaciones)

Removes promoted apps, tips and account nags from Start.
Quita apps promocionadas, consejos y avisos de cuenta del men&uacute; Inicio.

No suggested / auto-installed apps
Sin apps sugeridas / instaladas solas

Stops Windows from silently installing Candy Crush-style apps and showing app suggestions.
Evita que Windows instale sin avisar apps tipo Candy Crush y que muestre sugerencias de apps.

No tips, tricks and "finish setup" nags
Sin consejos, trucos ni avisos de "terminar la configuraci&oacute;n"

Removes Windows tips, Settings suggestions, the welcome experience and the "Let's finish setting up" screen.
Quita los consejos de Windows, las sugerencias de Configuraci&oacute;n, la experiencia de bienvenida y la pantalla "Terminemos de configurar".

No lock-screen ads and "fun facts"
Sin anuncios ni "datos curiosos" en la pantalla de bloqueo

Keeps your lock screen clean.
Mantiene limpia tu pantalla de bloqueo.

Edge: no startup boost / background mode
Edge: sin aumento de inicio ni modo en segundo plano

Edge stops pre-loading at sign-in and running after you close it. Frees RAM and CPU.
Edge deja de precargarse al iniciar sesi&oacute;n y de seguir abierto al cerrarlo. Libera RAM y CPU.

Edge: no nags, shopping or recommendations
Edge: sin avisos, compras ni recomendaciones

Skips first-run, default-browser prompts, shopping assistant and recommendations.
Omite la primera configuraci&oacute;n, los avisos de navegador predeterminado, el asistente de compras y las recomendaciones.

Edge will show "managed by your organization" (normal for policies).
Edge mostrar&aacute; "administrado por tu organizaci&oacute;n" (normal con directivas).

Edge: minimum diagnostic data
Edge: datos de diagn&oacute;stico m&iacute;nimos

Edge sends only required diagnostic data.
Edge env&iacute;a solo los datos de diagn&oacute;stico obligatorios.

Edge updater services to Manual
Servicios de actualizaci&oacute;n de Edge en Manual

Edge still updates, just without two always-on services.
Edge se sigue actualizando, solo que sin dos servicios siempre activos.

Edge resets these when it updates itself. The app flags it when that happens.
Edge los restablece cuando se actualiza. La app te avisa cuando pasa.

Store apps do not auto-update
Las apps de la Store no se actualizan solas

No surprise downloads hogging the disk and network. Update from the Store when you choose.
Sin descargas sorpresa que saturen el disco y la red. Actualiza desde la Store cuando quieras.

Uninstall OneDrive
Desinstalar OneDrive

Removes the OneDrive app and its startup entry. Turn this switch back on to reinstall it.
Quita la app de OneDrive y su entrada de inicio. Vuelve a activar este interruptor para reinstalarla.

Turn off "Back up folders" in OneDrive first. Your files stay in your user folder.
Primero desactiva "Copia de seguridad de carpetas" en OneDrive. Tus archivos se quedan en tu carpeta de usuario.

Block OneDrive from syncing
Bloquear la sincronizaci&oacute;n de OneDrive

Prevents OneDrive from running even if it is reinstalled by an update.
Impide que OneDrive se ejecute aunque una actualizaci&oacute;n lo reinstale.

Never auto-restart while signed in
Nunca reiniciar solo con la sesi&oacute;n iniciada

Updates still install, but Windows will not reboot your PC in the middle of a game or render.
Las actualizaciones se instalan igual, pero Windows no reiniciar&aacute; tu PC en medio de un juego o un render.

Do not get drivers from Windows Update
No recibir drivers por Windows Update

Stops Windows from replacing the GPU / chipset drivers you installed yourself.
Evita que Windows reemplace los drivers de GPU / chipset que instalaste t&uacute;.

You must keep drivers updated yourself (see DRIVERS).
Tendr&aacute;s que mantener los drivers actualizados t&uacute; mismo (ver DRIVERS).

Ask before downloading updates
Preguntar antes de descargar actualizaciones

Windows notifies you instead of downloading in the background - good on slow or metered internet.
Windows te avisa en lugar de descargar en segundo plano: bueno con internet lento o de uso medido.

Remember to install security updates.
Recuerda instalar las actualizaciones de seguridad.

Delay feature updates 1 year
Retrasar las actualizaciones de funciones 1 a&ntilde;o

Security updates keep coming; big version upgrades wait until they are stable (Pro / Enterprise).
Las actualizaciones de seguridad siguen llegando; las versiones grandes esperan a ser estables (Pro / Enterprise).

Skip the monthly Malicious Software Removal Tool
Omitir la Herramienta de eliminaci&oacute;n de software malintencionado mensual

Saves a monthly download and scan if you already use Defender or another antivirus.
Ahorra una descarga y un an&aacute;lisis cada mes si ya usas Defender u otro antivirus.

Disable NTFS last-access timestamps
Desactivar la marca de &uacute;ltimo acceso de NTFS

Reading a file no longer triggers a disk write. Less I/O on every drive.
Leer un archivo ya no provoca una escritura en disco. Menos E/S en cada unidad.

Disable 8.3 short file names
Desactivar los nombres cortos 8.3

NTFS stops creating legacy DOS names for every new file - faster in big folders.
NTFS deja de crear nombres DOS antiguos para cada archivo nuevo: m&aacute;s r&aacute;pido en carpetas grandes.

More RAM for NTFS cache
M&aacute;s RAM para la cach&eacute; de NTFS

Lets NTFS use more paged pool for file metadata. Speeds up heavy file work on 16 GB+.
Deja que NTFS use m&aacute;s memoria para los metadatos de archivos. Acelera el trabajo pesado con archivos en 16 GB o m&aacute;s.

Enable long file paths
Activar las rutas de archivo largas

Apps can use paths longer than 260 characters (fixes many dev-tool and game-mod errors).
Las apps pueden usar rutas de m&aacute;s de 260 caracteres (arregla muchos errores de herramientas de desarrollo y mods).

Make sure SSD TRIM is ON
Asegurar que TRIM del SSD est&eacute; ACTIVADO

TRIM keeps SSDs fast over time. This guarantees it was not disabled.
TRIM mantiene r&aacute;pidos los SSD con el tiempo. Esto garantiza que no est&eacute; desactivado.

Storage Sense ON
Sensor de almacenamiento ACTIVADO

Windows cleans temp files and the recycle bin automatically when space runs low.
Windows limpia los temporales y la papelera autom&aacute;ticamente cuando queda poco espacio.

Disable SMBv1
Desactivar SMBv1

The protocol WannaCry used. Modern Windows does not need it.
El protocolo que us&oacute; WannaCry. Windows moderno no lo necesita.

Very old NAS boxes may need SMBv1.
Algunos NAS muy antiguos pueden necesitar SMBv1.

Disable LLMNR
Desactivar LLMNR

Blocks a legacy name-resolution protocol that attackers abuse on public Wi-Fi.
Bloquea un protocolo antiguo de resoluci&oacute;n de nombres que los atacantes aprovechan en Wi-Fi p&uacute;blicas.

Restrict anonymous SAM / share access
Restringir el acceso an&oacute;nimo a SAM / recursos compartidos

Anonymous users cannot list accounts or shares on this PC.
Los usuarios an&oacute;nimos no pueden ver las cuentas ni los recursos compartidos de esta PC.

Disable NetBIOS over TCP/IP
Desactivar NetBIOS sobre TCP/IP

Closes ports 137-139 on every adapter.
Cierra los puertos 137-139 en cada adaptador.

Very old NAS / printers found by NetBIOS name may need their IP instead.
Los NAS / impresoras muy antiguos que se encuentran por nombre NetBIOS quiz&aacute; necesiten su IP.

Disable AutoRun on all drives
Desactivar la reproducci&oacute;n autom&aacute;tica en todas las unidades

USB sticks and discs can no longer launch programs automatically.
Las memorias USB y los discos ya no pueden abrir programas solos.

Disable Remote Assistance
Desactivar la Asistencia remota

Closes the legacy "invite someone to help you" door. Quick Assist still works.
Cierra la antigua puerta de "invitar a alguien para que te ayude". Asistencia r&aacute;pida sigue funcionando.

Fewer non-critical security notifications
Menos notificaciones de seguridad no cr&iacute;ticas

Hides "summary" and informational Windows Security toasts. Threat alerts still show.
Oculta los avisos de "resumen" e informativos de Seguridad de Windows. Las alertas de amenazas siguen apareciendo.

Turn off Defender real-time protection
Apagar la protecci&oacute;n en tiempo real de Defender

Stops on-access scanning. Only do this if you install another antivirus or the PC is offline.
Detiene el an&aacute;lisis al abrir archivos. Hazlo solo si instalas otro antivirus o la PC no tiene internet.

Turn OFF Tamper Protection in Windows Security first, or Windows blocks this.
Primero APAGA la Protecci&oacute;n contra alteraciones en Seguridad de Windows, o Windows lo bloquea.

Disable SmartScreen
Desactivar SmartScreen

No more "Windows protected your PC" for unknown downloads. You lose phishing and malware URL checks.
Se acaba el "Windows protegi&oacute; tu PC" con descargas desconocidas. Pierdes la revisi&oacute;n de enlaces de phishing y malware.

Turn off Memory Integrity (HVCI)
Apagar la integridad de memoria (HVCI)

Can return a few % FPS in some games. Removes protection against malicious kernel drivers.
Puede devolver un poco de FPS en algunos juegos. Quita la protecci&oacute;n contra drivers de kernel maliciosos.

Turn off Virtualization-Based Security
Apagar la seguridad basada en virtualizaci&oacute;n

Disables VBS entirely (HVCI, Credential Guard). Some PCs lock VBS on in firmware and ignore this.
Desactiva VBS por completo (HVCI, Credential Guard). Algunas PCs fijan VBS en el firmware e ignoran esto.

Disable Spectre / Meltdown mitigations
Desactivar las mitigaciones de Spectre / Meltdown

Mostly helps older Intel CPUs (pre-9th gen) in I/O-heavy work. Exposes the CPU to side-channel attacks.
Ayuda sobre todo a CPUs Intel antiguas (antes de 9.a gen.) con mucha E/S. Expone la CPU a ataques de canal lateral.

PRIVACY & TELEMETRY
PRIVACIDAD Y TELEMETR&Iacute;A

AI & COPILOT
IA Y COPILOT

PERFORMANCE
RENDIMIENTO

GAMING & INPUT
GAMING Y CONTROLES

POWER & THERMALS
ENERG&Iacute;A Y TEMPERATURA

SERVICES
SERVICIOS

NETWORK & LATENCY
RED Y LATENCIA

EXPLORER & UI
EXPLORADOR E INTERFAZ

START, TASKBAR & SEARCH
INICIO, BARRA DE TAREAS Y B&Uacute;SQUEDA

EDGE, ONEDRIVE & STORE
EDGE, ONEDRIVE Y STORE

WINDOWS UPDATE
WINDOWS UPDATE

STORAGE & NTFS
ALMACENAMIENTO Y NTFS

SECURITY HARDENING
REFUERZO DE SEGURIDAD

DANGER ZONE
ZONA DE PELIGRO

AUTO-TUNE THIS PC
AUTO-AJUSTAR ESTA PC

REVIVE CHEAP PC
REVIVIR PC BARATA

MAX PERFORMANCE
M&Aacute;XIMO RENDIMIENTO

COOL & QUIET
FRESCO Y SILENCIOSO

COMPETITIVE GAMING
GAMING COMPETITIVO

PRIVACY MAX
PRIVACIDAD M&Aacute;XIMA

CLEAN WINDOWS UI
WINDOWS LIMPIO

Built from your scan
Hecho a partir de tu an&aacute;lisis

Old, low-RAM or HDD machines
PCs viejas, con poca RAM o con HDD

Desktops / laptops on AC
Escritorio / laptops con cargador

Hot laptops, silent PCs, battery
Laptops calientes, PCs silenciosas, bater&iacute;a

Lowest input lag and ping
El menor input lag y ping

Minimum data leaves this PC
El m&iacute;nimo de datos sale de esta PC

Declutter Start, taskbar and Explorer
Ordena Inicio, la barra de tareas y el Explorador

Everything recommended for this exact machine: its tier, desktop or laptop, SSD or HDD, GPU and Windows version. Safe and fully reversible.
Todo lo recomendado para esta PC exacta: su gama, escritorio o laptop, SSD o HDD, GPU y versi&oacute;n de Windows. Seguro y totalmente reversible.

Strips Windows down: no animations, no background apps, no bloat services, no web junk in search. Makes 4-8 GB and hard-disk PCs usable again.
Aligera Windows: sin animaciones, sin apps en segundo plano, sin servicios in&uacute;tiles, sin basura web en la b&uacute;squeda. Hace usables otra vez las PCs con 4-8 GB y disco duro.

Every CPU core unparked, aggressive boost, games first in the scheduler, GPU scheduling on, background noise removed. Idle stays cool (5% minimum CPU state).
Todos los n&uacute;cleos activos, boost agresivo, juegos primero en el planificador, programaci&oacute;n de GPU activada y sin ruido de fondo. En reposo se mantiene fresca (5% de estado m&iacute;nimo de CPU).

Turbo-off cool plan on laptops (smart plan on desktops), fewer background processes and no surprise downloads. Lower temps, quieter fans, longer battery.
Plan fresco sin turbo en laptops (plan inteligente en escritorio), menos procesos de fondo y sin descargas sorpresa. Menos temperatura, ventiladores m&aacute;s silenciosos y m&aacute;s bater&iacute;a.

MAX PERFORMANCE plus raw mouse input, no sticky-key pop-ups, TCP no-delay, network card never sleeps, Ethernet power saving off and flip-model for windowed games.
M&Aacute;XIMO RENDIMIENTO m&aacute;s mouse sin aceleraci&oacute;n, sin avisos de teclas especiales, TCP sin retraso, tarjeta de red sin suspensi&oacute;n, sin ahorro de energ&iacute;a en Ethernet y modelo flip para juegos en ventana.

All privacy, telemetry and AI switches, no cloud search, app permissions locked down, no sync, no ads anywhere. Camera and microphone are left for you to decide.
Todos los interruptores de privacidad, telemetr&iacute;a e IA, sin b&uacute;squeda en la nube, permisos de apps cerrados, sin sincronizaci&oacute;n y sin anuncios. La c&aacute;mara y el micr&oacute;fono quedan a tu elecci&oacute;n.

Microsoft News
Microsoft Noticias

Weather
El Tiempo

Money
Dinero

Sports
Deportes

Get Help
Obtener ayuda

Tips
Consejos

3D Viewer
Visor 3D

Solitaire Collection
Solitaire Collection

Mixed Reality Portal
Portal de realidad mixta

People
Contactos

Feedback Hub
Centro de opiniones

Maps
Mapas

Mail and Calendar (retired)
Correo y Calendario (retirado)

Outlook (new)
Outlook (nuevo)

Movies & TV
Pel&iacute;culas y TV

Copilot app
App de Copilot

Copilot provider
Proveedor de Copilot

Widgets Platform Runtime
Plataforma de Widgets

Teams (personal, old)
Teams (personal, antiguo)

Family Safety
Protecci&oacute;n infantil

Advertising SDK
SDK de publicidad

Sticky Notes
Notas r&aacute;pidas

Clock / Alarms
Reloj / Alarmas

Camera
C&aacute;mara

Sound Recorder
Grabadora de sonido

Media Player
Reproductor multimedia

Photos
Fotos

Phone Link
V&iacute;nculo m&oacute;vil

Quick Assist
Asistencia r&aacute;pida

Start Experiences
Experiencias de Inicio

Xbox app
App de Xbox

Xbox speech-to-text
Voz a texto de Xbox

Xbox Identity (needed for Xbox sign-in in games)
Identidad de Xbox (necesaria para iniciar sesi&oacute;n de Xbox en juegos)

Candy Crush and other King games
Candy Crush y otros juegos de King

McAfee trial
Prueba de McAfee

Automatic (router / ISP)
Autom&aacute;tico (router / proveedor)

Quad9 (blocks malware)
Quad9 (bloquea malware)

AdGuard (blocks ads)
AdGuard (bloquea anuncios)

Device Manager
Administrador de dispositivos

Services
Servicios

Task Manager
Administrador de tareas

System Config
Configuraci&oacute;n del sistema

Programs
Programas

Power Options
Opciones de energ&iacute;a

Network
Red

System Properties
Propiedades del sistema

Disk Management
Administraci&oacute;n de discos

Event Viewer
Visor de eventos

Resource Monitor
Monitor de recursos

Windows Security
Seguridad de Windows

not configured
sin configurar

driver may be corrupted
el driver puede estar da&ntilde;ado

cannot start
no puede iniciar

resource conflict
conflicto de recursos

needs restart
necesita reiniciar

reinstall driver
reinstalar el driver

disabled
deshabilitado

not present / no driver
no presente / sin driver

driver NOT installed
driver NO instalado

not working
no funciona

driver corrupted or missing
driver da&ntilde;ado o faltante

device reported a problem
el dispositivo inform&oacute; un problema

unsigned driver blocked
driver sin firma bloqueado

Your temp folder
Tu carpeta temporal

Windows temp
Temporales de Windows

Crash dumps
Volcados de errores

Error reports (archive)
Informes de errores (archivo)

Error reports (queue)
Informes de errores (cola)

Legacy web cache
Cach&eacute; web antigua

Servicing logs
Registros de mantenimiento

Driver scan
An&aacute;lisis de drivers

App scan
An&aacute;lisis de apps

Profile preview
Vista previa del perfil

Profile apply
Aplicar perfil

Startup app
App de inicio

Rescan
Volver a analizar

Auto-tune
Auto-ajuste

Re-apply
Reaplicar

Debloat
Limpiar apps

Hardware scan
An&aacute;lisis de hardware

Quick clean
Limpieza r&aacute;pida

Network reset
Restablecer la red

Plan
Plan

Reset plans
Restablecer planes

Startup
Inicio

Restore point
Punto de restauraci&oacute;n

Export
Exportar

Import
Importar

Revert all
Revertir todo

CHEAP  /  REVIVE MODE
BARATA  /  MODO REVIVIR

BUDGET
ECON&Oacute;MICA

MID-RANGE
GAMA MEDIA

FANCY  /  HIGH-END
GAMA ALTA

Desktop
Escritorio

Laptop
Laptop

Virtual Machine
M&aacute;quina virtual

Storage
Almacenamiento

SAFE
SEGURO

MODERATE
MODERADO

ADVANCED
AVANZADO

DANGER
PELIGRO

User
Usuario

All users
Todos los usuarios

All users (32-bit)
Todos los usuarios (32 bits)

User folder
Carpeta del usuario

All users folder
Carpeta de todos los usuarios

Board
Placa

PROFILES
PERFILES

TOOLS
HERRAMIENTAS

TWEAKS
AJUSTES

DRIVERS
DRIVERS

ALL
TODOS

PENDING
PENDIENTES

NEEDS ATTENTION
REQUIERE ATENCI&Oacute;N

OZZYHN TWEAKS  //  CONTROL DECK
OZZYHN TWEAKS  //  CENTRO DE CONTROL

CONTROL DECK
CENTRO DE CONTROL

Dashboard
Panel

Tweaks
Ajustes

Profiles
Perfiles

Drivers
Drivers

Tools
Herramientas

Backup & Undo
Respaldo y deshacer

Log
Registro

TWEAKS ACTIVE
AJUSTES ACTIVOS

SYSTEM CLASS
CLASE DE SISTEMA

STORAGE
ALMACENAMIENTO

RESCAN HARDWARE
VOLVER A ANALIZAR

COPY SPEC SHEET
COPIAR FICHA T&Eacute;CNICA

CPU LOAD
CARGA DE CPU

CPU CLOCK
FRECUENCIA DE CPU

TEMPERATURE
TEMPERATURA

UPTIME / PROCESSES
TIEMPO ACTIVO / PROCESOS

SMART INSIGHTS FOR THIS PC
RECOMENDACIONES PARA ESTA PC

Every switch shows the REAL state read from Windows right now. Flip what you want, then APPLY. Everything is logged and reversible.
Cada interruptor muestra el estado REAL le&iacute;do de Windows ahora mismo. Cambia lo que quieras y luego APLICA. Todo queda registrado y se puede deshacer.

Create a System Restore point before applying
Crear un punto de restauraci&oacute;n antes de aplicar

RE-APPLY
REAPLICAR

SELECT RECOMMENDED
SELECCIONAR RECOMENDADOS

UNDO SELECTION
DESHACER SELECCI&Oacute;N

APPLY CHANGES
APLICAR CAMBIOS

One click, tuned to what was detected on this PC. PREVIEW stages the switches so you can review them first; APPLY does it now. Danger Zone items are never included.
Un clic, ajustado a lo que se detect&oacute; en esta PC. VISTA PREVIA prepara los interruptores para que los revises primero; APLICAR lo hace ahora. Nunca incluyen la Zona de peligro.

DEBLOAT
LIMPIAR APPS

Only apps actually installed on this PC are listed. Core Windows apps (Store, Calculator, Notepad, Terminal, Security) are protected and never shown. Removed apps can be reinstalled from the Microsoft Store.
Solo se muestran las apps instaladas en esta PC. Las apps esenciales de Windows (Store, Calculadora, Bloc de notas, Terminal, Seguridad) est&aacute;n protegidas y nunca aparecen. Las apps quitadas se pueden reinstalar desde Microsoft Store.

SCAN INSTALLED APPS
ANALIZAR APPS INSTALADAS

SELECT NONE
NO SELECCIONAR NINGUNA

REMOVE SELECTED
QUITAR SELECCIONADAS

TRY OFFICIAL EDGE UNINSTALL
PROBAR LA DESINSTALACI&Oacute;N OFICIAL DE EDGE

Uses winget. Works only where Microsoft allows it (EEA). WebView2 stays installed.
Usa winget. Solo funciona donde Microsoft lo permite (EEE). WebView2 se queda instalado.

Recommendations come from the hardware found on this PC and always point to the official source - never to driver-updater junkware.
Las recomendaciones salen del hardware de esta PC y siempre llevan a la fuente oficial, nunca a programas basura de "actualizar drivers".

SCAN DRIVERS & DEVICES
ANALIZAR DRIVERS Y DISPOSITIVOS

DEVICE MANAGER
ADMINISTRADOR DE DISPOSITIVOS

DETECT NEW HARDWARE
DETECTAR HARDWARE NUEVO

RECOMMENDED DOWNLOADS
DESCARGAS RECOMENDADAS

DEVICES WITH PROBLEMS
DISPOSITIVOS CON PROBLEMAS

INSTALLED KEY DRIVERS
DRIVERS CLAVE INSTALADOS

Cleanup, repair, DNS, power, storage and startup control. Long built-in tools open in their own window so you can watch them.
Limpieza, reparaci&oacute;n, DNS, energ&iacute;a, almacenamiento y control de inicio. Las herramientas largas de Windows abren en su propia ventana para que veas el progreso.

CLEANUP
LIMPIEZA

Windows' own cleaners. DEEP CLEAN removes old update files that Windows keeps in its component store. DISK CLEANUP opens the classic tool.
Los limpiadores propios de Windows. LIMPIEZA PROFUNDA quita archivos viejos de actualizaciones que Windows guarda en su almac&eacute;n de componentes. LIBERADOR DE ESPACIO abre la herramienta cl&aacute;sica.

QUICK CLEAN
LIMPIEZA R&Aacute;PIDA

DEEP CLEAN (DISM)
LIMPIEZA PROFUNDA (DISM)

DISK CLEANUP
LIBERADOR DE ESPACIO

REPAIR WINDOWS
REPARAR WINDOWS

Fix corrupted system files, broken networking and disk errors - the classic toolkit for a PC that acts weird.
Arregla archivos del sistema da&ntilde;ados, la red rota y errores de disco: el kit cl&aacute;sico para una PC que se porta raro.

DISM + SFC REPAIR
REPARAR CON DISM + SFC

RESET NETWORK STACK
RESTABLECER LA RED

SCAN DISK
ANALIZAR DISCO

APPLY DNS
APLICAR DNS

SMART
INTELIGENTE

COOL
FRESCO

RESET PLANS
RESTABLECER PLANES

BATTERY REPORT
REPORTE DE BATER&Iacute;A

CompactOS compresses Windows itself and frees 2-4 GB - a lifesaver on 32/64 GB eMMC laptops. Slight CPU cost when loading files.
CompactOS comprime el propio Windows y libera 2-4 GB: salvavidas en laptops con eMMC de 32/64 GB. Usa un poco m&aacute;s de CPU al abrir archivos.

COMPACT OS ON
COMPACT OS ACTIVADO

COMPACT OS OFF
COMPACT OS APAGADO

OPTIMIZE DRIVES
OPTIMIZAR UNIDADES

WINDOWS SHORTCUTS
ACCESOS DE WINDOWS

Jump straight into the classic control panels.
Abre directo los paneles de control cl&aacute;sicos.

STARTUP APPS
APPS DE INICIO

Switch off what you do not need at boot. Same mechanism as Task Manager, so nothing is deleted.
Apaga lo que no necesitas al arrancar. Es el mismo mecanismo del Administrador de tareas, as&iacute; que no se borra nada.

REFRESH
ACTUALIZAR

BACKUP & UNDO
RESPALDO Y DESHACER

Before any value is changed, its original is saved to an undo journal. Revert one tweak, or everything, at any time - even after updates or reinstalling this tool.
Antes de cambiar cualquier valor, el original se guarda en un registro para deshacer. Revierte un ajuste o todos cuando quieras, incluso despu&eacute;s de actualizaciones o de reinstalar esta herramienta.

SYSTEM RESTORE
RESTAURAR SISTEMA

A full Windows snapshot of system settings and drivers.
Una copia completa de la configuraci&oacute;n del sistema y los drivers de Windows.

CREATE RESTORE POINT
CREAR PUNTO DE RESTAURACI&Oacute;N

OPEN SYSTEM RESTORE
ABRIR RESTAURAR SISTEMA

SETUP FILE
ARCHIVO DE CONFIGURACI&Oacute;N

Save your active tweaks and load them on another PC. Imported tweaks are staged for review first.
Guarda tus ajustes activos y c&aacute;rgalos en otra PC. Los ajustes importados se preparan para que los revises primero.

EXPORT MY SETUP
EXPORTAR MI CONFIGURACI&Oacute;N

IMPORT SETUP
IMPORTAR CONFIGURACI&Oacute;N

OPEN DATA FOLDER
ABRIR CARPETA DE DATOS

UNDO JOURNAL
REGISTRO PARA DESHACER

REVERT EVERYTHING
REVERTIR TODO

LOG
REGISTRO

COPY LOG
COPIAR REGISTRO

OPEN LOG FOLDER
ABRIR CARPETA DE REGISTROS

Version 1.0 did not write this setting correctly. Use RE-APPLY below to apply it for real.
La versi&oacute;n 1.0 no escribi&oacute; bien este ajuste. Usa REAPLICAR abajo para aplicarlo de verdad.

This update fixes a v1.0 bug: {0} tweak(s) you applied before were never really written. Press RE-APPLY in TWEAKS to apply them properly.
Esta actualizaci&oacute;n corrige un error de la v1.0: {0} ajuste(s) que aplicaste antes nunca se escribieron de verdad. Presiona REAPLICAR en AJUSTES para aplicarlos bien.

Data folder locked so only administrators can change it. Your undo journal was kept; older logs are in {0}
Carpeta de datos protegida: solo los administradores pueden cambiarla. Se conserv&oacute; tu registro de deshacer; los registros anteriores est&aacute;n en {0}

The old data folder could have been changed by a non-administrator account, so it was set aside without reading it: {0}. The undo journal starts empty. Use the System Restore point to undo older changes.
Una cuenta sin permisos de administrador pudo haber cambiado la carpeta de datos anterior, as&iacute; que se apart&oacute; sin leerla: {0}. El registro de deshacer empieza vac&iacute;o. Usa el punto de restauraci&oacute;n del sistema para deshacer cambios anteriores.

Games
Juegos

GAMES
JUEGOS

Competitive settings for popular shooters, matched to this PC. The app reads each game's own settings file to show what to change, and gives the launch options for the launcher you use. It never changes your game files.
Ajustes competitivos para shooters populares, adaptados a esta PC. La app lee el archivo de ajustes de cada juego para mostrarte qu&eacute; cambiar, y te da las opciones de lanzamiento del launcher que usas. Nunca cambia los archivos de tus juegos.

RESCAN GAMES
VOLVER A BUSCAR JUEGOS

Game scan
Revisi&oacute;n de juegos

The game check starts after the hardware scan.
La revisi&oacute;n de juegos empieza despu&eacute;s del an&aacute;lisis del hardware.

{0} of {1} games found on this PC. Setting and launcher names are shown as they appear in English menus.
Se encontraron {0} de {1} juegos en esta PC. Los nombres de ajustes y de launchers se muestran como en los men&uacute;s en ingl&eacute;s.

None of these games were found on this PC. The recommended settings still apply if you install one.
No se encontr&oacute; ninguno de estos juegos en esta PC. Los ajustes recomendados sirven si instalas alguno.

Games checked: {0} found on this PC.
Juegos revisados: {0} encontrados en esta PC.

Installed with {0}
Instalado con {0}

Not found on this PC
No encontrado en esta PC

{0} / {1} SETTINGS OK
{0} / {1} AJUSTES BIEN

HIDE
OCULTAR

DETAILS
DETALLES

YOUR SETTINGS FILE
TU ARCHIVO DE AJUSTES

Settings file not found. Start the game once, close it, then press RESCAN GAMES.
No se encontr&oacute; el archivo de ajustes. Abre el juego una vez, ci&eacute;rralo y presiona VOLVER A BUSCAR JUEGOS.

not in this version of the file
no est&aacute; en esta versi&oacute;n del archivo

{0}  ->  set to {1}
{0}  ->  pon {1}

OPEN SETTINGS FOLDER
ABRIR CARPETA DE AJUSTES

SET IN THE GAME MENU
AJUSTAR EN EL MEN&Uacute; DEL JUEGO

LAUNCH OPTIONS
OPCIONES DE LANZAMIENTO

COPY
COPIAR

Copied: {0}
Copiado: {0}

Could not copy. Select the text and press Ctrl+C.
No se pudo copiar. Selecciona el texto y presiona Ctrl+C.

Highest FPS
M&aacute;ximos FPS

Capped to your {0} Hz screen (cooler, steadier)
Limitado a tu pantalla de {0} Hz (m&aacute;s fresco y estable)

-dev skips the intro videos. +fps_max 0 removes the frame cap; the capped version runs cooler and steadier, which suits laptops.
-dev omite los videos de inicio. +fps_max 0 quita el l&iacute;mite de FPS; la versi&oacute;n con l&iacute;mite va m&aacute;s fresca y estable, ideal para port&aacute;tiles.

Force Performance mode
Forzar el modo Performance

Only needed if Rendering Mode keeps switching back from Performance. Epic documents this option to force it.
Solo hace falta si Rendering Mode deja de estar en Performance. Epic documenta esta opci&oacute;n para forzarlo.

Not needed. CS2 ignores most old CS:GO launch options (-tickrate, -high, -threads). Set everything in the game menu.
No hace falta. CS2 ignora casi todas las opciones de lanzamiento del viejo CS:GO (-tickrate, -high, -threads). Ajusta todo en el men&uacute; del juego.

Not available. The Riot Client has no launch options; everything is set in the game menu.
No disponible. Riot Client no tiene opciones de lanzamiento; todo se ajusta en el men&uacute; del juego.

Not needed. Overwatch 2 has no launch options that raise FPS.
No hace falta. Overwatch 2 no tiene opciones de lanzamiento que suban los FPS.

Not needed. Siege X has no launch options that raise FPS.
No hace falta. Siege X no tiene opciones de lanzamiento que suban los FPS.

YES
S&Iacute;

NO
NO

CANCEL
CANCELAR

OK
ACEPTAR

APPLY NOW
APLICAR AHORA

SHOW ME FIRST
VER LA LISTA

AUTO-TUNE found {0} improvement(s) for this {1} ({2}).\n\nApply them now (a restore point is made first), or look at the list first?
AUTO-AJUSTE encontr&oacute; {0} mejora(s) para esta {1} ({2}).\n\n&iquest;Aplicarlas ahora (antes se crea un punto de restauraci&oacute;n) o ver la lista primero?

DONE
LISTO

Changes finished.
Cambios terminados.

{0} change(s) done
{0} cambio(s) hecho(s)

{0} failed - see the Log tab
{0} fallaron: mira la pesta&ntilde;a Registro

Windows kept these OFF: {0}
Windows dej&oacute; estos desactivados: {0}

Tweaks active: {0} -> {1}
Ajustes activos: {0} -> {1}

Undo any of it in BACKUP & UNDO.
Puedes deshacer todo en RESPALDO Y DESHACER.

Some changes take effect after a restart.
Algunos cambios se aplican despu&eacute;s de reiniciar.

RESTART NOW
REINICIAR AHORA

LATER
M&Aacute;S TARDE


INSTALLED APPS
APPS INSTALADAS

No suggested actions when copying
Sin acciones sugeridas al copiar

Copying a date, time or phone number no longer pops up suggestions to make a call or add a calendar event.
Copiar una fecha, una hora o un n&uacute;mero de tel&eacute;fono ya no muestra sugerencias para llamar o crear un evento.

No telemetry from PowerShell 7 and .NET tools
Sin telemetr&iacute;a de PowerShell 7 ni de las herramientas .NET

Sets the official opt-out switches, so PowerShell 7 and the .NET SDK stop sending usage data. Windows PowerShell is not affected.
Activa las opciones oficiales de exclusi&oacute;n para que PowerShell 7 y el SDK de .NET dejen de enviar datos de uso. Windows PowerShell no cambia.

Applies to programs started after the change.
Se aplica a los programas que se abran despu&eacute;s del cambio.

Disable AI in Paint
Desactivar la IA en Paint

Turns off Cocreator, Image Creator and generative fill in Paint (Pro and up honor this policy).
Apaga Cocreator, Image Creator y el relleno generativo de Paint (Pro y superiores respetan esta directiva).

Disable AI in Notepad
Desactivar la IA en el Bloc de notas

Removes Copilot, Rewrite and Summarize from Notepad. The editor itself is unchanged.
Quita Copilot, Reescribir y Resumir del Bloc de notas. El editor sigue igual.

Block apps from Windows generative AI
Impedir que las apps usen la IA generativa de Windows

Apps can no longer use the text and image generation built into Windows (Settings > Privacy > Text and image generation).
Las apps ya no pueden usar la generaci&oacute;n de texto e im&aacute;genes integrada en Windows (Configuraci&oacute;n > Privacidad > Generaci&oacute;n de texto e im&aacute;genes).

Edge: no on-device AI model
Edge: sin modelo de IA local

Edge stops downloading its local AI model and deletes it if it is already there. Frees disk space.
Edge deja de descargar su modelo de IA local y lo borra si ya est&aacute; descargado. Libera espacio en disco.

Fastest key repeat
Repetici&oacute;n de teclas m&aacute;s r&aacute;pida

A held key starts repeating after the shortest delay, at the fastest rate.
Una tecla mantenida empieza a repetirse con el menor retraso y a la mayor velocidad.

Xbox button does not open Game Bar
El bot&oacute;n Xbox no abre la Game Bar

Pressing the Xbox button on a controller no longer pops Game Bar over your game. Win+G still opens it.
Pulsar el bot&oacute;n Xbox del mando ya no abre la Game Bar encima del juego. Win+G la sigue abriendo.

No network while asleep on battery
Sin red durante la suspensi&oacute;n con bater&iacute;a

Modern Standby laptops stop syncing mail and downloading updates while asleep on battery: less drain and heat in a bag.
Las port&aacute;tiles con Modern Standby dejan de sincronizar correo y descargar actualizaciones mientras duermen con bater&iacute;a: menos consumo y menos calor en la mochila.

Show hidden CPU power settings
Mostrar ajustes ocultos de energ&iacute;a de la CPU

Adds "Processor performance boost mode" and core parking to Power Options > Advanced settings, so you can tune them yourself.
A&ntilde;ade "Modo de aumento de rendimiento del procesador" y el estacionamiento de n&uacute;cleos a Opciones de energ&iacute;a > Configuraci&oacute;n avanzada, para que los ajustes t&uacute; mismo.

Bluetooth services OFF
Servicios de Bluetooth APAGADOS

Only shown when this PC has no Bluetooth radio, so nothing here can use them.
Solo aparece cuando esta PC no tiene Bluetooth, as&iacute; que nada puede usarlos.

Turn this back off before you plug in a Bluetooth adapter.
Desact&iacute;valo antes de conectar un adaptador Bluetooth.

Fingerprint / face sign-in service OFF
Servicio de inicio con huella o rostro APAGADO

Only shown when this PC has no fingerprint reader or Windows Hello camera.
Solo aparece cuando esta PC no tiene lector de huellas ni c&aacute;mara de Windows Hello.

Turn this back off before you add a fingerprint reader or face camera.
Desact&iacute;valo antes de a&ntilde;adir un lector de huellas o una c&aacute;mara de reconocimiento facial.

Mobile hotspot service OFF
Servicio de zona m&oacute;vil APAGADO

Only needed to share this PC's internet with other devices.
Solo hace falta para compartir el internet de esta PC con otros dispositivos.

Prefer IPv4 over IPv6
Preferir IPv4 sobre IPv6

Windows tries IPv4 first. Fixes slow first connections on networks with broken IPv6, while IPv6 keeps working.
Windows prueba IPv4 primero. Arregla las conexiones lentas en redes con IPv6 roto, y IPv6 sigue funcionando.

Microsoft recommends keeping IPv6 on. This only changes which one is tried first.
Microsoft recomienda dejar IPv6 activado. Esto solo cambia cu&aacute;l se prueba primero.

Disable interrupt moderation (wired)
Desactivar la moderaci&oacute;n de interrupciones (cable)

The network card reports every packet right away instead of batching them. Can lower ping jitter in games, costs a little CPU.
La tarjeta de red avisa de cada paquete al instante en lugar de agruparlos. Puede reducir la variaci&oacute;n del ping en juegos y usa un poco m&aacute;s de CPU.

The adapter briefly reconnects. Turn this back off if downloads get slower.
El adaptador se reconecta un momento. Desact&iacute;valo si las descargas se vuelven m&aacute;s lentas.

Hide Home from Explorer
Ocultar Inicio del Explorador

Removes the Home entry at the top of the navigation pane.
Quita la entrada Inicio de la parte superior del panel de navegaci&oacute;n.

No duplicate USB drives in Explorer
Sin unidades USB duplicadas en el Explorador

USB sticks and SD cards show once under This PC instead of twice in the navigation pane.
Las memorias USB y tarjetas SD aparecen una vez dentro de Este equipo en lugar de dos veces en el panel de navegaci&oacute;n.

Right-click menu: no Give access, Share or Cast
Men&uacute; contextual: sin Conceder acceso, Compartir ni Transmitir

Removes "Give access to", "Share" and "Cast to device" from the right-click menu.
Quita "Conceder acceso a", "Compartir" y "Transmitir a dispositivo" del men&uacute; contextual.

Right-click menu: no app shortcuts
Men&uacute; contextual: sin atajos de apps

Removes "Ask Copilot", "Edit with Clipchamp", "Edit with Photos", "Edit with Paint" and "Edit in Notepad". Open with still works.
Quita "Preguntar a Copilot", "Editar con Clipchamp", "Editar con Fotos", "Editar con Paint" y "Editar en Bloc de notas". Abrir con sigue funcionando.

No "Look for an app in the Store"
Sin "Buscar una app en Microsoft Store"

Opening an unknown file type shows your installed apps instead of sending you to the Microsoft Store.
Abrir un tipo de archivo desconocido muestra tus apps instaladas en lugar de mandarte a Microsoft Store.

Hide the "Learn about this picture" icon
Ocultar el &iacute;cono "M&aacute;s informaci&oacute;n sobre esta imagen"

Removes the Windows Spotlight icon from the desktop. Spotlight wallpapers keep changing.
Quita el &iacute;cono de Windows Spotlight del escritorio. Los fondos de Spotlight siguen cambiando.

No window shake to minimize
Sin agitar ventanas para minimizar

Shaking a window by its title bar no longer minimizes every other window.
Agitar una ventana por su barra de t&iacute;tulo ya no minimiza todas las dem&aacute;s.

Compact Explorer view
Vista compacta del Explorador

Less space between files, so more fit on screen (the Windows 10 spacing).
Menos espacio entre archivos para que quepan m&aacute;s en pantalla (el espaciado de Windows 10).

Sharp sign-in screen background
Fondo n&iacute;tido en la pantalla de inicio de sesi&oacute;n

The sign-in screen shows your lock-screen picture without the blur.
La pantalla de inicio de sesi&oacute;n muestra tu imagen de bloqueo sin desenfoque.

Full-quality wallpaper
Fondo de pantalla a calidad completa

Windows stops recompressing your wallpaper to 85% JPEG quality, so gradients and dark scenes stay smooth.
Windows deja de recomprimir tu fondo al 85% de calidad JPEG, as&iacute; los degradados y las escenas oscuras se ven suaves.

Set your wallpaper again to see the difference.
Vuelve a poner tu fondo de pantalla para ver la diferencia.

Detailed file copy window
Ventana de copia con detalles

Copy and move windows open with the speed graph and details already shown.
Las ventanas de copiar y mover se abren con el gr&aacute;fico de velocidad y los detalles visibles.

Never combine taskbar buttons
No combinar nunca los botones de la barra de tareas

Every window gets its own taskbar button with its title, on every monitor.
Cada ventana tiene su propio bot&oacute;n con su t&iacute;tulo en la barra de tareas, en todos los monitores.

No search history on this device
Sin historial de b&uacute;squeda en este dispositivo

Windows search stops remembering what you searched for on this PC.
La b&uacute;squeda de Windows deja de recordar lo que buscaste en esta PC.

Chrome: no background mode or usage reports
Chrome: sin modo en segundo plano ni informes de uso

Chrome stops running after you close it, stops its cleanup scanner and stops sending usage statistics.
Chrome deja de ejecutarse al cerrarlo, apaga su esc&aacute;ner de limpieza y deja de enviar estad&iacute;sticas de uso.

Chrome will show "managed by your organization" (normal for policies).
Chrome mostrar&aacute; "administrado por tu organizaci&oacute;n" (normal con directivas).

Firefox: no telemetry or studies
Firefox: sin telemetr&iacute;a ni estudios

Firefox stops sending telemetry, stops installing studies and stops its default-browser agent task.
Firefox deja de enviar telemetr&iacute;a, de instalar estudios y de ejecutar su tarea de navegador predeterminado.

Office: minimum diagnostic data
Office: datos de diagn&oacute;stico m&iacute;nimos

Word, Excel, Outlook and the other Office apps send no optional diagnostic data.
Word, Excel, Outlook y las dem&aacute;s apps de Office no env&iacute;an datos de diagn&oacute;stico opcionales.

Stay on your current Windows version
Quedarse en tu versi&oacute;n actual de Windows

Windows Update keeps sending security fixes for the version you have now, but does not upgrade you to the next yearly version (Pro / Enterprise).
Windows Update sigue enviando parches de seguridad para tu versi&oacute;n actual, pero no te actualiza a la siguiente versi&oacute;n anual (Pro / Enterprise).

Turn this off before your version stops getting security updates.
Desact&iacute;valo antes de que tu versi&oacute;n deje de recibir actualizaciones de seguridad.

Delay monthly updates 7 days
Retrasar las actualizaciones mensuales 7 d&iacute;as

Monthly fixes arrive a week later, after early problems are found and pulled (Pro / Enterprise).
Los parches mensuales llegan una semana despu&eacute;s, cuando ya se detectaron y retiraron los primeros fallos (Pro / Enterprise).

Free the space Windows reserves for updates
Liberar el espacio que Windows reserva para actualizaciones

Gives back the 5-7 GB that Windows keeps aside for updates. Worth it on 64-128 GB drives.
Recupera los 5-7 GB que Windows aparta para actualizaciones. Vale la pena en discos de 64-128 GB.

Updates then need that much free space while they install. Windows cannot change this while an update is waiting.
Las actualizaciones necesitar&aacute;n ese espacio libre mientras se instalan. Windows no puede cambiar esto si hay una actualizaci&oacute;n pendiente.

Block potentially unwanted apps
Bloquear aplicaciones potencialmente no deseadas

Defender blocks adware, bundled toolbars, browser hijackers and hidden crypto miners.
Defender bloquea adware, barras de herramientas incluidas, secuestradores del navegador y mineros de criptomonedas ocultos.

Only works while Microsoft Defender is your antivirus.
Solo funciona mientras Microsoft Defender sea tu antivirus.

Disable proxy auto-discovery (WPAD)
Desactivar la detecci&oacute;n autom&aacute;tica de proxy (WPAD)

Stops Windows from asking the network for a proxy, a trick used to intercept traffic on public Wi-Fi.
Windows deja de pedirle un proxy a la red, un truco usado para interceptar el tr&aacute;fico en Wi-Fi p&uacute;blicas.

Company networks that hand out their proxy automatically need this on.
Las redes de empresa que reparten su proxy autom&aacute;ticamente lo necesitan activado.

Disable AutoPlay
Desactivar la reproducci&oacute;n autom&aacute;tica

Plugging in a USB drive, phone or disc no longer pops up an action or opens an app by itself.
Conectar una memoria USB, un tel&eacute;fono o un disco ya no muestra una acci&oacute;n ni abre una app por s&iacute; solo.

LSA protection ON
Protecci&oacute;n LSA ACTIVADA

Runs the Windows sign-in process as protected, so password-stealing tools cannot read its memory. Can be turned off again.
Ejecuta el proceso de inicio de sesi&oacute;n de Windows como protegido, as&iacute; las herramientas que roban contrase&ntilde;as no pueden leer su memoria. Se puede volver a desactivar.

Some old smart-card readers or password plug-ins may stop loading.
Algunos lectores de tarjetas inteligentes o complementos de contrase&ntilde;as antiguos pueden dejar de cargar.

Block Remote Desktop connections
Bloquear las conexiones de Escritorio remoto

Makes sure nobody can sign in to this PC with Remote Desktop. Quick Assist and remote tools you start yourself still work.
Asegura que nadie pueda entrar a esta PC con Escritorio remoto. Asistencia r&aacute;pida y las herramientas remotas que abras t&uacute; siguen funcionando.

Disable Windows Script Host
Desactivar Windows Script Host

Blocks .vbs and .js script files, a common way malware arrives in e-mail attachments and downloads.
Bloquea los scripts .vbs y .js, una v&iacute;a com&uacute;n de malware en adjuntos de correo y descargas.

Some old installers and login scripts use these files.
Algunos instaladores y scripts de inicio de sesi&oacute;n antiguos usan estos archivos.

Classic right-click menu without app shortcuts, no widgets or chat icon, clean Start, no tips or ads, End Task on the taskbar, file extensions visible.
Men&uacute; contextual cl&aacute;sico sin atajos de apps, sin widgets ni &iacute;cono de chat, Inicio limpio, sin consejos ni anuncios, Finalizar tarea en la barra y extensiones de archivo visibles.

Themes
Temas

THEMES
TEMAS

Desktop themes for Rainmeter: a clock that picks its text color from your wallpaper, a status bar, a dock and a wallpaper picker. Everything is made for this screen and can be removed in one click.
Temas de escritorio para Rainmeter: un reloj que elige el color del texto seg&uacute;n tu fondo, una barra de estado, un dock y un selector de fondos. Todo se hace para esta pantalla y se quita con un clic.

RAINMETER
RAINMETER

GET RAINMETER
OBTENER RAINMETER

Opens rainmeter.net, the official site
Abre rainmeter.net, el sitio oficial

CHECK AGAIN
VOLVER A COMPROBAR

LOOK
ESTILO VISUAL

Colors of the status bar, the dock and the wallpaper picker.
Colores de la barra de estado, el dock y el selector de fondos.

WIDGETS
WIDGETS

Your wallpaper with these settings. It updates as you change them.
Tu fondo con estos ajustes. Se actualiza a medida que los cambias.

CLOCK
RELOJ

GENERAL
GENERAL

APPEARANCE
APARIENCIA

WALLPAPERS
FONDOS DE PANTALLA

The picker (left button of the status bar) shows the pictures in these folders, sorted by color. CREATE OZZYHN WALLPAPERS draws six original wallpapers for this theme.
El selector (bot&oacute;n izquierdo de la barra de estado) muestra las im&aacute;genes de estas carpetas, ordenadas por color. CREAR FONDOS OZZYHN dibuja seis fondos originales para este tema.

CREATE OZZYHN WALLPAPERS
CREAR FONDOS OZZYHN

ADD FOLDER
AGREGAR CARPETA

OPEN PICKER
ABRIR SELECTOR

DOCK APPS
APPS DEL DOCK

Only apps installed on this PC are listed. They open as you, never as administrator.
Solo aparecen las apps instaladas en esta PC. Se abren con tu usuario, nunca como administrador.

ADD APP
AGREGAR APP

APPLY THEME
APLICAR TEMA

REMOVE THEME
QUITAR TEMA

MONO DARK
MONO OSCURO

MONO LIGHT
MONO CLARO

OZZYHN NEON
NE&Oacute;N OZZYHN

CRIMSON
CARMES&Iacute;

ARCTIC
&Aacute;RTICO

running
en ejecuci&oacute;n

not running (APPLY THEME starts it)
sin ejecutar (APLICAR TEMA lo inicia)

Rainmeter {0} is installed, {1}. Skins folder: {2}
Rainmeter {0} est&aacute; instalado, {1}. Carpeta de skins: {2}

Rainmeter is not installed. It is free and open source: press GET RAINMETER, install it from the official site, then press CHECK AGAIN. This app never downloads it for you.
Rainmeter no est&aacute; instalado. Es gratis y de c&oacute;digo abierto: pulsa OBTENER RAINMETER, inst&aacute;lalo desde el sitio oficial y luego pulsa VOLVER A COMPROBAR. Esta app nunca lo descarga por ti.

Install Rainmeter to apply a theme. You can set everything up now.
Instala Rainmeter para aplicar un tema. Ya puedes dejarlo todo configurado.

Changes are not on your desktop yet. Press APPLY THEME.
Los cambios a&uacute;n no est&aacute;n en tu escritorio. Pulsa APLICAR TEMA.

Theme is on your desktop. Right-click the clock for more options.
El tema est&aacute; en tu escritorio. Haz clic derecho en el reloj para ver m&aacute;s opciones.

Clock
Reloj

The big clock with the greeting, date and wallpaper-aware color.
El reloj grande con saludo, fecha y color que se adapta al fondo.

Status bar
Barra de estado

Date, time, CPU, RAM, network, volume and battery at the top. The left button opens the wallpaper picker.
Fecha, hora, CPU, RAM, red, volumen y bater&iacute;a arriba. El bot&oacute;n izquierdo abre el selector de fondos.

Keep the bar above windows
Barra siempre encima de las ventanas

Off: the bar lives on the desktop, under your windows.
Apagado: la barra vive en el escritorio, debajo de tus ventanas.

Dock
Dock

Your apps in a floating bar at the bottom. Hover to lift, click to open.
Tus apps en una barra flotante abajo. Pasa el rat&oacute;n para elevarlas, haz clic para abrirlas.

Hide the Rainmeter sample skins
Ocultar los skins de ejemplo de Rainmeter

Unloads the illustro skins Rainmeter shows the first time.
Descarga los skins illustro que Rainmeter muestra la primera vez.

Top left
Arriba a la izquierda

Top
Arriba

Top right
Arriba a la derecha

Left
Izquierda

Center
Centro

Right
Derecha

Bottom left
Abajo a la izquierda

Bottom
Abajo

Bottom right
Abajo a la derecha

Position
Posici&oacute;n

Where the clock sits on the desktop.
D&oacute;nde va el reloj en el escritorio.

Horizontal margin
Margen horizontal

Distance from the left or right edge, in pixels.
Distancia al borde izquierdo o derecho, en p&iacute;xeles.

Vertical margin
Margen vertical

Distance from the top or bottom edge, in pixels.
Distancia al borde superior o inferior, en p&iacute;xeles.

Size
Tama&ntilde;o

Everything in the theme grows with this. This screen uses {0}% scaling.
Todo el tema crece con esto. Esta pantalla usa un escalado del {0}%.

24-hour format
Formato de 24 horas

Use 24-hour time instead of AM/PM.
Usa la hora de 24 horas en lugar de AM/PM.

Date format
Formato de fecha

How the date is written.
C&oacute;mo se escribe la fecha.

The day spelled wide, with the date and time under it.
El d&iacute;a escrito a lo ancho, con la fecha y la hora debajo.

A greeting and the short day between two lines.
Un saludo y el d&iacute;a abreviado entre dos l&iacute;neas.

Big hours over minutes, day and date below.
Horas grandes sobre los minutos, con el d&iacute;a y la fecha debajo.

Neon time in the theme colors with a seconds line.
Hora ne&oacute;n con los colores del tema y una l&iacute;nea de segundos.

One quiet line.
Una sola l&iacute;nea discreta.

Style
Estilo

The look of the clock. Right-click the clock on the desktop to switch styles there too.
El aspecto del reloj. Tambi&eacute;n puedes cambiarlo con clic derecho sobre el reloj en el escritorio.

Automatic text color
Color de texto autom&aacute;tico

Reads the wallpaper under the clock and picks the most readable of your three colors. Follows wallpaper changes.
Lee el fondo debajo del reloj y elige el m&aacute;s legible de tus tres colores. Sigue los cambios de fondo.

BEST CONTRAST
MEJOR CONTRASTE

BRIGHTNESS LIMITS
L&Iacute;MITES DE BRILLO

How to choose
C&oacute;mo elegir

BEST CONTRAST measures which color reads best. BRIGHTNESS LIMITS uses the two limits below.
MEJOR CONTRASTE mide qu&eacute; color se lee mejor. L&Iacute;MITES DE BRILLO usa los dos l&iacute;mites de abajo.

Area read (%)
Zona le&iacute;da (%)

Size of the part of the wallpaper read around the clock.
Tama&ntilde;o de la parte del fondo que se lee alrededor del reloj.

Dark limit
L&iacute;mite oscuro

Below this brightness the light text color is used.
Por debajo de este brillo se usa el color de texto claro.

Light limit
L&iacute;mite claro

Above this brightness the dark text color is used.
Por encima de este brillo se usa el color de texto oscuro.

DARK
OSCURO

MID
MEDIO

LIGHT
CLARO

Text color
Color del texto

The clock always uses this color.
El reloj siempre usa este color.

Dark text
Texto oscuro

Used on bright wallpapers.
Se usa sobre fondos claros.

Mid text
Texto medio

Used on medium wallpapers.
Se usa sobre fondos de brillo medio.

Light text
Texto claro

Used on dark wallpapers.
Se usa sobre fondos oscuros.

No folders yet. Press ADD FOLDER or CREATE OZZYHN WALLPAPERS.
A&uacute;n no hay carpetas. Pulsa AGREGAR CARPETA o CREAR FONDOS OZZYHN.

REMOVE
QUITAR

GOOD
BUENAS

EVENING
NOCHES

Text color: {0}. Wallpaper brightness under the clock: {1}%.
Color del texto: {0}. Brillo del fondo debajo del reloj: {1}%.

Text color: {0} (fixed).
Color del texto: {0} (fijo).

Rainmeter is not installed. Press GET RAINMETER, install it, then try again.
Rainmeter no est&aacute; instalado. Pulsa OBTENER RAINMETER, inst&aacute;lalo y vuelve a intentarlo.

Rainmeter did not start. Open it from the Start menu, then press APPLY THEME again.
Rainmeter no se inici&oacute;. &Aacute;brelo desde el men&uacute; Inicio y vuelve a pulsar APLICAR TEMA.

Applying the theme...
Aplicando el tema...

Theme files written to {0}
Archivos del tema guardados en {0}

Theme applied.
Tema aplicado.

Theme failed: {0}
El tema fall&oacute;: {0}

The theme could not be applied:\n\n{0}
No se pudo aplicar el tema:\n\n{0}

Remove the OZZYHN theme?\n\nIts skins are unloaded and the OZZYHN skins folder is deleted. Your wallpaper, your pictures and your other Rainmeter skins stay as they are.
&iquest;Quitar el tema OZZYHN?\n\nSus skins se descargan y se borra la carpeta de skins OZZYHN. Tu fondo, tus im&aacute;genes y tus otros skins de Rainmeter se quedan como est&aacute;n.

Removing the theme...
Quitando el tema...

Theme removed. Your wallpaper and your own Rainmeter skins were not touched.
Tema quitado. Tu fondo y tus propios skins de Rainmeter no se tocaron.

Drawing the OZZYHN wallpapers...
Dibujando los fondos OZZYHN...

{0} wallpapers saved in {1}
{0} fondos guardados en {1}

Pick a folder with wallpapers (JPG, PNG or BMP).
Elige una carpeta con fondos de pantalla (JPG, PNG o BMP).

Programs and shortcuts
Programas y accesos directos
'@
#endregion

#region ============================ XAML ============================
$Oz.Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Optimizaciones de Ozzyhn | OZZYHN TWEAKS" Width="1320" Height="840" MinWidth="960" MinHeight="540"
        WindowStartupLocation="CenterScreen" Background="#05070D" Foreground="#E6F1FF"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display">
    <WindowChrome.WindowChrome>
        <WindowChrome CaptionHeight="48" ResizeBorderThickness="6" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
    </WindowChrome.WindowChrome>

    <Window.Resources>
        <FontFamily x:Key="Icons">Segoe Fluent Icons, Segoe MDL2 Assets</FontFamily>
        <FontFamily x:Key="Display">Bahnschrift, Segoe UI</FontFamily>
        <FontFamily x:Key="Mono">Cascadia Mono, Consolas</FontFamily>

        <SolidColorBrush x:Key="Cyan" Color="#00E5FF"/>
        <SolidColorBrush x:Key="Magenta" Color="#FF2BD6"/>
        <SolidColorBrush x:Key="Violet" Color="#8A5CFF"/>
        <SolidColorBrush x:Key="Green" Color="#2BFF9A"/>
        <SolidColorBrush x:Key="Amber" Color="#FFB020"/>
        <SolidColorBrush x:Key="Red" Color="#FF3B5C"/>
        <SolidColorBrush x:Key="Text" Color="#E6F1FF"/>
        <SolidColorBrush x:Key="Muted" Color="#8A9BBF"/>
        <SolidColorBrush x:Key="Dim" Color="#5D6E92"/>
        <SolidColorBrush x:Key="Line" Color="#1B2A48"/>

        <LinearGradientBrush x:Key="NeonGrad" StartPoint="0,0" EndPoint="1,0">
            <GradientStop Color="#00E5FF" Offset="0"/>
            <GradientStop Color="#8A5CFF" Offset="0.55"/>
            <GradientStop Color="#FF2BD6" Offset="1"/>
        </LinearGradientBrush>
        <LinearGradientBrush x:Key="NeonGradV" StartPoint="0,0" EndPoint="0,1">
            <GradientStop Color="#00E5FF" Offset="0"/>
            <GradientStop Color="#FF2BD6" Offset="1"/>
        </LinearGradientBrush>
        <RadialGradientBrush x:Key="BgGlow" Center="0.15,0" GradientOrigin="0.15,0" RadiusX="0.9" RadiusY="0.8">
            <GradientStop Color="#1A0F2A4A" Offset="0"/>
            <GradientStop Color="#0005070D" Offset="1"/>
        </RadialGradientBrush>
        <RadialGradientBrush x:Key="BgGlow2" Center="1,1" GradientOrigin="1,1" RadiusX="0.7" RadiusY="0.7">
            <GradientStop Color="#16FF2BD6" Offset="0"/>
            <GradientStop Color="#0005070D" Offset="1"/>
        </RadialGradientBrush>
        <PathGeometry x:Key="OzHex" Figures="M50,4 L89.84,27 L89.84,73 L50,96 L10.16,73 L10.16,27 Z"/>
        <PathGeometry x:Key="OzMark" Figures="M29,33 L39,33 L46,40 L46,60 L39,67 L29,67 L22,60 L22,40 Z M31,40 L37,40 L39,42 L39,58 L37,60 L31,60 L29,58 L29,42 Z M54,33 L78,33 L78,40 L63.5,60 L78,60 L78,67 L54,67 L54,60 L68.5,40 L54,40 Z"/>
        <DrawingBrush x:Key="GridBrush" TileMode="Tile" Viewport="0,0,34,34" ViewportUnits="Absolute" Viewbox="0,0,34,34" ViewboxUnits="Absolute" RenderOptions.CachingHint="Cache">
            <DrawingBrush.Drawing>
                <GeometryDrawing>
                    <GeometryDrawing.Pen><Pen Brush="#0E1A33" Thickness="1"/></GeometryDrawing.Pen>
                    <GeometryDrawing.Geometry>
                        <GeometryGroup>
                            <LineGeometry StartPoint="0,0" EndPoint="34,0"/>
                            <LineGeometry StartPoint="0,0" EndPoint="0,34"/>
                        </GeometryGroup>
                    </GeometryDrawing.Geometry>
                </GeometryDrawing>
            </DrawingBrush.Drawing>
        </DrawingBrush>

        <!-- Text -->
        <Style x:Key="Label" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#5D6E92"/>
        </Style>
        <Style x:Key="H1" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="24"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#E6F1FF"/>
        </Style>
        <Style x:Key="H2" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#E6F1FF"/>
        </Style>
        <Style x:Key="Body" TargetType="TextBlock">
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Foreground" Value="#8A9BBF"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>

        <!-- Panels -->
        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="#CC0A1120"/>
            <Setter Property="BorderBrush" Value="#1B2A48"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="12"/>
            <Setter Property="Padding" Value="16"/>
            <Setter Property="Margin" Value="0,0,12,12"/>
        </Style>

        <!-- Buttons -->
        <Style x:Key="Neon" TargetType="Button">
            <Setter Property="Foreground" Value="#00E5FF"/>
            <Setter Property="Background" Value="#0F00E5FF"/>
            <Setter Property="BorderBrush" Value="#5500E5FF"/>
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="7" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#1CFFFFFF"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{Binding Foreground, RelativeSource={RelativeSource TemplatedParent}}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#33FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.35"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="NeonDanger" TargetType="Button" BasedOn="{StaticResource Neon}">
            <Setter Property="Foreground" Value="#FF3B5C"/>
            <Setter Property="Background" Value="#0FFF3B5C"/>
            <Setter Property="BorderBrush" Value="#55FF3B5C"/>
        </Style>
        <Style x:Key="NeonViolet" TargetType="Button" BasedOn="{StaticResource Neon}">
            <Setter Property="Foreground" Value="#B79BFF"/>
            <Setter Property="Background" Value="#0F8A5CFF"/>
            <Setter Property="BorderBrush" Value="#558A5CFF"/>
        </Style>
        <Style x:Key="Primary" TargetType="Button">
            <Setter Property="Foreground" Value="#04060C"/>
            <Setter Property="Padding" Value="18,9"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{StaticResource NeonGrad}" CornerRadius="8" Padding="{TemplateBinding Padding}" BorderBrush="#66FFFFFF" BorderThickness="0,1,0,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect Color="#FF2BD6" BlurRadius="22" ShadowDepth="0" Opacity="0.85"/>
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.35"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="Ghost" TargetType="Button">
            <Setter Property="Foreground" Value="#8A9BBF"/>
            <Setter Property="Width" Value="46"/>
            <Setter Property="Height" Value="34"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#18FFFFFF"/>
                                <Setter Property="Foreground" Value="#E6F1FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="GhostClose" TargetType="Button" BasedOn="{StaticResource Ghost}">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#E81123"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Navigation -->
        <Style x:Key="Nav" TargetType="RadioButton">
            <Setter Property="Height" Value="42"/>
            <Setter Property="Foreground" Value="#8A9BBF"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,2"/>
            <Setter Property="GroupName" Value="nav"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="9" Height="{TemplateBinding Height}" Padding="14,0">
                            <Grid>
                                <Border x:Name="Bar" Width="3" CornerRadius="2" HorizontalAlignment="Left" Margin="-14,10,0,10" Background="{StaticResource NeonGradV}" Visibility="Hidden"/>
                                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                    <TextBlock Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" FontFamily="{StaticResource Icons}" FontSize="16" Width="28" VerticalAlignment="Center"/>
                                    <ContentPresenter VerticalAlignment="Center" TextElement.FontFamily="{StaticResource Display}" TextElement.FontSize="13.5"/>
                                </StackPanel>
                            </Grid>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#0F1C34"/>
                                <Setter Property="Foreground" Value="#E6F1FF"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#1800E5FF"/>
                                <Setter TargetName="Bar" Property="Visibility" Value="Visible"/>
                                <Setter Property="Foreground" Value="#00E5FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Filter chips -->
        <Style x:Key="Chip" TargetType="RadioButton">
            <Setter Property="Foreground" Value="#8A9BBF"/>
            <Setter Property="Margin" Value="0,0,6,6"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="Bd" CornerRadius="13" Padding="12,5" BorderThickness="1" BorderBrush="#22FFFFFF" Background="#08FFFFFF">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#6600E5FF"/>
                                <Setter Property="Foreground" Value="#E6F1FF"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#2200E5FF"/>
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#00E5FF"/>
                                <Setter Property="Foreground" Value="#00E5FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Toggle switch -->
        <Style x:Key="Switch" TargetType="CheckBox">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Grid Width="46" Height="24" Background="Transparent">
                            <Border x:Name="Track" CornerRadius="12" Background="#0E1729" BorderBrush="#2A3B5E" BorderThickness="1"/>
                            <Grid x:Name="KnobBox" Width="22" Height="22" Margin="1,0" HorizontalAlignment="Left">
                                <Ellipse x:Name="Halo" Width="22" Height="22" Fill="#4400E5FF" Visibility="Hidden"/>
                                <Ellipse x:Name="Knob" Width="16" Height="16" Fill="#5D6E92"/>
                            </Grid>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Track" Property="BorderBrush" Value="#4FD8FF"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Track" Property="Background" Value="#2E00E5FF"/>
                                <Setter TargetName="Track" Property="BorderBrush" Value="#00E5FF"/>
                                <Setter TargetName="KnobBox" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="Knob" Property="Fill" Value="#00E5FF"/>
                                <Setter TargetName="Halo" Property="Visibility" Value="Visible"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.3"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Square check -->
        <Style x:Key="Tick" TargetType="CheckBox">
            <Setter Property="Foreground" Value="#E6F1FF"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Grid Background="Transparent">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" BorderThickness="1" BorderBrush="#3A4C70" Background="#0E1729" VerticalAlignment="Center">
                                <TextBlock x:Name="Mark" Text="&#xE73E;" FontFamily="{StaticResource Icons}" FontSize="11" Foreground="#04060C" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Hidden"/>
                            </Border>
                            <ContentPresenter Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Box" Property="BorderBrush" Value="#00E5FF"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Box" Property="Background" Value="#00E5FF"/>
                                <Setter TargetName="Box" Property="BorderBrush" Value="#00E5FF"/>
                                <Setter TargetName="Mark" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Meter -->
        <Style x:Key="Meter" TargetType="ProgressBar">
            <Setter Property="Height" Value="5"/>
            <Setter Property="Maximum" Value="100"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Grid>
                            <Border x:Name="PART_Track" CornerRadius="3" Background="#16FFFFFF"/>
                            <Border x:Name="PART_Indicator" CornerRadius="3" HorizontalAlignment="Left" Background="{StaticResource NeonGrad}"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Inputs -->
        <Style x:Key="Input" TargetType="TextBox">
            <Setter Property="Background" Value="#0B1426"/>
            <Setter Property="Foreground" Value="#E6F1FF"/>
            <Setter Property="BorderBrush" Value="#22FFFFFF"/>
            <Setter Property="CaretBrush" Value="#00E5FF"/>
            <Setter Property="SelectionBrush" Value="#00E5FF"/>
            <Setter Property="Padding" Value="34,8,10,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="9">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="#00E5FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NeonAmber" TargetType="Button" BasedOn="{StaticResource Neon}">
            <Setter Property="Foreground" Value="#FFB020"/>
            <Setter Property="Background" Value="#14FFB020"/>
            <Setter Property="BorderBrush" Value="#66FFB020"/>
        </Style>

        <!-- Language switch (EN | ES) in the title bar -->
        <Style x:Key="Lang" TargetType="RadioButton">
            <Setter Property="Foreground" Value="#8A9BBF"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="GroupName" Value="lang"/>
            <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="Bd" CornerRadius="9" Padding="9,3" Background="Transparent">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#E6F1FF"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{StaticResource NeonGrad}"/>
                                <Setter Property="Foreground" Value="#04060C"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Small text link -->
        <Style x:Key="LinkBtn" TargetType="Button">
            <Setter Property="Foreground" Value="#8A9BBF"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontFamily" Value="{StaticResource Mono}"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="HorizontalAlignment" Value="Left"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="Transparent">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#00E5FF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- "OZZYHN TWEAKS //" label above page titles -->
        <Style x:Key="Kicker" TargetType="TextBlock">
            <Setter Property="FontFamily" Value="{StaticResource Display}"/>
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="{StaticResource NeonGrad}"/>
            <Setter Property="Margin" Value="0,0,0,3"/>
        </Style>

        <!-- Thin neon scrollbars everywhere -->
        <Style TargetType="ScrollBar">
            <Setter Property="Width" Value="8"/>
            <Setter Property="MinWidth" Value="8"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Track x:Name="PART_Track" Orientation="Vertical" IsDirectionReversed="True">
                            <Track.Thumb>
                                <Thumb>
                                    <Thumb.Template>
                                        <ControlTemplate TargetType="Thumb">
                                            <Border CornerRadius="4" Background="#3300E5FF" Margin="1"/>
                                        </ControlTemplate>
                                    </Thumb.Template>
                                </Thumb>
                            </Track.Thumb>
                        </Track>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="Orientation" Value="Horizontal">
                    <Setter Property="Width" Value="Auto"/>
                    <Setter Property="MinWidth" Value="0"/>
                    <Setter Property="Height" Value="8"/>
                    <Setter Property="Template">
                        <Setter.Value>
                            <ControlTemplate TargetType="ScrollBar">
                                <Track x:Name="PART_Track" Orientation="Horizontal">
                                    <Track.Thumb>
                                        <Thumb>
                                            <Thumb.Template>
                                                <ControlTemplate TargetType="Thumb">
                                                    <Border CornerRadius="4" Background="#3300E5FF" Margin="1"/>
                                                </ControlTemplate>
                                            </Thumb.Template>
                                        </Thumb>
                                    </Track.Thumb>
                                </Track>
                            </ControlTemplate>
                        </Setter.Value>
                    </Setter>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="ToolTip">
            <Setter Property="Background" Value="#0B1426"/>
            <Setter Property="Foreground" Value="#E6F1FF"/>
            <Setter Property="BorderBrush" Value="#00E5FF"/>
            <Setter Property="Padding" Value="10,6"/>
        </Style>
    </Window.Resources>

    <Border x:Name="RootBorder" BorderBrush="#1B2A48" BorderThickness="1" Background="#05070D">
        <Grid>
            <!-- Background layers + OZZYHN TWEAKS watermark, cached as one bitmap -->
            <Grid IsHitTestVisible="False" CacheMode="BitmapCache">
                <Rectangle Fill="{StaticResource GridBrush}" Opacity="0.55"/>
                <Rectangle Fill="{StaticResource BgGlow}"/>
                <Rectangle Fill="{StaticResource BgGlow2}"/>
                <Rectangle Opacity="0.045">
                    <Rectangle.Fill>
                        <VisualBrush TileMode="Tile" Viewport="0,0,480,240" ViewportUnits="Absolute" Viewbox="0,0,480,240" ViewboxUnits="Absolute" Stretch="None">
                            <VisualBrush.Visual>
                                <Canvas Width="480" Height="240" Background="Transparent">
                                    <TextBlock Canvas.Left="36" Canvas.Top="104" Text="OZZYHN TWEAKS" FontFamily="Bahnschrift, Segoe UI" FontWeight="Bold" FontSize="36" Foreground="#00E5FF">
                                        <TextBlock.RenderTransform>
                                            <RotateTransform Angle="-14"/>
                                        </TextBlock.RenderTransform>
                                    </TextBlock>
                                </Canvas>
                            </VisualBrush.Visual>
                        </VisualBrush>
                    </Rectangle.Fill>
                </Rectangle>
                <Viewbox Width="520" Height="520" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,-110,-130" Opacity="0.07">
                    <Canvas Width="100" Height="100">
                        <Path Data="{StaticResource OzHex}" Stroke="{StaticResource NeonGrad}" StrokeThickness="4" StrokeLineJoin="Round"/>
                        <Path Data="{StaticResource OzMark}" Fill="{StaticResource NeonGrad}"/>
                    </Canvas>
                </Viewbox>
            </Grid>

            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="48"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="30"/>
                </Grid.RowDefinitions>

                <!-- ============ TITLE BAR ============ -->
                <Grid Grid.Row="0" Background="#A0050912">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel Orientation="Horizontal" Margin="18,0,0,0" VerticalAlignment="Center">
                        <Viewbox Width="32" Height="32">
                            <Canvas Width="100" Height="100">
                                <Path Data="{StaticResource OzHex}" Stroke="#00E5FF" StrokeThickness="16" StrokeLineJoin="Round" Opacity="0.15">
                                    <Path.Triggers>
                                        <EventTrigger RoutedEvent="FrameworkElement.Loaded">
                                            <BeginStoryboard>
                                                <Storyboard RepeatBehavior="Forever" AutoReverse="True" Timeline.DesiredFrameRate="15">
                                                    <DoubleAnimation Storyboard.TargetProperty="Opacity" From="0.06" To="0.32" Duration="0:0:1.8"/>
                                                </Storyboard>
                                            </BeginStoryboard>
                                        </EventTrigger>
                                    </Path.Triggers>
                                </Path>
                                <Path Data="{StaticResource OzHex}" Stroke="{StaticResource NeonGrad}" StrokeThickness="7" StrokeLineJoin="Round" Fill="#1A00E5FF"/>
                                <Path Data="{StaticResource OzMark}" Fill="#E6F1FF"/>
                            </Canvas>
                        </Viewbox>
                        <TextBlock Margin="12,0,0,0" VerticalAlignment="Center" FontFamily="{StaticResource Display}" FontSize="15.5" FontWeight="SemiBold">
                            <Run Text="OPTIMIZACIONES" Foreground="#E6F1FF"/><Run Text=" DE " Foreground="#5D6E92"/><Run Text="OZZYHN" Foreground="#00E5FF"/>
                        </TextBlock>
                        <Border Margin="12,0,0,0" CornerRadius="9" Padding="8,2" BorderBrush="#558A5CFF" BorderThickness="1" VerticalAlignment="Center">
                            <TextBlock x:Name="VersionText" Text="v1.2.0" FontSize="10.5" Foreground="#B79BFF" FontFamily="{StaticResource Mono}"/>
                        </Border>
                        <TextBlock Text="//  OZZYHN TWEAKS" Margin="12,0,0,0" VerticalAlignment="Center" FontFamily="{StaticResource Display}" FontSize="11.5" FontWeight="Bold" Foreground="{StaticResource NeonGrad}"/>
                    </StackPanel>

                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,6,0">
                        <Border x:Name="TierChip" CornerRadius="11" Padding="12,4" Margin="0,0,10,0" BorderThickness="1" BorderBrush="#5500E5FF" Background="#1000E5FF" VerticalAlignment="Center">
                            <TextBlock x:Name="TierChipText" Text="SCANNING..." FontFamily="{StaticResource Display}" FontSize="11.5" FontWeight="SemiBold" Foreground="#00E5FF"/>
                        </Border>
                        <Border CornerRadius="11" BorderBrush="#33FFFFFF" BorderThickness="1" Background="#0AFFFFFF" Padding="2" Margin="0,0,8,0" VerticalAlignment="Center">
                            <StackPanel Orientation="Horizontal">
                                <RadioButton x:Name="LangEn" Style="{StaticResource Lang}" Content="EN" ToolTip="English"/>
                                <RadioButton x:Name="LangEs" Style="{StaticResource Lang}" Content="ES" ToolTip="Espa&#xF1;ol"/>
                            </StackPanel>
                        </Border>
                        <Button x:Name="BtnGitHub" Style="{StaticResource Ghost}" ToolTip="github.com/ozzyhntweaks">
                            <TextBlock Text="&#xE774;" FontFamily="{StaticResource Icons}" FontSize="14"/>
                        </Button>
                        <Button x:Name="BtnMin" Style="{StaticResource Ghost}">
                            <TextBlock Text="&#xE921;" FontFamily="{StaticResource Icons}" FontSize="10"/>
                        </Button>
                        <Button x:Name="BtnMax" Style="{StaticResource Ghost}">
                            <TextBlock Text="&#xE922;" FontFamily="{StaticResource Icons}" FontSize="10"/>
                        </Button>
                        <Button x:Name="BtnClose" Style="{StaticResource GhostClose}">
                            <TextBlock Text="&#xE8BB;" FontFamily="{StaticResource Icons}" FontSize="10"/>
                        </Button>
                    </StackPanel>

                    <!-- neon sweep -->
                    <Grid Grid.ColumnSpan="3" VerticalAlignment="Bottom" Height="1" ClipToBounds="True" IsHitTestVisible="False">
                        <Rectangle Fill="#1B2A48"/>
                        <Rectangle Width="260" HorizontalAlignment="Left">
                            <Rectangle.Fill>
                                <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                                    <GradientStop Color="#0000E5FF" Offset="0"/>
                                    <GradientStop Color="#FF00E5FF" Offset="0.5"/>
                                    <GradientStop Color="#00FF2BD6" Offset="1"/>
                                </LinearGradientBrush>
                            </Rectangle.Fill>
                            <Rectangle.RenderTransform>
                                <TranslateTransform/>
                            </Rectangle.RenderTransform>
                            <Rectangle.Triggers>
                                <EventTrigger RoutedEvent="FrameworkElement.Loaded">
                                    <BeginStoryboard>
                                        <Storyboard RepeatBehavior="Forever" Duration="0:0:9" Timeline.DesiredFrameRate="30">
                                            <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" From="-300" To="2200" Duration="0:0:4"/>
                                        </Storyboard>
                                    </BeginStoryboard>
                                </EventTrigger>
                            </Rectangle.Triggers>
                        </Rectangle>
                    </Grid>
                </Grid>

                <!-- ============ BODY ============ -->
                <Grid Grid.Row="1">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="224"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Navigation -->
                    <Border Background="#8A060A14" BorderBrush="#1B2A48" BorderThickness="0,0,1,0">
                        <Grid Margin="12,16,12,14">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
                                <StackPanel>
                                    <TextBlock Text="CONTROL DECK" Style="{StaticResource Label}" Margin="14,0,0,8"/>
                                    <RadioButton x:Name="NavDash" Style="{StaticResource Nav}" Tag="&#xE9D9;" Content="Dashboard" IsChecked="True"/>
                                    <RadioButton x:Name="NavTweaks" Style="{StaticResource Nav}" Tag="&#xE945;" Content="Tweaks"/>
                                    <RadioButton x:Name="NavProfiles" Style="{StaticResource Nav}" Tag="&#xE734;" Content="Profiles"/>
                                    <RadioButton x:Name="NavGames" Style="{StaticResource Nav}" Tag="&#xE7FC;" Content="Games"/>
                                    <RadioButton x:Name="NavThemes" Style="{StaticResource Nav}" Tag="&#xE790;" Content="Themes"/>
                                    <RadioButton x:Name="NavDebloat" Style="{StaticResource Nav}" Tag="&#xE74D;" Content="Debloat"/>
                                    <RadioButton x:Name="NavDrivers" Style="{StaticResource Nav}" Tag="&#xE896;" Content="Drivers"/>
                                    <RadioButton x:Name="NavTools" Style="{StaticResource Nav}" Tag="&#xE90F;" Content="Tools"/>
                                    <RadioButton x:Name="NavBackup" Style="{StaticResource Nav}" Tag="&#xE777;" Content="Backup &amp; Undo"/>
                                    <RadioButton x:Name="NavLog" Style="{StaticResource Nav}" Tag="&#xE8A5;" Content="Log"/>
                                </StackPanel>
                            </ScrollViewer>
                            <StackPanel Grid.Row="1">
                                <Border x:Name="NavProfileCard" CornerRadius="10" Padding="12,10" Background="#0C1222" BorderBrush="#2A00E5FF" BorderThickness="1" Margin="0,10,0,10">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <Border Width="42" Height="42" CornerRadius="21" Background="#05070D" BorderBrush="{StaticResource NeonGrad}" BorderThickness="1.5">
                                            <Viewbox Margin="6">
                                                <Canvas Width="100" Height="100">
                                                    <Path Data="{StaticResource OzHex}" Stroke="{StaticResource NeonGrad}" StrokeThickness="8" StrokeLineJoin="Round" Fill="#1A00E5FF"/>
                                                    <Path Data="{StaticResource OzMark}" Fill="#E6F1FF"/>
                                                </Canvas>
                                            </Viewbox>
                                        </Border>
                                        <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                                            <TextBlock Text="OZZYHN TWEAKS" FontFamily="{StaticResource Display}" FontWeight="Bold" FontSize="13" Foreground="{StaticResource NeonGrad}"/>
                                            <Button x:Name="BtnProfile" Style="{StaticResource LinkBtn}" Content="@ozzyhntweaks" ToolTip="github.com/ozzyhntweaks" Margin="0,2,0,0"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>
                                <Border x:Name="NavActiveCard" CornerRadius="10" Padding="14,12" Background="#0C1222" BorderBrush="#1B2A48" BorderThickness="1" Margin="0,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="TWEAKS ACTIVE" Style="{StaticResource Label}"/>
                                        <StackPanel Orientation="Horizontal" Margin="0,4,0,6">
                                            <TextBlock x:Name="NavActiveCount" Text="--" FontFamily="{StaticResource Display}" FontSize="26" FontWeight="Bold" Foreground="#00E5FF"/>
                                            <TextBlock x:Name="NavActiveTotal" Text=" / --" FontFamily="{StaticResource Display}" FontSize="14" Foreground="#5D6E92" VerticalAlignment="Bottom" Margin="0,0,0,4"/>
                                        </StackPanel>
                                        <ProgressBar x:Name="NavActiveBar" Style="{StaticResource Meter}" Value="0"/>
                                    </StackPanel>
                                </Border>
                                <StackPanel Orientation="Horizontal" Margin="4,0,0,0">
                                    <Ellipse x:Name="AdminDot" Width="7" Height="7" Fill="#2BFF9A" VerticalAlignment="Center"/>
                                    <TextBlock x:Name="AdminText" Text="ADMIN MODE" Style="{StaticResource Label}" Margin="8,0,0,0" Foreground="#2BFF9A"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Pages -->
                    <Grid Grid.Column="1">

                        <!-- ===================== DASHBOARD ===================== -->
                        <ScrollViewer x:Name="PageDash" VerticalScrollBarVisibility="Auto" Padding="24,16,12,8">
                            <StackPanel>
                                <TextBlock Text="OZZYHN TWEAKS  //  CONTROL DECK" Style="{StaticResource Kicker}" Margin="2,0,0,8"/>
                                <Border Style="{StaticResource Card}" Padding="22">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <Viewbox Grid.ColumnSpan="3" Width="176" Height="176" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,190,0" Opacity="0.06" IsHitTestVisible="False">
                                            <Canvas Width="100" Height="100">
                                                <Path Data="{StaticResource OzHex}" Stroke="{StaticResource NeonGrad}" StrokeThickness="5" StrokeLineJoin="Round"/>
                                                <Path Data="{StaticResource OzMark}" Fill="{StaticResource NeonGrad}"/>
                                            </Canvas>
                                        </Viewbox>
                                        <Grid Width="170" Height="170">
                                            <Ellipse Width="150" Height="150" Stroke="#14FFFFFF" StrokeThickness="10"/>
                                            <Path x:Name="ScoreGlow" StrokeThickness="22" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stroke="{StaticResource NeonGrad}" Opacity="0.16"/>
                                            <Path x:Name="ScoreRing" StrokeThickness="10" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Stroke="{StaticResource NeonGrad}"/>
                                            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                                                <TextBlock x:Name="ScoreText" Text="--" FontFamily="{StaticResource Display}" FontSize="46" FontWeight="Bold" HorizontalAlignment="Center"/>
                                                <TextBlock Text="OZ SCORE" Style="{StaticResource Label}" HorizontalAlignment="Center"/>
                                            </StackPanel>
                                        </Grid>
                                        <StackPanel Grid.Column="1" Margin="26,6,10,0" VerticalAlignment="Center">
                                            <TextBlock Text="SYSTEM CLASS" Style="{StaticResource Label}"/>
                                            <TextBlock x:Name="TierText" Text="SCANNING HARDWARE..." FontFamily="{StaticResource Display}" FontSize="34" FontWeight="Bold" Foreground="#00E5FF" Margin="0,2,0,0" TextWrapping="Wrap"/>
                                            <TextBlock x:Name="TierSub" Text="" FontFamily="{StaticResource Display}" FontSize="14" Foreground="#E6F1FF" Margin="0,4,0,0" TextWrapping="Wrap"/>
                                            <TextBlock x:Name="TierSummary" Text="" Style="{StaticResource Body}" Margin="0,8,0,0" MaxWidth="560" HorizontalAlignment="Left"/>
                                            <UniformGrid Columns="4" Margin="0,14,0,0" MaxWidth="560" HorizontalAlignment="Left">
                                                <StackPanel Margin="0,0,14,0"><TextBlock Text="CPU" Style="{StaticResource Label}"/><ProgressBar x:Name="BarCpu" Style="{StaticResource Meter}" Margin="0,5,0,0"/></StackPanel>
                                                <StackPanel Margin="0,0,14,0"><TextBlock Text="GPU" Style="{StaticResource Label}"/><ProgressBar x:Name="BarGpu" Style="{StaticResource Meter}" Margin="0,5,0,0"/></StackPanel>
                                                <StackPanel Margin="0,0,14,0"><TextBlock Text="RAM" Style="{StaticResource Label}"/><ProgressBar x:Name="BarRam" Style="{StaticResource Meter}" Margin="0,5,0,0"/></StackPanel>
                                                <StackPanel Margin="0,0,14,0"><TextBlock Text="STORAGE" Style="{StaticResource Label}"/><ProgressBar x:Name="BarSto" Style="{StaticResource Meter}" Margin="0,5,0,0"/></StackPanel>
                                            </UniformGrid>
                                        </StackPanel>
                                        <StackPanel Grid.Column="2" VerticalAlignment="Center">
                                            <Button x:Name="BtnAutoTune" Style="{StaticResource Primary}" Margin="0,0,0,10">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="&#xE945;" FontFamily="{StaticResource Icons}" Margin="0,1,8,0"/>
                                                    <TextBlock Text="AUTO-TUNE THIS PC"/>
                                                </StackPanel>
                                            </Button>
                                            <Button x:Name="BtnRescan" Style="{StaticResource Neon}" Margin="0,0,0,8" Content="RESCAN HARDWARE"/>
                                            <Button x:Name="BtnCopySpecs" Style="{StaticResource NeonViolet}" Margin="0" Content="COPY SPEC SHEET"/>
                                        </StackPanel>
                                    </Grid>
                                </Border>

                                <!-- live telemetry -->
                                <UniformGrid Columns="5" Margin="0,0,0,0">
                                    <Border Style="{StaticResource Card}" Padding="14,12">
                                        <StackPanel><TextBlock Text="CPU LOAD" Style="{StaticResource Label}"/><TextBlock x:Name="LiveCpu" Text="--" FontFamily="{StaticResource Display}" FontSize="24" FontWeight="SemiBold" Margin="0,4,0,6"/><ProgressBar x:Name="LiveCpuBar" Style="{StaticResource Meter}"/></StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}" Padding="14,12">
                                        <StackPanel><TextBlock Text="CPU CLOCK" Style="{StaticResource Label}"/><TextBlock x:Name="LiveClock" Text="--" FontFamily="{StaticResource Display}" FontSize="24" FontWeight="SemiBold" Margin="0,4,0,6"/><TextBlock x:Name="LiveClockSub" Text="" Style="{StaticResource Body}" FontSize="11"/></StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}" Padding="14,12">
                                        <StackPanel><TextBlock Text="MEMORY" Style="{StaticResource Label}"/><TextBlock x:Name="LiveRam" Text="--" FontFamily="{StaticResource Display}" FontSize="24" FontWeight="SemiBold" Margin="0,4,0,6"/><ProgressBar x:Name="LiveRamBar" Style="{StaticResource Meter}"/></StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}" Padding="14,12">
                                        <StackPanel><TextBlock Text="TEMPERATURE" Style="{StaticResource Label}"/><TextBlock x:Name="LiveTemp" Text="--" FontFamily="{StaticResource Display}" FontSize="24" FontWeight="SemiBold" Margin="0,4,0,6"/><TextBlock x:Name="LiveTempSub" Text="ACPI thermal zone" Style="{StaticResource Body}" FontSize="11"/></StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}" Padding="14,12">
                                        <StackPanel><TextBlock Text="UPTIME / PROCESSES" Style="{StaticResource Label}"/><TextBlock x:Name="LiveUp" Text="--" FontFamily="{StaticResource Display}" FontSize="24" FontWeight="SemiBold" Margin="0,4,0,6"/><TextBlock x:Name="LiveProcs" Text="" Style="{StaticResource Body}" FontSize="11"/></StackPanel>
                                    </Border>
                                </UniformGrid>

                                <!-- spec cards -->
                                <UniformGrid x:Name="SpecGrid" Columns="3"/>

                                <!-- insights -->
                                <Border Style="{StaticResource Card}">
                                    <StackPanel>
                                        <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                            <TextBlock Text="&#xE945;" FontFamily="{StaticResource Icons}" Foreground="#FF2BD6" FontSize="15" VerticalAlignment="Center"/>
                                            <TextBlock Text="SMART INSIGHTS FOR THIS PC" Style="{StaticResource H2}" Margin="10,0,0,0"/>
                                        </StackPanel>
                                        <StackPanel x:Name="InsightsPanel"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- ===================== TWEAKS ===================== -->
                        <Grid x:Name="PageTweaks" Visibility="Collapsed" Margin="24,20,12,0">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid Margin="0,0,12,12">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="340"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel>
                                    <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                    <TextBlock Text="TWEAKS" Style="{StaticResource H1}"/>
                                    <TextBlock Style="{StaticResource Body}" Margin="0,4,0,0" Text="Every switch shows the REAL state read from Windows right now. Flip what you want, then APPLY. Everything is logged and reversible."/>
                                </StackPanel>
                                <Grid Grid.Column="1" VerticalAlignment="Center">
                                    <TextBox x:Name="TweakSearch" Style="{StaticResource Input}"/>
                                    <TextBlock Text="&#xE721;" FontFamily="{StaticResource Icons}" Foreground="#5D6E92" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
                                    <TextBlock x:Name="TweakSearchHint" Text="Search tweaks... (Ctrl+F)" Foreground="#5D6E92" Margin="35,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
                                </Grid>
                            </Grid>
                            <WrapPanel x:Name="ChipPanel" Grid.Row="1" Margin="0,0,12,6"/>
                            <!-- Virtualized: only the rows on screen are laid out and drawn, so fast scrolling stays smooth -->
                            <ItemsControl x:Name="TweakList" Grid.Row="2" Focusable="False"
                                          VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Standard"
                                          VirtualizingPanel.ScrollUnit="Pixel" VirtualizingPanel.CacheLengthUnit="Page" VirtualizingPanel.CacheLength="1,1"
                                          ScrollViewer.CanContentScroll="True">
                                <ItemsControl.Template>
                                    <ControlTemplate TargetType="ItemsControl">
                                        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="True" Focusable="False" Padding="0,4,12,12">
                                            <ItemsPresenter/>
                                        </ScrollViewer>
                                    </ControlTemplate>
                                </ItemsControl.Template>
                                <ItemsControl.ItemsPanel>
                                    <ItemsPanelTemplate>
                                        <VirtualizingStackPanel/>
                                    </ItemsPanelTemplate>
                                </ItemsControl.ItemsPanel>
                            </ItemsControl>
                            <Border Grid.Row="3" Margin="0,0,12,12" CornerRadius="12" Padding="16,12" Background="#E60A1120" BorderBrush="#2A00E5FF" BorderThickness="1">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel VerticalAlignment="Center">
                                        <TextBlock x:Name="PendingText" Text="No pending changes" FontFamily="{StaticResource Display}" FontSize="15" FontWeight="SemiBold"/>
                                        <CheckBox x:Name="ChkRestorePoint" Style="{StaticResource Tick}" IsChecked="True" Margin="0,6,0,0">
                                            <TextBlock Text="Create a System Restore point before applying" Foreground="#8A9BBF" FontSize="12" TextWrapping="Wrap"/>
                                        </CheckBox>
                                    </StackPanel>
                                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                                        <Button x:Name="BtnReapply" Style="{StaticResource NeonAmber}" Content="RE-APPLY" Tag="dyn" Visibility="Collapsed"/>
                                        <Button x:Name="BtnSelectRec" Style="{StaticResource NeonViolet}" Content="SELECT RECOMMENDED"/>
                                        <Button x:Name="BtnClearPending" Style="{StaticResource Neon}" Content="UNDO SELECTION"/>
                                        <Button x:Name="BtnApply" Style="{StaticResource Primary}" Margin="0">
                                            <StackPanel Orientation="Horizontal">
                                                <TextBlock Text="&#xE73E;" FontFamily="{StaticResource Icons}" Margin="0,1,8,0"/>
                                                <TextBlock Text="APPLY CHANGES"/>
                                            </StackPanel>
                                        </Button>
                                    </StackPanel>
                                </Grid>
                            </Border>
                        </Grid>

                        <!-- ===================== PROFILES ===================== -->
                        <ScrollViewer x:Name="PageProfiles" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="24,20,12,8">
                            <StackPanel>
                                <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                    <TextBlock Text="PROFILES" Style="{StaticResource H1}"/>
                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,16" Text="One click, tuned to what was detected on this PC. PREVIEW stages the switches so you can review them first; APPLY does it now. Danger Zone items are never included."/>
                                <UniformGrid x:Name="ProfilePanel" Columns="2"/>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- ===================== GAMES ===================== -->
                        <ScrollViewer x:Name="PageGames" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="24,20,12,8">
                            <StackPanel>
                                <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                <TextBlock Text="GAMES" Style="{StaticResource H1}"/>
                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Competitive settings for popular shooters, matched to this PC. The app reads each game's own settings file to show what to change, and gives the launch options for the launcher you use. It never changes your game files."/>
                                <WrapPanel Margin="0,0,0,6">
                                    <Button x:Name="BtnScanGames" Style="{StaticResource Neon}" Content="RESCAN GAMES" Margin="0,0,8,8"/>
                                </WrapPanel>
                                <TextBlock x:Name="GamesHint" Text="" Style="{StaticResource Body}" Margin="0,0,0,12"/>
                                <StackPanel x:Name="GamesPanel" Margin="0,0,12,12"/>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- ===================== THEMES ===================== -->
                        <ScrollViewer x:Name="PageThemes" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="24,20,12,8">
                            <StackPanel>
                                <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                <TextBlock Text="THEMES" Style="{StaticResource H1}"/>
                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Desktop themes for Rainmeter: a clock that picks its text color from your wallpaper, a status bar, a dock and a wallpaper picker. Everything is made for this screen and can be removed in one click."/>
                                <Border Style="{StaticResource Card}">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <StackPanel Margin="0,0,12,0">
                                            <TextBlock Text="RAINMETER" Style="{StaticResource H2}"/>
                                            <TextBlock x:Name="ThemeRmText" Style="{StaticResource Body}" Margin="0,4,0,0" Text=""/>
                                        </StackPanel>
                                        <WrapPanel Grid.Column="1" VerticalAlignment="Center">
                                            <Button x:Name="BtnRmGet" Style="{StaticResource NeonViolet}" Content="GET RAINMETER" Margin="0,0,8,0" ToolTip="Opens rainmeter.net, the official site"/>
                                            <Button x:Name="BtnRmCheck" Style="{StaticResource Neon}" Content="CHECK AGAIN" Margin="0"/>
                                        </WrapPanel>
                                    </Grid>
                                </Border>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="LOOK" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,10" Text="Colors of the status bar, the dock and the wallpaper picker."/>
                                            <StackPanel x:Name="ThemeLookPanel"/>
                                            <TextBlock Text="WIDGETS" Style="{StaticResource H2}" Margin="0,8,0,8"/>
                                            <StackPanel x:Name="ThemeWidgetPanel"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Column="1" Style="{StaticResource Card}" VerticalAlignment="Top">
                                        <StackPanel>
                                            <TextBlock Text="PREVIEW" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,10" Text="Your wallpaper with these settings. It updates as you change them."/>
                                            <Border x:Name="ThemePreviewBox" CornerRadius="10" BorderBrush="#2A00E5FF" BorderThickness="1" Background="#0B0D12" Height="214" ClipToBounds="True">
                                                <Grid>
                                                    <Image x:Name="ThemePreviewImg" Stretch="UniformToFill"/>
                                                    <Grid x:Name="ThemePreviewLayer"/>
                                                </Grid>
                                            </Border>
                                            <TextBlock x:Name="ThemePreviewNote" Style="{StaticResource Body}" Margin="0,8,0,0" Text=""/>
                                        </StackPanel>
                                    </Border>
                                </Grid>
                                <Border Style="{StaticResource Card}">
                                    <StackPanel>
                                        <Grid Margin="0,0,0,10">
                                            <TextBlock Text="CLOCK" Style="{StaticResource H2}" VerticalAlignment="Center"/>
                                            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                                <RadioButton x:Name="ThemeTabGeneral" Style="{StaticResource Chip}" GroupName="themetab" Content="GENERAL" IsChecked="True"/>
                                                <RadioButton x:Name="ThemeTabLook" Style="{StaticResource Chip}" GroupName="themetab" Content="APPEARANCE"/>
                                            </StackPanel>
                                        </Grid>
                                        <StackPanel x:Name="ThemeClockPanel"/>
                                    </StackPanel>
                                </Border>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="WALLPAPERS" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,10" Text="The picker (left button of the status bar) shows the pictures in these folders, sorted by color. CREATE OZZYHN WALLPAPERS draws six original wallpapers for this theme."/>
                                            <StackPanel x:Name="ThemeWallPanel" Margin="0,0,0,6"/>
                                            <WrapPanel>
                                                <Button x:Name="BtnWallMake" Style="{StaticResource NeonViolet}" Content="CREATE OZZYHN WALLPAPERS" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnWallAdd" Style="{StaticResource Neon}" Content="ADD FOLDER" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnWallOpen" Style="{StaticResource Neon}" Content="OPEN PICKER" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                        </StackPanel>
                                    </Border>
                                    <Border Grid.Column="1" Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="DOCK APPS" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,10" Text="Only apps installed on this PC are listed. They open as you, never as administrator."/>
                                            <WrapPanel x:Name="ThemeDockPanel" Margin="0,0,0,4"/>
                                            <Button x:Name="BtnDockAdd" Style="{StaticResource Neon}" Content="ADD APP" HorizontalAlignment="Left" Margin="0,4,0,0"/>
                                        </StackPanel>
                                    </Border>
                                </Grid>
                                <Border Style="{StaticResource Card}">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto"/>
                                            <ColumnDefinition Width="*"/>
                                        </Grid.ColumnDefinitions>
                                        <StackPanel Orientation="Horizontal">
                                            <Button x:Name="BtnThemeApply" Style="{StaticResource Primary}" Content="APPLY THEME"/>
                                            <Button x:Name="BtnThemeRemove" Style="{StaticResource NeonDanger}" Content="REMOVE THEME"/>
                                        </StackPanel>
                                        <TextBlock x:Name="ThemeStatus" Grid.Column="1" Style="{StaticResource Body}" VerticalAlignment="Center" Margin="12,0,0,0" Text=""/>
                                    </Grid>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- ===================== DEBLOAT ===================== -->
                        <Grid x:Name="PageDebloat" Visibility="Collapsed" Margin="24,20,12,0">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <StackPanel Margin="0,0,12,12">
                                <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                    <TextBlock Text="DEBLOAT" Style="{StaticResource H1}"/>
                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Only apps actually installed on this PC are listed. Core Windows apps (Store, Calculator, Notepad, Terminal, Security) are protected and never shown. Removed apps can be reinstalled from the Microsoft Store."/>
                                <WrapPanel>
                                    <Button x:Name="BtnScanApps" Style="{StaticResource Neon}" Content="SCAN INSTALLED APPS" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnBloatRec" Style="{StaticResource NeonViolet}" Content="SELECT RECOMMENDED" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnBloatNone" Style="{StaticResource Neon}" Content="SELECT NONE" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnBloatRemove" Style="{StaticResource NeonDanger}" Content="REMOVE SELECTED" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnEdgeUninstall" Style="{StaticResource NeonDanger}" Content="TRY OFFICIAL EDGE UNINSTALL" Margin="0,0,8,8" ToolTip="Uses winget. Works only where Microsoft allows it (EEA). WebView2 stays installed."/>
                                </WrapPanel>
                            </StackPanel>
                            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,12,0">
                                <StackPanel>
                                    <TextBlock x:Name="BloatHint" Text="Press SCAN INSTALLED APPS to list removable apps." Style="{StaticResource Body}" Margin="0,0,0,10"/>
                                    <UniformGrid x:Name="BloatList" Columns="2" Margin="0,0,0,12"/>
                                </StackPanel>
                            </ScrollViewer>
                        </Grid>

                        <!-- ===================== DRIVERS ===================== -->
                        <ScrollViewer x:Name="PageDrivers" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="24,20,12,8">
                            <StackPanel>
                                <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                    <TextBlock Text="DRIVERS" Style="{StaticResource H1}"/>
                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Recommendations come from the hardware found on this PC and always point to the official source - never to driver-updater junkware."/>
                                <WrapPanel Margin="0,0,0,14">
                                    <Button x:Name="BtnScanDrivers" Style="{StaticResource Neon}" Content="SCAN DRIVERS &amp; DEVICES" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnDevMgr" Style="{StaticResource NeonViolet}" Content="DEVICE MANAGER" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnPnpScan" Style="{StaticResource Neon}" Content="DETECT NEW HARDWARE" Margin="0,0,8,8"/>
                                </WrapPanel>
                                <TextBlock Text="RECOMMENDED DOWNLOADS" Style="{StaticResource Label}" Margin="0,0,0,8"/>
                                <UniformGrid x:Name="DriverRecPanel" Columns="2"/>
                                <TextBlock Text="DEVICES WITH PROBLEMS" Style="{StaticResource Label}" Margin="0,6,0,8"/>
                                <StackPanel x:Name="DriverProblemPanel" Margin="0,0,12,12"/>
                                <TextBlock Text="INSTALLED KEY DRIVERS" Style="{StaticResource Label}" Margin="0,6,0,8"/>
                                <StackPanel x:Name="DriverListPanel" Margin="0,0,12,12"/>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- ===================== TOOLS ===================== -->
                        <ScrollViewer x:Name="PageTools" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="24,20,12,8">
                            <StackPanel>
                                <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                    <TextBlock Text="TOOLS" Style="{StaticResource H1}"/>
                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,16" Text="Cleanup, repair, DNS, power, storage and startup control. Long built-in tools open in their own window so you can watch them."/>
                                <Border Style="{StaticResource Card}">
                                    <StackPanel>
                                        <TextBlock Text="CLEAN UP FILES" Style="{StaticResource H2}"/>
                                        <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Pick the drives, press SCAN, then tick what to delete. Only Windows cache folders and Recycle Bins are listed - never your own files. Recommended items are ticked for you."/>
                                        <TextBlock Text="DRIVES" Style="{StaticResource Label}" Margin="0,0,0,8"/>
                                        <WrapPanel x:Name="CleanDrivePanel" Margin="0,0,0,6"/>
                                        <WrapPanel>
                                            <Button x:Name="BtnCleanScan" Style="{StaticResource Neon}" Content="SCAN" Margin="0,0,8,8"/>
                                            <Button x:Name="BtnCleanRec" Style="{StaticResource NeonViolet}" Content="SELECT RECOMMENDED" Margin="0,0,8,8"/>
                                            <Button x:Name="BtnCleanNone" Style="{StaticResource Neon}" Content="SELECT NONE" Margin="0,0,8,8"/>
                                            <Button x:Name="BtnCleanSelected" Style="{StaticResource NeonDanger}" Content="CLEAN SELECTED" Margin="0,0,8,8"/>
                                        </WrapPanel>
                                        <TextBlock x:Name="CleanHint" Text="Pick the drives, then press SCAN to see what can be cleaned on them." Style="{StaticResource Body}" Margin="0,2,0,10"/>
                                        <StackPanel x:Name="CleanList"/>
                                        <TextBlock x:Name="CleanTotal" Text="" Foreground="#E6F1FF" FontSize="12.5" Margin="0,2,0,0"/>
                                        <TextBlock x:Name="CleanResult" Text="" Foreground="#2BFF9A" FontSize="12" Margin="0,4,0,0"/>
                                    </StackPanel>
                                </Border>
                                <UniformGrid Columns="2">
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="WINDOWS CLEANUP TOOLS" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Windows' own cleaners. DEEP CLEAN removes old update files that Windows keeps in its component store. DISK CLEANUP opens the classic tool."/>
                                            <WrapPanel>
                                                <Button x:Name="BtnDeepClean" Style="{StaticResource NeonViolet}" Content="DEEP CLEAN (DISM)" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnCleanMgr" Style="{StaticResource Neon}" Content="DISK CLEANUP" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                        </StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="REPAIR WINDOWS" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Fix corrupted system files, broken networking and disk errors - the classic toolkit for a PC that acts weird."/>
                                            <WrapPanel>
                                                <Button x:Name="BtnSfc" Style="{StaticResource Neon}" Content="DISM + SFC REPAIR" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnNetReset" Style="{StaticResource NeonViolet}" Content="RESET NETWORK STACK" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnChkdsk" Style="{StaticResource Neon}" Content="SCAN DISK" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                        </StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="DNS" Style="{StaticResource H2}"/>
                                            <TextBlock x:Name="DnsCurrent" Style="{StaticResource Body}" Margin="0,4,0,12" Text="Faster, more private name resolution for every connected adapter."/>
                                            <WrapPanel x:Name="DnsPanel"/>
                                            <Button x:Name="BtnApplyDns" Style="{StaticResource Neon}" Content="APPLY DNS" HorizontalAlignment="Left" Margin="0,6,0,0"/>
                                        </StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="POWER &amp; THERMALS" Style="{StaticResource H2}"/>
                                            <TextBlock x:Name="PowerCurrent" Style="{StaticResource Body}" Margin="0,4,0,12" Text=""/>
                                            <WrapPanel>
                                                <Button x:Name="BtnPlanPerf" Style="{StaticResource Neon}" Content="PERFORMANCE" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnPlanSmart" Style="{StaticResource NeonViolet}" Content="SMART" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnPlanCool" Style="{StaticResource Neon}" Content="COOL" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnPlanReset" Style="{StaticResource NeonDanger}" Content="RESET PLANS" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnBatteryReport" Style="{StaticResource Neon}" Content="BATTERY REPORT" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                        </StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="STORAGE" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="CompactOS compresses Windows itself and frees 2-4 GB - a lifesaver on 32/64 GB eMMC laptops. Slight CPU cost when loading files."/>
                                            <WrapPanel>
                                                <Button x:Name="BtnCompactOn" Style="{StaticResource Neon}" Content="COMPACT OS ON" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnCompactOff" Style="{StaticResource NeonViolet}" Content="COMPACT OS OFF" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnOptimizeDrives" Style="{StaticResource Neon}" Content="OPTIMIZE DRIVES" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                        </StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="WINDOWS SHORTCUTS" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Jump straight into the classic control panels."/>
                                            <WrapPanel x:Name="ShortcutPanel"/>
                                        </StackPanel>
                                    </Border>
                                </UniformGrid>
                                <Border Style="{StaticResource Card}">
                                    <StackPanel>
                                        <Grid Margin="0,0,0,10">
                                            <StackPanel>
                                                <TextBlock Text="STARTUP APPS" Style="{StaticResource H2}"/>
                                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,0" Text="Switch off what you do not need at boot. Same mechanism as Task Manager, so nothing is deleted."/>
                                            </StackPanel>
                                            <Button x:Name="BtnRefreshStartup" Style="{StaticResource Neon}" Content="REFRESH" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0"/>
                                        </Grid>
                                        <StackPanel x:Name="StartupPanel"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- ===================== BACKUP ===================== -->
                        <ScrollViewer x:Name="PageBackup" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" Padding="24,20,12,8">
                            <StackPanel>
                                <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                    <TextBlock Text="BACKUP &amp; UNDO" Style="{StaticResource H1}"/>
                                <TextBlock Style="{StaticResource Body}" Margin="0,4,0,16" Text="Before any value is changed, its original is saved to an undo journal. Revert one tweak, or everything, at any time - even after updates or reinstalling this tool."/>
                                <UniformGrid Columns="2">
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="SYSTEM RESTORE" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="A full Windows snapshot of system settings and drivers."/>
                                            <WrapPanel>
                                                <Button x:Name="BtnRestorePoint" Style="{StaticResource Neon}" Content="CREATE RESTORE POINT" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnOpenRestore" Style="{StaticResource NeonViolet}" Content="OPEN SYSTEM RESTORE" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                        </StackPanel>
                                    </Border>
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="SETUP FILE" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Save your active tweaks and load them on another PC. Imported tweaks are staged for review first."/>
                                            <WrapPanel>
                                                <Button x:Name="BtnExport" Style="{StaticResource Neon}" Content="EXPORT MY SETUP" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnImport" Style="{StaticResource NeonViolet}" Content="IMPORT SETUP" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnOpenData" Style="{StaticResource Neon}" Content="OPEN DATA FOLDER" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                        </StackPanel>
                                    </Border>
                                </UniformGrid>
                                <Border Style="{StaticResource Card}">
                                    <StackPanel>
                                        <Grid Margin="0,0,0,10">
                                            <StackPanel>
                                                <TextBlock Text="UNDO JOURNAL" Style="{StaticResource H2}"/>
                                                <TextBlock x:Name="JournalSummary" Style="{StaticResource Body}" Margin="0,4,0,0" Text=""/>
                                            </StackPanel>
                                            <Button x:Name="BtnRevertAll" Style="{StaticResource NeonDanger}" Content="REVERT EVERYTHING" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0"/>
                                        </Grid>
                                        <StackPanel x:Name="JournalPanel"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- ===================== LOG ===================== -->
                        <Grid x:Name="PageLog" Visibility="Collapsed" Margin="24,20,24,16">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <Grid Margin="0,0,0,12">
                                <StackPanel>
                                    <TextBlock Text="OZZYHN TWEAKS  //" Style="{StaticResource Kicker}"/>
                                    <TextBlock Text="LOG" Style="{StaticResource H1}"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                    <Button x:Name="BtnCopyLog" Style="{StaticResource Neon}" Content="COPY LOG"/>
                                    <Button x:Name="BtnOpenLogs" Style="{StaticResource NeonViolet}" Content="OPEN LOG FOLDER" Margin="0"/>
                                </StackPanel>
                            </Grid>
                            <Border Grid.Row="1" CornerRadius="12" Background="#E6040810" BorderBrush="#1B2A48" BorderThickness="1" Padding="4">
                                <TextBox x:Name="LogBox" IsReadOnly="True" Background="Transparent" Foreground="#9FE9FF" BorderThickness="0" FontFamily="{StaticResource Mono}" FontSize="12" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Padding="10"/>
                            </Border>
                        </Grid>
                    </Grid>
                </Grid>

                <!-- ============ STATUS BAR ============ -->
                <Grid Grid.Row="2" Background="#C0040810">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="220"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Rectangle Grid.ColumnSpan="5" Height="1" VerticalAlignment="Top" Fill="#1B2A48"/>
                    <TextBlock Text="&#xE9D9;" FontFamily="{StaticResource Icons}" Foreground="#00E5FF" Margin="16,0,10,0" VerticalAlignment="Center" FontSize="12"/>
                    <TextBlock x:Name="StatusText" Grid.Column="1" Text="Ready" Foreground="#8A9BBF" FontSize="12" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                    <Grid Grid.Column="2" Margin="0,0,14,0" VerticalAlignment="Center">
                        <ProgressBar x:Name="ApplyProgress" Style="{StaticResource Meter}" Height="4" Visibility="Collapsed"/>
                        <Grid x:Name="BusyBar" Height="4" ClipToBounds="True" Visibility="Collapsed">
                            <Border CornerRadius="2" Background="#16FFFFFF"/>
                            <Rectangle Width="70" HorizontalAlignment="Left" RadiusX="2" RadiusY="2" Fill="{StaticResource NeonGrad}">
                                <Rectangle.RenderTransform>
                                    <TranslateTransform/>
                                </Rectangle.RenderTransform>
                                <Rectangle.Triggers>
                                    <EventTrigger RoutedEvent="FrameworkElement.Loaded">
                                        <BeginStoryboard>
                                            <Storyboard RepeatBehavior="Forever" Timeline.DesiredFrameRate="30">
                                                <DoubleAnimation Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" From="-70" To="220" Duration="0:0:1.2"/>
                                            </Storyboard>
                                        </BeginStoryboard>
                                    </EventTrigger>
                                </Rectangle.Triggers>
                            </Rectangle>
                        </Grid>
                    </Grid>
                    <TextBlock x:Name="FooterText" Grid.Column="3" Text="" Foreground="#5D6E92" FontSize="11" Margin="0,0,14,0" VerticalAlignment="Center" FontFamily="{StaticResource Mono}"/>
                    <TextBlock Grid.Column="4" Text="OZZYHN TWEAKS" Margin="0,0,16,0" VerticalAlignment="Center" FontFamily="{StaticResource Display}" FontSize="11" FontWeight="Bold" Foreground="{StaticResource NeonGrad}"/>
                </Grid>
            </Grid>
        </Grid>
    </Border>
</Window>
'@
#endregion

#region ============================ UI PRIMITIVES ============================
$Oz.BrushCache = @{}
function Get-OzBrush {
    param([string]$Hex)
    if (-not $Oz.BrushCache.ContainsKey($Hex)) {
        $b = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Hex)
        $b.Freeze()
        $Oz.BrushCache[$Hex] = $b
    }
    $Oz.BrushCache[$Hex]
}

function New-OzThickness {
    param([string]$Spec)
    $p = @($Spec -split ',' | ForEach-Object { [double]$_ })
    switch ($p.Count) {
        1 { New-Object System.Windows.Thickness($p[0]) }
        2 { New-Object System.Windows.Thickness($p[0], $p[1], $p[0], $p[1]) }
        default { New-Object System.Windows.Thickness($p[0], $p[1], $p[2], $p[3]) }
    }
}

function New-OzText {
    param(
        [string]$Text, [double]$Size = 12.5, [string]$Color = '#8A9BBF', [string]$Margin = '0',
        [switch]$Bold, [switch]$Semi, [switch]$Display, [switch]$Mono, [switch]$Icon, [switch]$Wrap
    )
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.Foreground = Get-OzBrush $Color
    $t.Margin = New-OzThickness $Margin
    if ($Bold) { $t.FontWeight = [System.Windows.FontWeights]::Bold }
    if ($Semi) { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
    if ($Display) { $t.FontFamily = $Oz.Window.FindResource('Display') }
    if ($Mono) { $t.FontFamily = $Oz.Window.FindResource('Mono') }
    if ($Icon) { $t.FontFamily = $Oz.Window.FindResource('Icons') }
    if ($Wrap) { $t.TextWrapping = [System.Windows.TextWrapping]::Wrap }
    $t
}

function New-OzBadge {
    param([string]$Text, [string]$Color)
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = New-Object System.Windows.CornerRadius(8)
    $b.Padding = New-OzThickness '7,1,7,1'
    $b.Margin = New-OzThickness '6,0,0,0'
    $b.BorderThickness = New-OzThickness '1'
    $b.BorderBrush = Get-OzBrush ('#66' + $Color.TrimStart('#'))
    $b.Background = Get-OzBrush ('#14' + $Color.TrimStart('#'))
    $b.VerticalAlignment = 'Center'
    $tx = New-OzText -Text $Text -Size 10 -Color $Color -Display -Semi
    $b.Child = $tx
    $b
}

function New-OzButton {
    param([string]$Text, [string]$Style = 'Neon', $Tag, [string]$Margin = '0,0,8,0')
    $b = New-Object System.Windows.Controls.Button
    $b.Content = $Text
    $b.Style = $Oz.Window.FindResource($Style)
    $b.Tag = $Tag
    $b.Margin = New-OzThickness $Margin
    $b
}

function New-OzRowBorder {
    param([string]$Margin = '0,0,0,8', [string]$Padding = '14,10,14,10')
    $b = New-Object System.Windows.Controls.Border
    $b.Background = Get-OzBrush '#990B1324'
    $b.BorderBrush = Get-OzBrush '#16233D'
    $b.BorderThickness = New-OzThickness '1'
    $b.CornerRadius = New-Object System.Windows.CornerRadius(10)
    $b.Padding = New-OzThickness $Padding
    $b.Margin = New-OzThickness $Margin
    $b
}

function New-OzCard {
    $b = New-Object System.Windows.Controls.Border
    $b.Style = $Oz.Window.FindResource('Card')
    $b
}

function Add-OzGridChild {
    param($Grid, $Child, [int]$Column = 0, [int]$Row = 0)
    [System.Windows.Controls.Grid]::SetColumn($Child, $Column)
    [System.Windows.Controls.Grid]::SetRow($Child, $Row)
    [void]$Grid.Children.Add($Child)
}

function New-OzColumns {
    param([string[]]$Widths)
    $g = New-Object System.Windows.Controls.Grid
    foreach ($w in $Widths) {
        $c = New-Object System.Windows.Controls.ColumnDefinition
        $c.Width = if ($w -eq 'Auto') { [System.Windows.GridLength]::Auto }
        elseif ($w -eq '*') { New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        else { New-Object System.Windows.GridLength([double]$w) }
        [void]$g.ColumnDefinitions.Add($c)
    }
    $g
}

function Show-OzPage {
    param([string]$Name)
    foreach ($p in 'Dash', 'Tweaks', 'Profiles', 'Games', 'Themes', 'Debloat', 'Drivers', 'Tools', 'Backup', 'Log') {
        $el = $Oz.UI["Page$p"]
        if ($el) { $el.Visibility = $(if ($p -eq $Name) { 'Visible' } else { 'Collapsed' }) }
    }
    $Oz.LiveWanted = ($Name -eq 'Dash')
    if ($Name -eq 'Tools' -and -not $Oz.ToolsShown -and $Oz.Sys) { $Oz.ToolsShown = $true; Initialize-OzTools }
    if ($Name -eq 'Drivers' -and -not $Oz.DriversShown -and $Oz.Sys -and -not $Oz.Busy) {
        $Oz.DriversShown = $true
        Show-OzDriverRecs
        Invoke-OzSafe 'Driver scan' { Show-OzDriverScan (Get-OzDriverScan) }
    }
    if ($Name -eq 'Debloat' -and -not $Oz.BloatShown -and $Oz.Sys -and -not $Oz.Busy) {
        $Oz.BloatShown = $true
        Invoke-OzSafe 'App scan' { Show-OzBloat (Get-OzInstalledBloat) }
    }
    if ($Name -eq 'Backup') { Update-OzJournalView }
    if ($Name -eq 'Themes' -and -not $Oz.ThemesShown) {
        try { Show-OzThemes } catch { Write-OzLog ((T '{0} failed: {1}') -f (T 'Themes'), $_.Exception.Message) 'ERR' }
    } elseif ($Name -eq 'Themes') {
        try { Update-OzThemeStatus; Update-OzThemePreview } catch { Write-OzLog ((T '{0} failed: {1}') -f (T 'Themes'), $_.Exception.Message) 'ERR' }
    }
    if ($Name -eq 'Games' -and -not $Oz.GamesShown -and $Oz.Sys -and -not $Oz.Busy) {
        $Oz.GamesShown = $true
        Invoke-OzSafe 'Game scan' { Show-OzGames (Get-OzGameScan) }
    }
}

function Remove-OzAccents {
    # "telemetria" finds "telemetria" with or without the accent
    param([string]$Text)
    $d = $Text.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    $sb.ToString().ToLowerInvariant()
}

function Get-OzBothLang {
    # English + Spanish text, used so search works in either language
    param([string]$Text)
    if (-not $Text) { return '' }
    $v = $null
    $es = if ($Oz.Es.TryGetValue($Text, [ref]$v) -and $v) { [System.Net.WebUtility]::HtmlDecode($v) } else { '' }
    '{0} {1}' -f $Text, $es
}

function Set-OzWindowIcon {
    # Taskbar / Alt+Tab icon drawn from the same OZ mark as the logo
    try {
        $dv = New-Object System.Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $dc.DrawRoundedRectangle((Get-OzBrush '#05070D'), $null, (New-Object System.Windows.Rect(0, 0, 64, 64)), 14, 14)
        $dc.PushTransform((New-Object System.Windows.Media.ScaleTransform(0.64, 0.64)))
        $pen = New-Object System.Windows.Media.Pen($Oz.Window.FindResource('NeonGrad'), 8)
        $pen.LineJoin = 'Round'
        $dc.DrawGeometry((Get-OzBrush '#2200E5FF'), $pen, $Oz.Window.FindResource('OzHex'))
        $dc.DrawGeometry((Get-OzBrush '#E6F1FF'), $null, $Oz.Window.FindResource('OzMark'))
        $dc.Pop()
        $dc.Close()
        $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(64, 64, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($dv)
        $bmp.Freeze()
        $Oz.Window.Icon = $bmp
    } catch { }
}
#endregion

#region ============================ DIALOGS ============================
function Show-OzDialog {
    # Neon replacement for MessageBox, in the app's own style. Returns 'Yes', 'No', 'Cancel' or 'OK',
    # like MessageBox did. Enter picks the first button; Esc or closing picks the last one.
    #   -Labels: button texts in order (Yes, No, Cancel / OK). Missing ones use YES, NO, CANCEL, OK.
    #   -Rows:   extra lines under the text, each @{ Text = ''; Color = '#hex'; Glyph = [char]0x... }
    param(
        [string]$Text,
        [ValidateSet('OK', 'YesNo', 'YesNoCancel')][string]$Buttons = 'OK',
        [ValidateSet('Info', 'Question', 'Warning', 'Error', 'Success')][string]$Kind = 'Info',
        [string]$Title = '',
        [string[]]$Labels = @(),
        [object[]]$Rows = @()
    )
    $results = switch ($Buttons) { 'OK' { @('OK') } 'YesNo' { @('Yes', 'No') } default { @('Yes', 'No', 'Cancel') } }
    $last = $results[$results.Count - 1]
    if (-not $Oz.Window -or -not $Oz.Window.IsLoaded) {
        # Before the main window is up there is nothing to style a dialog with
        $img = switch ($Kind) { 'Warning' { 'Warning' } 'Error' { 'Error' } 'Question' { 'Question' } default { 'Information' } }
        try { return [string][System.Windows.MessageBox]::Show($Text, $Oz.AppName, $Buttons, $img) } catch { return $last }
    }
    $accent = switch ($Kind) { 'Question' { '#8A5CFF' } 'Warning' { '#FFB020' } 'Error' { '#FF3B5C' } 'Success' { '#2BFF9A' } default { '#00E5FF' } }
    $glyph = switch ($Kind) { 'Question' { [char]0xE9CE } 'Warning' { [char]0xE7BA } 'Error' { [char]0xEA39 } 'Success' { [char]0xE73E } default { [char]0xE946 } }
    if (-not $Title) { $Title = $Oz.AppName }

    $dlg = New-Object System.Windows.Window
    $dlg.WindowStyle = 'None'
    $dlg.ResizeMode = 'NoResize'
    $dlg.SizeToContent = 'WidthAndHeight'
    $dlg.ShowInTaskbar = $false
    $dlg.Owner = $Oz.Window
    $dlg.WindowStartupLocation = 'CenterOwner'
    $dlg.Title = $Oz.AppName
    $dlg.Background = Get-OzBrush '#05070D'
    $dlg.Foreground = Get-OzBrush '#E6F1FF'
    $dlg.FontFamily = New-Object System.Windows.Media.FontFamily('Segoe UI')
    $dlg.FontSize = 13
    $dlg.UseLayoutRounding = $true
    $dlg.Tag = $last
    $dlg.Add_MouseLeftButtonDown({ try { $this.DragMove() } catch { } })

    $outer = New-Object System.Windows.Controls.Border
    $outer.BorderBrush = Get-OzBrush ('#99' + $accent.TrimStart('#'))
    $outer.BorderThickness = New-OzThickness '1'
    $grid = New-OzColumns @('Auto', '*')
    $bar = New-Object System.Windows.Controls.Border
    $bar.Width = 4
    $bar.Background = Get-OzBrush $accent
    Add-OzGridChild $grid $bar 0
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = New-OzThickness '22,18,24,18'
    $sp.MinWidth = 360
    $sp.MaxWidth = 540
    $head = New-Object System.Windows.Controls.StackPanel
    $head.Orientation = 'Horizontal'
    $gi = New-OzText -Text ([string]$glyph) -Size 18 -Color $accent -Icon -Margin '0,0,10,0'
    $gi.VerticalAlignment = 'Center'
    [void]$head.Children.Add($gi)
    $ti = New-OzText -Text $Title -Size 15 -Color '#E6F1FF' -Display -Bold
    $ti.VerticalAlignment = 'Center'
    [void]$head.Children.Add($ti)
    [void]$sp.Children.Add($head)
    if ($Text) { [void]$sp.Children.Add((New-OzText -Text $Text -Size 13 -Color '#C9D6EE' -Wrap -Margin '0,12,0,0')) }
    foreach ($r in @($Rows)) {
        if (-not $r) { continue }
        $line = New-OzColumns @('Auto', '*')
        $line.Margin = New-OzThickness '0,8,0,0'
        $color = if ($r.Color) { [string]$r.Color } else { '#8A9BBF' }
        if ($r.Glyph) { Add-OzGridChild $line (New-OzText -Text ([string]$r.Glyph) -Size 13 -Color $color -Icon -Margin '0,2,10,0') 0 }
        Add-OzGridChild $line (New-OzText -Text ([string]$r.Text) -Size 13 -Color $color -Wrap) 1
        [void]$sp.Children.Add($line)
    }
    $btns = New-Object System.Windows.Controls.StackPanel
    $btns.Orientation = 'Horizontal'
    $btns.HorizontalAlignment = 'Right'
    $btns.Margin = New-OzThickness '0,20,0,0'
    $defaults = @{ Yes = (T 'YES'); No = (T 'NO'); Cancel = (T 'CANCEL'); OK = (T 'OK') }
    for ($i = 0; $i -lt $results.Count; $i++) {
        $res = $results[$i]
        $label = if ($Labels.Count -gt $i -and $Labels[$i]) { $Labels[$i] } else { $defaults[$res] }
        $style = if ($i -eq 0) { 'Primary' } else { 'Neon' }
        $b = New-OzButton -Text $label -Style $style -Tag $res -Margin '8,0,0,0'
        if ($i -eq 0) { $b.IsDefault = $true }
        if ($i -eq $results.Count - 1) { $b.IsCancel = $true }
        $b.Add_Click({
                $w = [System.Windows.Window]::GetWindow($this)
                $w.Tag = [string]$this.Tag
                $w.Close()
            })
        [void]$btns.Children.Add($b)
    }
    [void]$sp.Children.Add($btns)
    Add-OzGridChild $grid $sp 1
    $outer.Child = $grid
    $dlg.Content = $outer
    $Oz.Dialog = $dlg
    try { [void]$dlg.ShowDialog() } finally { $Oz.Dialog = $null }
    [string]$dlg.Tag
}

function Invoke-OzSearchShortcut {
    # Ctrl+F from any page: open TWEAKS and put the cursor in the search box
    $Oz.UI.NavTweaks.IsChecked = $true
    [void]$Oz.Window.Dispatcher.BeginInvoke([Action] {
            [void]$Oz.UI.TweakSearch.Focus()
            $Oz.UI.TweakSearch.SelectAll()
        }, [System.Windows.Threading.DispatcherPriority]::Input)
}
#endregion

#region ============================ LANGUAGE (UI) ============================
function Register-OzXamlTexts {
    # Remembers every fixed English text in the window so it can be swapped to Spanish and back.
    # Named TextBlocks and anything tagged "dyn" are filled in by code instead.
    $Oz.XamlTexts = New-Object System.Collections.ArrayList
    Add-OzXamlTextNode $Oz.Window
}

function Add-OzXamlTextNode {
    param($Node)
    if ($Node -is [System.Windows.FrameworkElement] -and [string]$Node.Tag -eq 'dyn') { return }
    if ($Node -is [System.Windows.Controls.TextBlock]) {
        if (-not $Node.Name -and $Node.Inlines.Count -le 1 -and $Node.Text -match '[A-Za-z]{2}') {
            [void]$Oz.XamlTexts.Add(@{ El = $Node; Prop = 'Text'; En = $Node.Text })
        }
    } elseif ($Node -is [System.Windows.Controls.ContentControl] -and $Node.Content -is [string]) {
        if ($Node.Content -match '[A-Za-z]{2}') { [void]$Oz.XamlTexts.Add(@{ El = $Node; Prop = 'Content'; En = $Node.Content }) }
    }
    if ($Node -is [System.Windows.FrameworkElement] -and $Node.ToolTip -is [string] -and $Node.ToolTip -match '[A-Za-z]{2}') {
        [void]$Oz.XamlTexts.Add(@{ El = $Node; Prop = 'ToolTip'; En = $Node.ToolTip })
    }
    foreach ($c in [System.Windows.LogicalTreeHelper]::GetChildren($Node)) {
        if ($c -is [System.Windows.DependencyObject]) { Add-OzXamlTextNode $c }
    }
}

function Set-OzLanguage {
    param([ValidateSet('en', 'es')][string]$Lang, [switch]$Save)
    $Oz.Lang = $Lang
    foreach ($x in @($Oz.XamlTexts)) { try { $x.El.($x.Prop) = T $x.En } catch { } }
    $ui = $Oz.UI
    $ui.TweakSearchHint.Text = (T 'Search tweaks...') + '  (Ctrl+F)'
    $ui.AdminText.Text = T 'ADMIN MODE'
    if (-not $Oz.Sys) {
        $ui.TierText.Text = T 'SCANNING HARDWARE...'
        $ui.TierChipText.Text = T 'SCANNING...'
    }
    if (-not $Oz.BloatShown) { $ui.BloatHint.Text = T 'Press SCAN INSTALLED APPS to list removable apps.' }
    if (-not $Oz.ToolsShown) { $ui.DnsCurrent.Text = T 'Faster, more private name resolution for every connected adapter.' }
    if ($ui.LangEn.IsChecked -ne ($Lang -eq 'en')) { $ui.LangEn.IsChecked = ($Lang -eq 'en') }
    if ($ui.LangEs.IsChecked -ne ($Lang -eq 'es')) { $ui.LangEs.IsChecked = ($Lang -eq 'es') }

    if ($Oz.Sys) { Update-OzDashboard; if ($Oz.LiveShown) { Update-OzLive $Oz.LiveShown } }
    foreach ($row in @($Oz.Rows.Values)) { Set-OzRowText $row; Set-OzRowBadges $row; Set-OzRowVisual $row }
    foreach ($k in @($Oz.CatHeaders.Keys)) { Set-OzCatHeaderText $k }
    if ($Oz.Rows.Count) { Update-OzChipLabels; Update-OzPendingBar; Update-OzActiveCount }
    if ($Oz.ProfileStats) { Initialize-OzProfileCards }
    if ($Oz.BloatShown -and $null -ne $Oz.LastBloat) { Show-OzBloat $Oz.LastBloat }
    if ($Oz.DriversShown) { Show-OzDriverRecs; if ($Oz.LastDriverScan) { Show-OzDriverScan $Oz.LastDriverScan -Quiet } }
    if ($Oz.ToolsShown) { Initialize-OzTools }
    if ($Oz.GamesShown) { Show-OzGames (Get-OzGameScan) } else { $ui.GamesHint.Text = T 'The game check starts after the hardware scan.' }
    if ($Oz.ThemesShown) { try { Show-OzThemes } catch { Write-OzLog ((T '{0} failed: {1}') -f (T 'Themes'), $_.Exception.Message) 'ERR' } }
    Update-OzCleanText
    Update-OzJournalView
    if ($Save) { Save-OzSettings; Write-OzLog (T 'Language: English') 'OK' }
}
#endregion

#region ============================ DASHBOARD ============================
function Set-OzRing {
    param([double]$Percent)
    $r = 70.0; $cx = 85.0; $cy = 85.0
    $f = [math]::Max(0.002, [math]::Min(0.9995, $Percent / 100.0))
    $a = 2 * [math]::PI * $f - [math]::PI / 2
    $x = $cx + $r * [math]::Cos($a)
    $y = $cy + $r * [math]::Sin($a)
    $large = if ($f -gt 0.5) { 1 } else { 0 }
    $data = 'M {0},{1} A {2},{2} 0 {3} 1 {4},{5}' -f (Format-OzNum $cx), (Format-OzNum ($cy - $r)), (Format-OzNum $r), $large, (Format-OzNum $x), (Format-OzNum $y)
    $geo = [System.Windows.Media.Geometry]::Parse($data)
    $Oz.UI.ScoreRing.Data = $geo
    $Oz.UI.ScoreGlow.Data = $geo
}

function New-OzSpecCard {
    param([string]$Title, [string]$Main, [string[]]$Lines, [int]$Score = -1, [string]$Accent = '#00E5FF')
    $card = New-OzCard
    $sp = New-Object System.Windows.Controls.StackPanel
    $head = New-Object System.Windows.Controls.StackPanel
    $head.Orientation = 'Horizontal'
    $bar = New-Object System.Windows.Controls.Border
    $bar.Width = 3; $bar.Height = 12; $bar.CornerRadius = New-Object System.Windows.CornerRadius(2)
    $bar.Background = Get-OzBrush $Accent
    [void]$head.Children.Add($bar)
    $lbl = New-OzText -Text $Title -Size 10.5 -Color '#5D6E92' -Display -Semi -Margin '8,0,0,0'
    [void]$head.Children.Add($lbl)
    [void]$sp.Children.Add($head)
    [void]$sp.Children.Add((New-OzText -Text $Main -Size 15 -Color '#E6F1FF' -Display -Semi -Wrap -Margin '0,8,0,6'))
    foreach ($l in $Lines) { if ($l) { [void]$sp.Children.Add((New-OzText -Text $l -Size 12 -Color '#8A9BBF' -Wrap -Margin '0,1,0,0')) } }
    if ($Score -ge 0) {
        $pb = New-Object System.Windows.Controls.ProgressBar
        $pb.Style = $Oz.Window.FindResource('Meter')
        $pb.Value = $Score
        $pb.Margin = New-OzThickness '0,10,0,0'
        [void]$sp.Children.Add($pb)
    }
    $card.Child = $sp
    $card
}

function Update-OzDashboard {
    $s = $Oz.Sys
    if (-not $s) { return }
    $sc = $s.Score
    $onOff = { param($v) if ($v) { T 'ON' } else { T 'OFF' } }
    Set-OzRing $sc.Overall
    $Oz.UI.ScoreText.Text = [string]$sc.Overall
    $Oz.UI.TierText.Text = T $sc.TierName
    $Oz.UI.TierText.Foreground = Get-OzBrush $sc.TierColor
    $Oz.UI.TierChipText.Text = '{0}  |  {1}  |  {2}' -f (T $sc.TierName), (T $s.Form).ToUpper(), $s.OS.Family.ToUpper()
    $Oz.UI.TierSub.Text = '{0}  /  {1} {2}  /  {3} {4}' -f (T $s.Form), $s.OS.Family, $s.OS.DisplayVersion, $s.Board.SystemManufacturer, $s.Board.SystemModel
    $summary = switch ($sc.TierKey) {
        'CHEAP'    { T 'Entry-level hardware. REVIVE mode strips Windows down so this PC feels fast again.' }
        'BUDGET'   { T 'Solid everyday machine with room to gain. Auto-Tune removes the overhead holding it back.' }
        'MIDRANGE' { T 'Strong hardware. Focus on latency, background noise and smart power for max FPS at sane temps.' }
        'FANCY'    { T 'Enthusiast-class rig. Unlock every frame: competitive latency tweaks and the Performance plan.' }
    }
    $Oz.UI.TierSummary.Text = '{0} {1}' -f $summary, (T 'Weakest part: {0}.' (T $sc.Bottleneck))
    $Oz.UI.BarCpu.Value = $sc.Cpu; $Oz.UI.BarGpu.Value = $sc.Gpu; $Oz.UI.BarRam.Value = $sc.Ram; $Oz.UI.BarSto.Value = $sc.Storage

    $g = $Oz.UI.SpecGrid
    $g.Children.Clear()
    $c = $s.CPU
    [void]$g.Children.Add((New-OzSpecCard -Title (T 'PROCESSOR') -Main $c.Name -Score $sc.Cpu -Lines @(
                (T '{0} cores / {1} threads  -  {2:N1} GHz base' $c.Cores $c.Threads ($c.MaxMHz / 1000)),
                ('L2 {0:N1} MB  -  L3 {1:N0} MB  -  {2}' -f ($c.L2KB / 1024), ($c.L3KB / 1024), $c.Arch),
                (T 'Socket {0}  -  Virtualization {1}' $c.Socket (& $onOff $c.Virt)))))
    $gp = $s.GPU.Primary
    $gpuLines = @()
    if ($gp) {
        $gpuLines += ('{0}  -  {1} GB VRAM  -  {2}' -f $gp.Vendor, $gp.VramGB, $(if ($gp.Dedicated) { T 'dedicated' } else { T 'integrated' }))
        $gpuLines += (T 'Driver {0}' $gp.DriverVersion)
        if ($gp.Resolution) { $gpuLines += $gp.Resolution }
        foreach ($o in @($s.GPU.List | Where-Object { $_.Name -ne $gp.Name -and -not $_.Virtual })) { $gpuLines += ('+ ' + $o.Name) }
    }
    [void]$g.Children.Add((New-OzSpecCard -Title (T 'GRAPHICS') -Main $(if ($gp) { $gp.Name } else { T 'Unknown' }) -Lines $gpuLines -Score $sc.Gpu -Accent '#FF2BD6'))
    $m = $s.Memory
    $chan = if ($m.Soldered) { T 'soldered' } elseif ($m.Modules -ge 2) { T 'dual / multi-channel' } elseif ($m.Modules -eq 1) { T 'SINGLE-channel' } else { '' }
    $memLines = @(T '{0} MT/s  -  {1} of {2} slots  -  {3}' $m.SpeedMTs $m.Modules $m.Slots $chan) + @($m.Details | Select-Object -First 4)
    [void]$g.Children.Add((New-OzSpecCard -Title (T 'MEMORY') -Main ('{0} GB {1}' -f $m.GB, $m.Type) -Score $sc.Ram -Accent '#8A5CFF' -Lines $memLines))
    $st = $s.Storage
    $stoLines = @(T '{0} GB free of {1} GB ({2}%)' $st.FreeGB $st.SizeGB $st.FreePct) + @($st.Disks | Select-Object -First 3)
    [void]$g.Children.Add((New-OzSpecCard -Title (T 'SYSTEM DRIVE') -Main ('{0}  -  {1}' -f (T $st.SystemKind), $st.SystemModel) -Score $sc.Storage -Accent '#2BFF9A' -Lines $stoLines))
    $b = $s.Board
    $biosDate = if ($b.BiosDate) { ([datetime]$b.BiosDate).ToString('yyyy-MM-dd') } else { '' }
    [void]$g.Children.Add((New-OzSpecCard -Title (T 'BOARD & SYSTEM') -Main ('{0} {1}' -f $b.Manufacturer, $b.Product) -Accent '#FFB020' -Lines @(
                ('{0} {1}' -f $b.SystemManufacturer, $b.SystemModel),
                ('BIOS {0}  {1}' -f $b.BiosVersion, $biosDate),
                $(if ($s.Battery.Present) { T 'Battery {0}%  -  wear {1}%' $s.Battery.Charge $(if ($null -ne $s.Battery.WearPct) { $s.Battery.WearPct } else { '?' }) }))))
    $o = $s.OS
    [void]$g.Children.Add((New-OzSpecCard -Title (T 'WINDOWS & SECURITY') -Main ('{0} {1}' -f $o.Family, $o.DisplayVersion) -Accent '#4FD8FF' -Lines @(
                ('{0}  -  build {1}.{2}' -f $o.Edition, $o.Build, $o.UBR),
                (T 'VBS {0}  -  Memory Integrity {1}' (& $onOff $s.Security.VBS) (& $onOff $s.Security.HVCI)),
                (T 'Secure Boot {0}  -  TPM {1}' $(if ($null -eq $s.Security.SecureBoot) { 'n/a' } else { & $onOff $s.Security.SecureBoot }) $(if ($s.Security.TPM) { $s.Security.TPM } else { T 'none' })),
                (T 'Power plan: {0}' $s.Power.Name))))

    # insights
    $panel = $Oz.UI.InsightsPanel
    $panel.Children.Clear()
    $colors = @{ crit = '#FF3B5C'; warn = '#FFB020'; info = '#00E5FF'; good = '#2BFF9A' }
    $order = @{ crit = 0; warn = 1; info = 2; good = 3 }
    $pages = @{ Profiles = 'PROFILES'; Tools = 'TOOLS'; Tweaks = 'TWEAKS'; Drivers = 'DRIVERS' }
    foreach ($i in @(Get-OzInsights $s | Sort-Object { $order[$_.Level] })) {
        $row = New-OzRowBorder
        $row.BorderBrush = Get-OzBrush ('#44' + $colors[$i.Level].TrimStart('#'))
        $grid = New-OzColumns @('Auto', '*', 'Auto')
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 9; $dot.Height = 9; $dot.Fill = Get-OzBrush $colors[$i.Level]
        $dot.VerticalAlignment = 'Top'; $dot.Margin = New-OzThickness '0,5,14,0'
        Add-OzGridChild $grid $dot 0
        $tx = New-Object System.Windows.Controls.StackPanel
        [void]$tx.Children.Add((New-OzText -Text $i.Title -Size 13.5 -Color '#E6F1FF' -Semi))
        [void]$tx.Children.Add((New-OzText -Text $i.Text -Size 12 -Wrap -Margin '0,3,0,0'))
        Add-OzGridChild $grid $tx 1
        if ($i.Go) {
            $btn = New-OzButton -Text (T 'GO TO {0}' (T $pages[$i.Go])) -Tag $i.Go -Margin '12,0,0,0'
            $btn.VerticalAlignment = 'Center'
            $btn.Add_Click({ $Oz.UI["Nav$($this.Tag)"].IsChecked = $true })
            Add-OzGridChild $grid $btn 2
        }
        $row.Child = $grid
        [void]$panel.Children.Add($row)
    }
}

function Update-OzLive {
    # Draws the latest numbers. They are measured on a background runspace, so the window never waits for WMI.
    param($l)
    if (-not $l) { return }
    try {
        $Oz.UI.LiveCpu.Text = '{0}%' -f $l.Cpu
        $Oz.UI.LiveCpuBar.Value = $l.Cpu
        if ($l.ClockMHz) {
            $Oz.UI.LiveClock.Text = '{0:N2} GHz' -f ($l.ClockMHz / 1000)
            $base = $Oz.Sys.CPU.MaxMHz
            if ($l.Cpu -ge 70 -and $base -and $l.ClockMHz -lt ($base * 0.6)) {
                $Oz.UI.LiveClockSub.Text = T 'Below base clock under load: throttling?'
                $Oz.UI.LiveClockSub.Foreground = Get-OzBrush '#FFB020'
            } else {
                $Oz.UI.LiveClockSub.Text = T 'base {0:N2} GHz' ($base / 1000)
                $Oz.UI.LiveClockSub.Foreground = Get-OzBrush '#8A9BBF'
            }
        }
        $Oz.UI.LiveRam.Text = '{0}%' -f $l.RamPct
        $Oz.UI.LiveRamBar.Value = $l.RamPct
        if ($null -ne $l.Temp) {
            $Oz.UI.LiveTemp.Text = '{0} {1}C' -f $l.Temp, [char]0x00B0
            $col = if ($l.Temp -lt 70) { '#2BFF9A' } elseif ($l.Temp -lt 85) { '#FFB020' } else { '#FF3B5C' }
            $Oz.UI.LiveTemp.Foreground = Get-OzBrush $col
            $Oz.UI.LiveTempSub.Text = T 'ACPI thermal zone'
        } else {
            $Oz.UI.LiveTemp.Text = 'N/A'
            $Oz.UI.LiveTempSub.Text = T 'Sensor hidden by firmware. HWiNFO shows exact temps.'
        }
        if ($l.Uptime) { $Oz.UI.LiveUp.Text = '{0}d {1}h {2}m' -f $l.Uptime.Days, $l.Uptime.Hours, $l.Uptime.Minutes }
        $Oz.UI.LiveProcs.Text = T '{0} processes running' $l.Procs
    } catch { }
}

function Start-OzLive {
    if ($Oz.LiveWorker) { return }
    $Oz.LiveWorker = Start-OzWorker -ScriptBlock {
        while (-not $Oz.Closing) {
            if ($Oz.LiveWanted -and $Oz.Sys) { try { $Oz.LiveData = Get-OzLiveStats } catch { } }
            Start-Sleep -Milliseconds 2000
        }
    }
}
#endregion

#region ============================ TWEAKS VIEW ============================
$Oz.RiskColors = @{ Safe = '#2BFF9A'; Moderate = '#FFB020'; Advanced = '#B79BFF'; Danger = '#FF3B5C' }

function New-OzTweakRow {
    # Builds the row only. Its real state is filled in by Set-OzRowFromState once the scan finishes.
    param($T)
    $border = New-OzRowBorder
    $grid = New-OzColumns @('Auto', '*', 'Auto')

    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Style = $Oz.Window.FindResource('Switch')
    $cb.Tag = $T.Id
    $cb.IsChecked = $false
    $cb.IsEnabled = $false
    $cb.VerticalAlignment = 'Center'
    $cb.Margin = New-OzThickness '0,0,16,0'
    $cb.Add_Click({ Update-OzRowState $this.Tag; Update-OzPendingBar })
    Add-OzGridChild $grid $cb 0

    $txt = New-Object System.Windows.Controls.StackPanel
    $nameColor = if ($T.Risk -eq 'Danger') { '#FF8FA3' } else { '#E6F1FF' }
    $nameT = New-OzText -Text '' -Size 13.5 -Color $nameColor -Semi
    $descT = New-OzText -Text '' -Size 12 -Wrap -Margin '0,2,0,0'
    $noteT = New-OzText -Text '' -Size 11.5 -Color '#FFB020' -Wrap -Margin '0,3,0,0'
    $infoT = New-OzText -Text '' -Size 11.5 -Color '#5D6E92' -Wrap -Margin '0,3,0,0'
    $infoT.Visibility = 'Collapsed'
    foreach ($x in $nameT, $descT, $noteT, $infoT) { [void]$txt.Children.Add($x) }
    Add-OzGridChild $grid $txt 1

    $side = New-Object System.Windows.Controls.StackPanel
    $side.HorizontalAlignment = 'Right'
    $side.VerticalAlignment = 'Center'
    $side.Margin = New-OzThickness '12,0,0,0'
    $badges = New-Object System.Windows.Controls.StackPanel
    $badges.Orientation = 'Horizontal'
    $badges.HorizontalAlignment = 'Right'
    [void]$side.Children.Add($badges)
    $status = New-OzText -Text '...' -Size 11 -Color '#5D6E92' -Display -Semi -Margin '0,6,0,0'
    $status.HorizontalAlignment = 'Right'
    [void]$side.Children.Add($status)
    Add-OzGridChild $grid $side 2

    $border.Child = $grid
    $row = @{
        Tweak = $T; Border = $border; Check = $cb; Status = $status; NameText = $nameT; DescText = $descT; NoteText = $noteT
        InfoText = $infoT; Badges = $badges; State = 'Scan'; Flag = ''; Legacy = $false; Applied = $false; Applicable = $false
        Rec = $false; Pending = $false; SearchText = ''
    }
    $Oz.Rows[$T.Id] = $row
    Set-OzRowText $row
    Set-OzRowBadges $row
    Set-OzRowVisual $row
    $row
}

function Set-OzRowText {
    param($Row)
    $t = $Row.Tweak
    $Row.NameText.Text = T $t.Name
    $Row.DescText.Text = T $t.Desc
    $Row.DescText.Visibility = $(if ($t.Desc) { 'Visible' } else { 'Collapsed' })
    if ($t.Note) { $Row.NoteText.Text = (T 'NOTE:') + ' ' + (T $t.Note); $Row.NoteText.Visibility = 'Visible' }
    else { $Row.NoteText.Visibility = 'Collapsed' }
    $Row.SearchText = Remove-OzAccents ('{0} {1} {2} {3} {4}' -f (Get-OzBothLang $t.Name), (Get-OzBothLang $t.Desc), (Get-OzBothLang $t.Note), $t.Id, $t.Cat)
}

function Set-OzRowBadges {
    param($Row)
    $t = $Row.Tweak
    $Row.Badges.Children.Clear()
    if ($Row.Rec) { [void]$Row.Badges.Children.Add((New-OzBadge (T 'RECOMMENDED') '#B79BFF')) }
    if ($t.Reboot) { [void]$Row.Badges.Children.Add((New-OzBadge (T 'REBOOT') '#4FD8FF')) }
    [void]$Row.Badges.Children.Add((New-OzBadge (T $t.Risk.ToUpper()) $Oz.RiskColors[$t.Risk]))
}

function Set-OzRowFromState {
    # Turns the detected state into what the row shows
    param($Row)
    $t = $Row.Tweak
    $st = $Oz.States[$t.Id]
    if (-not $st) { $st = 'Error' }
    $hwOk = Test-OzApplicable $t $Oz.Sys
    $e = Get-OzJournalEntry $t.Id
    $Row.State = $st
    $Row.Applicable = $hwOk -and ($st -ne 'NA')
    $Row.Applied = if ($st -eq 'Error') { [bool]$e } else { $st -eq 'On' }
    $Row.Flag = ''
    $Row.Legacy = $false
    if ($Row.Applicable -and $e -and $st -eq 'Off') {
        $Row.Flag = $(if ($e.Data.ContainsKey('Blocked')) { 'Blocked' } else { 'Undone' })
        # Applied by v1.0, which deleted registry values instead of writing them
        $Row.Legacy = -not $e.ContainsKey('Ver')
    }
    $wasRec = $Row.Rec
    $Row.Rec = $Row.Applicable -and (Test-OzRecommended $t $Oz.Sys)
    if ($wasRec -ne $Row.Rec) { Set-OzRowBadges $Row }
    $Row.Check.IsChecked = $Row.Applied
    $Row.Check.IsEnabled = $Row.Applicable
    Set-OzRowVisual $Row
}

function Set-OzRowVisual {
    param($Row)
    $t = $Row.Tweak
    $want = [bool]$Row.Check.IsChecked
    $Row.Pending = $Row.Applicable -and ($want -ne $Row.Applied)
    $info = ''; $infoColor = '#5D6E92'
    if ($Row.State -eq 'Scan') {
        $Row.Status.Text = '...'
        $Row.Status.Foreground = Get-OzBrush '#5D6E92'
        $Row.Border.BorderBrush = Get-OzBrush '#16233D'
        $Row.Border.Background = Get-OzBrush '#990B1324'
    } elseif ($Row.Pending) {
        $Row.Border.BorderBrush = Get-OzBrush '#FF2BD6'
        $Row.Border.Background = Get-OzBrush '#1AFF2BD6'
        $Row.Status.Text = if ($want) { T 'WILL APPLY' } else { T 'WILL REVERT' }
        $Row.Status.Foreground = Get-OzBrush '#FF2BD6'
    } else {
        $Row.Border.Background = Get-OzBrush '#990B1324'
        $Row.Border.BorderBrush = Get-OzBrush $(if ($Row.Flag -and $Row.Applicable) { '#55FFB020' } elseif ($Row.Applied) { '#2600E5FF' } else { '#16233D' })
        if (-not $Row.Applicable) { $Row.Status.Text = 'N/A'; $Row.Status.Foreground = Get-OzBrush '#5D6E92' }
        elseif ($Row.Applied) { $Row.Status.Text = T 'ACTIVE'; $Row.Status.Foreground = Get-OzBrush '#2BFF9A' }
        elseif ($Row.Flag -eq 'Undone') { $Row.Status.Text = T 'CHANGED BACK'; $Row.Status.Foreground = Get-OzBrush '#FFB020' }
        elseif ($Row.Flag -eq 'Blocked') { $Row.Status.Text = T 'BLOCKED'; $Row.Status.Foreground = Get-OzBrush '#FFB020' }
        else { $Row.Status.Text = T 'OFF'; $Row.Status.Foreground = Get-OzBrush '#5D6E92' }
    }
    if ($Row.State -ne 'Scan') {
        if ($Row.State -eq 'NA') { $info = T 'Not present on this PC - nothing to change here.' }
        elseif (-not $Row.Applicable) {
            $info = if ($t.MinBuild -and $Oz.Sys -and $Oz.Sys.OS.Build -lt $t.MinBuild) { T 'Needs a newer Windows build.' } else { T 'Not applicable to this hardware.' }
        } elseif (-not $Row.Pending -and -not $Row.Applied -and $Row.Flag -eq 'Undone' -and $Row.Legacy) {
            $info = T 'Version 1.0 did not write this setting correctly. Use RE-APPLY below to apply it for real.'
            $infoColor = '#FFB020'
        } elseif (-not $Row.Pending -and -not $Row.Applied -and $Row.Flag -eq 'Undone') {
            $info = T 'Something outside the app (Windows, an update or another program) changed this back. Turn it on and apply, or use RE-APPLY below.'
            $infoColor = '#FFB020'
        } elseif (-not $Row.Pending -and -not $Row.Applied -and $Row.Flag -eq 'Blocked') {
            $info = T 'Windows did not accept this change on this PC (edition, policy or a protected setting). It is not counted as active.'
            $infoColor = '#FFB020'
        } elseif ($Row.State -eq 'Error') {
            $info = T 'Could not read the current state this time.'
        }
    }
    $Row.InfoText.Text = $info
    $Row.InfoText.Foreground = Get-OzBrush $infoColor
    $Row.InfoText.Visibility = $(if ($info) { 'Visible' } else { 'Collapsed' })
    $Row.Border.Opacity = if ($Row.Applicable -or $Row.State -eq 'Scan') { 1.0 } else { 0.5 }
}

function Update-OzRowState {
    param([string]$Id)
    $row = $Oz.Rows[$Id]
    if (-not $row) { return }
    if ($row.Check.IsChecked -and $row.Tweak.Group) {
        foreach ($o in @($Oz.Rows.Values)) {
            if ($o.Tweak.Id -ne $Id -and $o.Tweak.Group -eq $row.Tweak.Group -and $o.Check.IsChecked) {
                $o.Check.IsChecked = $false
                Set-OzRowVisual $o
            }
        }
    }
    Set-OzRowVisual $row
}

function Update-OzPendingBar {
    $p = @($Oz.Rows.Values | Where-Object { $_.Pending })
    $on = @($p | Where-Object { $_.Check.IsChecked }).Count
    $off = $p.Count - $on
    $Oz.UI.PendingText.Text = if ($p.Count) { T '{0} change(s) pending   +{1} apply   -{2} revert' $p.Count $on $off } else { T 'No pending changes' }
    $Oz.UI.PendingText.Foreground = Get-OzBrush $(if ($p.Count) { '#FF2BD6' } else { '#E6F1FF' })
    $Oz.UI.BtnApply.IsEnabled = ($p.Count -gt 0)
    $Oz.UI.BtnClearPending.IsEnabled = ($p.Count -gt 0)
    $undone = @(Get-OzUndoneRows).Count
    $Oz.UI.BtnReapply.Visibility = $(if ($undone -and -not $p.Count) { 'Visible' } else { 'Collapsed' })
    $Oz.UI.BtnReapply.Content = T 'RE-APPLY {0} CHANGED BACK' $undone
    Update-OzChipLabels
}

function Get-OzUndoneRows {
    @($Oz.Rows.Values | Where-Object { $_.Applicable -and -not $_.Applied -and $_.Flag -eq 'Undone' })
}

function Update-OzActiveCount {
    $rows = @($Oz.Rows.Values | Where-Object { $_.Applicable })
    $act = @($rows | Where-Object { $_.Applied }).Count
    $Oz.UI.NavActiveCount.Text = [string]$act
    $Oz.UI.NavActiveTotal.Text = ' / {0}' -f $rows.Count
    $Oz.UI.NavActiveBar.Value = if ($rows.Count) { 100 * $act / $rows.Count } else { 0 }
    Update-OzChipLabels
}

function Update-OzChipLabels {
    if (-not $Oz.ChipLabels) { return }
    $vals = @($Oz.Rows.Values)
    $count = @{
        PENDING   = @($vals | Where-Object { $_.Pending }).Count
        ACTIVE    = @($vals | Where-Object { $_.Applicable -and $_.Applied }).Count
        ATTENTION = @($vals | Where-Object { $_.Applicable -and -not $_.Applied -and $_.Flag }).Count
    }
    foreach ($k in @($Oz.Chips.Keys)) {
        $label = T $Oz.ChipLabels[$k]
        if ($count.ContainsKey($k)) { $label = '{0} ({1})' -f $label, $count[$k] }
        $Oz.Chips[$k].Content = $label
    }
    if ($Oz.Chips.ContainsKey('ATTENTION')) {
        $Oz.Chips['ATTENTION'].Visibility = $(if ($count.ATTENTION -or $Oz.Chip -eq 'ATTENTION') { 'Visible' } else { 'Collapsed' })
    }
}

function Select-OzChip {
    param([string]$Key)
    if ($Oz.Chips.ContainsKey($Key)) { $Oz.Chips[$Key].IsChecked = $true }
    $Oz.Chip = $Key
    Update-OzFilter
}

function Update-OzFilter {
    $q = Remove-OzAccents (([string]$Oz.UI.TweakSearch.Text).Trim())
    $chip = $Oz.Chip
    $visibleCats = @{}
    foreach ($row in $Oz.Rows.Values) {
        $show = $true
        if ($q -and -not $row.SearchText.Contains($q)) { $show = $false }
        switch ($chip) {
            'ALL' { }
            'RECOMMENDED' { if (-not $row.Rec) { $show = $false } }
            'PENDING' { if (-not $row.Pending) { $show = $false } }
            'ACTIVE' { if (-not ($row.Applied -and $row.Applicable)) { $show = $false } }
            'ATTENTION' { if (-not ($row.Flag -and $row.Applicable -and -not $row.Applied)) { $show = $false } }
            default { if ($row.Tweak.Cat -ne $chip) { $show = $false } }
        }
        $row.Border.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
        if ($show) { $visibleCats[$row.Tweak.Cat] = $true }
    }
    foreach ($k in @($Oz.CatHeaders.Keys)) {
        $Oz.CatHeaders[$k].Panel.Visibility = if ($visibleCats.ContainsKey($k)) { 'Visible' } else { 'Collapsed' }
    }
}

function Set-OzCatHeaderText {
    param([string]$Key)
    $h = $Oz.CatHeaders[$Key]
    $c = $Oz.Categories | Where-Object Key -EQ $Key | Select-Object -First 1
    $h.Title.Text = T $c.Name
    if ($h.Info) { $h.Info.Text = T 'These trade security for speed or convenience. They are never part of a profile and always ask for confirmation. Only use them if you understand the risk.' }
}

function Initialize-OzTweakList {
    $Oz.UI.TweakList.Items.Clear()
    $Oz.Rows = @{}
    $Oz.CatHeaders = @{}
    $Oz.UI.ChipPanel.Children.Clear()
    $Oz.Chips = @{}
    $Oz.ChipLabels = @{}
    $Oz.Chip = 'ALL'
    $chipDefs = @(@('ALL', 'ALL'), @('RECOMMENDED', 'RECOMMENDED'), @('PENDING', 'PENDING'), @('ACTIVE', 'ACTIVE'), @('ATTENTION', 'NEEDS ATTENTION')) +
    @($Oz.Categories | ForEach-Object { , @($_.Key, $_.Name) })
    foreach ($c in $chipDefs) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $Oz.Window.FindResource('Chip')
        $rb.GroupName = 'chips'
        $rb.Content = T $c[1]
        $rb.Tag = $c[0]
        if ($c[0] -eq 'ALL') { $rb.IsChecked = $true }
        if ($c[0] -eq 'ATTENTION') { $rb.Foreground = Get-OzBrush '#FFB020'; $rb.Visibility = 'Collapsed' }
        $rb.Add_Checked({ $Oz.Chip = $this.Tag; Update-OzFilter })
        $Oz.Chips[$c[0]] = $rb
        $Oz.ChipLabels[$c[0]] = $c[1]
        [void]$Oz.UI.ChipPanel.Children.Add($rb)
    }

    $n = 0
    foreach ($c in $Oz.Categories) {
        $tw = @($Oz.Tweaks | Where-Object { $_.Cat -eq $c.Key })
        if (-not $tw) { continue }
        $hdr = New-Object System.Windows.Controls.StackPanel
        $hdr.Margin = New-OzThickness '0,14,0,8'
        $line = New-Object System.Windows.Controls.StackPanel
        $line.Orientation = 'Horizontal'
        $col = if ($c.Key -eq 'Danger') { '#FF3B5C' } else { '#00E5FF' }
        $title = New-OzText -Text '' -Size 13 -Color $col -Display -Bold
        [void]$line.Children.Add($title)
        [void]$line.Children.Add((New-OzText -Text ('  {0}' -f $tw.Count) -Size 12 -Color '#5D6E92' -Display))
        [void]$hdr.Children.Add($line)
        $info = $null
        if ($c.Key -eq 'Danger') {
            $info = New-OzText -Text '' -Size 12 -Color '#FF8FA3' -Wrap -Margin '0,4,0,0'
            [void]$hdr.Children.Add($info)
        }
        [void]$Oz.UI.TweakList.Items.Add($hdr)
        $Oz.CatHeaders[$c.Key] = @{ Panel = $hdr; Title = $title; Info = $info }
        Set-OzCatHeaderText $c.Key
        foreach ($t in $tw) {
            $n++
            $row = New-OzTweakRow $t
            [void]$Oz.UI.TweakList.Items.Add($row.Border)
            if ($n % 16 -eq 0) { Update-OzUI }
        }
    }
    Update-OzPendingBar
}

function Update-OzAllRowStates {
    # Re-reads every tweak on a background runspace, then refreshes the rows
    $w = Start-OzWorker -ArgumentList @(, @($Oz.Tweaks)) -ScriptBlock { param($list) Get-OzAllStates $list }
    foreach ($h in (Wait-OzWorker $w (T 'Reading the real state of every tweak...'))) {
        if ($h -is [hashtable]) { foreach ($k in @($h.Keys)) { $Oz.States[$k] = $h[$k] } }
    }
    foreach ($row in @($Oz.Rows.Values)) { Set-OzRowFromState $row }
    Update-OzPendingBar
    Update-OzActiveCount
    Update-OzFilter
}

function Invoke-OzApplyPending {
    $pending = @($Oz.Rows.Values | Where-Object { $_.Pending })
    if (-not $pending) { Write-OzLog (T 'No pending changes.'); return }
    $toApply = @($pending | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.Tweak })
    $toRevert = @($pending | Where-Object { -not $_.Check.IsChecked } | ForEach-Object { $_.Tweak })
    Invoke-OzChangeSet -ToApply $toApply -ToRevert $toRevert
}

function Restart-OzExplorer {
    Write-OzLog (T 'Restarting Explorer to show UI changes...') 'STEP'
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 1500
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process "$env:SystemRoot\explorer.exe" }
}

function Invoke-OzChangeSet {
    param([object[]]$ToApply = @(), [object[]]$ToRevert = @())
    $ToApply = @($ToApply | Where-Object { $_ })
    $ToRevert = @($ToRevert | Where-Object { $_ })
    $total = $ToApply.Count + $ToRevert.Count
    if (-not $total) { return }

    $danger = @($ToApply | Where-Object { $_.Risk -eq 'Danger' })
    if ($danger.Count) {
        $msg = (T "You are about to change DANGER ZONE settings:`n`n{0}`n`nThese lower the security of this PC. Continue?" (($danger | ForEach-Object { '  - ' + (T $_.Name) }) -join "`n"))
        if ((Show-OzDialog -Text $msg -Buttons YesNo -Kind Warning) -ne 'Yes') { Write-OzLog (T 'Cancelled.') 'WARN'; return }
    }
    if ($ToApply.Count -and $Oz.UI.ChkRestorePoint.IsChecked) { [void](New-OzRestorePoint) }
    $activeBefore = @($Oz.Rows.Values | Where-Object { $_.Applicable -and $_.Applied }).Count

    Set-OzBusy $true (T 'Applying {0} change(s)...' $total)
    $Oz.UI.ApplyProgress.Visibility = 'Visible'
    $Oz.UI.ApplyProgress.Maximum = $total
    $Oz.UI.ApplyProgress.Value = 0
    $ok = 0; $fail = 0; $reboot = $false; $explorer = $false; $i = 0
    $jobs = @($ToRevert | ForEach-Object { @{ T = $_; Mode = 'Revert' } }) + @($ToApply | ForEach-Object { @{ T = $_; Mode = 'Apply' } })
    foreach ($j in $jobs) {
        $i++
        $t = $j.T
        $mode = if ($j.Mode -eq 'Apply') { T 'Apply' } else { T 'Revert' }
        Write-OzLog ('[{0}/{1}] {2}: {3}' -f $i, $total, $mode, (T $t.Name)) 'STEP'
        try {
            if ($j.Mode -eq 'Apply') { Invoke-OzTweakApply $t } else { Invoke-OzTweakRevert $t }
            $ok++
            if ($t.Reboot) { $reboot = $true }
            if ($t.Explorer) { $explorer = $true }
        } catch {
            $fail++
            Write-OzLog ((T '  failed: {0}') -f $_.Exception.Message) 'ERR'
        }
        $Oz.UI.ApplyProgress.Value = $i
        Update-OzUI
    }
    if ($explorer) { Restart-OzExplorer }

    # Check what really changed, so the switches and the count never claim more than Windows accepted
    $blocked = @()
    foreach ($j in $jobs) {
        $row = $Oz.Rows[$j.T.Id]
        $st = Get-OzTweakState $j.T
        $Oz.States[$j.T.Id] = $st
        $e = Get-OzJournalEntry $j.T.Id
        if ($j.Mode -eq 'Apply' -and $e) {
            if ($st -eq 'Off') { $e.Data['Blocked'] = $true; $blocked += (T $j.T.Name) }
            elseif ($e.Data.ContainsKey('Blocked')) { $e.Data.Remove('Blocked') }
        }
        if ($row) { Set-OzRowFromState $row; Update-OzUI }
    }
    Save-OzJournal
    $Oz.UI.ApplyProgress.Visibility = 'Collapsed'
    Update-OzPendingBar
    Update-OzActiveCount
    Update-OzFilter
    Update-OzProfileStats
    Update-OzJournalView
    if ($Oz.Sys) { $Oz.Sys.Power = Get-OzActivePlan; Update-OzPowerText }
    Set-OzBusy $false
    $lvl = if ($fail -or $blocked.Count) { 'WARN' } else { 'OK' }
    Write-OzLog (T 'Done: {0} succeeded, {1} failed.' $ok $fail) $lvl
    if ($blocked.Count) { Write-OzLog (T 'Windows did not accept these on this PC, so they stay OFF: {0}' ($blocked -join ', ')) 'WARN' }
    Show-OzResults -Total $total -Ok $ok -Fail $fail -Blocked $blocked -Reboot $reboot -ActiveBefore $activeBefore
}

function Show-OzResults {
    # The card shown after a batch of changes: what happened, what is active now, restart or not
    param([int]$Total, [int]$Ok, [int]$Fail, [string[]]$Blocked = @(), [bool]$Reboot, [int]$ActiveBefore)
    $Blocked = @($Blocked | Where-Object { $_ })
    if ($Total -lt 3 -and -not $Fail -and -not $Blocked.Count -and -not $Reboot) { return }
    $activeAfter = @($Oz.Rows.Values | Where-Object { $_.Applicable -and $_.Applied }).Count
    $rows = @(@{ Text = (T '{0} change(s) done' $Ok); Color = '#2BFF9A'; Glyph = [char]0xE73E })
    if ($Fail) { $rows += @{ Text = (T '{0} failed - see the Log tab' $Fail); Color = '#FF3B5C'; Glyph = [char]0xEA39 } }
    if ($Blocked.Count) { $rows += @{ Text = (T 'Windows kept these OFF: {0}' ($Blocked -join ', ')); Color = '#FFB020'; Glyph = [char]0xE7BA } }
    $rows += @{ Text = (T 'Tweaks active: {0} -> {1}' $ActiveBefore $activeAfter); Color = '#00E5FF'; Glyph = [char]0xE945 }
    $rows += @{ Text = (T 'Undo any of it in BACKUP & UNDO.'); Color = '#8A9BBF'; Glyph = [char]0xE777 }
    $kind = if ($Fail -or $Blocked.Count) { 'Warning' } else { 'Success' }
    if ($Reboot) {
        $rows += @{ Text = (T 'Some changes take effect after a restart.'); Color = '#FFB020'; Glyph = [char]0xE7E8 }
        $r = Show-OzDialog -Title (T 'DONE') -Text (T 'Changes finished.') -Kind $kind -Rows $rows -Buttons YesNo -Labels @((T 'RESTART NOW'), (T 'LATER'))
        if ($r -eq 'Yes') { Restart-Computer -Force }
    } else {
        [void](Show-OzDialog -Title (T 'DONE') -Text (T 'Changes finished.') -Kind $kind -Rows $rows)
    }
}
#endregion

#region ============================ PROFILES VIEW ============================
function Initialize-OzProfileCards {
    $panel = $Oz.UI.ProfilePanel
    $panel.Children.Clear()
    $Oz.ProfileStats = @{}
    foreach ($p in $Oz.Profiles) {
        $card = New-OzCard
        if ($p.Featured) {
            $card.BorderBrush = Get-OzBrush '#00E5FF'
            $card.BorderThickness = New-OzThickness '2'
            $card.Background = Get-OzBrush '#E60A1428'
        }
        $sp = New-Object System.Windows.Controls.StackPanel
        $head = New-OzColumns @('Auto', '*')
        $ic = New-OzText -Text ([string]$p.Icon) -Size 26 -Color $p.Color -Icon -Margin '0,2,14,0'
        Add-OzGridChild $head $ic 0
        $ttl = New-Object System.Windows.Controls.StackPanel
        [void]$ttl.Children.Add((New-OzText -Text (T $p.Name) -Size 17 -Color '#E6F1FF' -Display -Bold))
        $subText = if ($p.Featured) { (T 'RECOMMENDED FOR YOUR PC') + '  /  ' + (T $p.Sub).ToUpper() } else { (T $p.Sub).ToUpper() }
        [void]$ttl.Children.Add((New-OzText -Text $subText -Size 10.5 -Color $p.Color -Display -Semi -Margin '0,2,0,0'))
        Add-OzGridChild $head $ttl 1
        [void]$sp.Children.Add($head)
        [void]$sp.Children.Add((New-OzText -Text (T $p.Desc) -Size 12.5 -Wrap -Margin '0,10,0,10'))
        $stats = New-OzText -Text '' -Size 11.5 -Color '#5D6E92' -Mono -Margin '0,0,0,12'
        [void]$sp.Children.Add($stats)
        $Oz.ProfileStats[$p.Key] = $stats
        $btns = New-Object System.Windows.Controls.WrapPanel
        $pv = New-OzButton -Text (T 'PREVIEW') -Style 'Neon' -Tag $p.Key -Margin '0,0,8,6'
        $pv.Add_Click({ $k = $this.Tag; Invoke-OzSafe 'Profile preview' { Invoke-OzProfile $k } })
        [void]$btns.Children.Add($pv)
        $ap = New-OzButton -Text (T 'APPLY {0}' (T $p.Name)) -Style 'Primary' -Tag $p.Key -Margin '0,0,8,6'
        $ap.Add_Click({ $k = $this.Tag; Invoke-OzSafe 'Profile apply' { Invoke-OzProfile $k -Apply } })
        [void]$btns.Children.Add($ap)
        [void]$sp.Children.Add($btns)
        $card.Child = $sp
        [void]$panel.Children.Add($card)
    }
    Update-OzProfileStats
}

function Update-OzProfileStats {
    if (-not $Oz.ProfileStats) { return }
    foreach ($p in $Oz.Profiles) {
        $ids = @(Resolve-OzProfile $p | Where-Object { $Oz.Rows[$_] -and $Oz.Rows[$_].Applicable })
        $new = @($ids | Where-Object { -not $Oz.Rows[$_].Applied }).Count
        $plan = @($ids | Where-Object { $_ -like 'plan-*' }) | Select-Object -First 1
        $planTxt = if ($plan) { '  |  ' + (T 'plan: {0}' $plan.Substring(5).ToUpper()) } else { '' }
        $Oz.ProfileStats[$p.Key].Text = (T '{0} tweaks  |  {1} not active yet' $ids.Count $new) + $planTxt
    }
}

function Invoke-OzProfile {
    param([string]$Key, [switch]$Apply)
    $p = $Oz.Profiles | Where-Object Key -EQ $Key | Select-Object -First 1
    if (-not $p) { return }
    $ids = Resolve-OzProfile $p
    $n = 0
    foreach ($id in $ids) {
        $row = $Oz.Rows[$id]
        if ($row -and $row.Applicable -and -not $row.Check.IsChecked) {
            $row.Check.IsChecked = $true
            Update-OzRowState $id
            $n++
        }
    }
    Update-OzPendingBar
    if (-not $Apply) {
        Write-OzLog (T '{0}: {1} switch(es) staged. Review them, then press APPLY CHANGES.' (T $p.Name) $n) 'OK'
        $Oz.UI.NavTweaks.IsChecked = $true
        Select-OzChip 'PENDING'
        return
    }
    $pending = @($Oz.Rows.Values | Where-Object { $_.Pending }).Count
    if (-not $pending) { Write-OzLog (T '{0}: everything in this profile is already active.' (T $p.Name)) 'OK'; return }
    $extra = ''
    if ($Key -in 'maxperf', 'competitive' -and $Oz.Sys.IsLaptop) { $extra = "`n`n" + (T 'Laptop detected: the Performance plan runs hotter. Use it while plugged in, or switch to COOL & QUIET later.') }
    $rp = if ($Oz.UI.ChkRestorePoint.IsChecked) { "`n" + (T 'A System Restore point is created first.') } else { '' }
    $msg = (T "Apply {0}?`n`n{1} change(s) will be made on this PC." (T $p.Name) $pending) + $rp + $extra
    if ((Show-OzDialog -Text $msg -Buttons YesNo -Kind Question) -eq 'Yes') { Invoke-OzApplyPending }
}
#endregion

#region ============================ GAMES ============================
# Competitive settings for popular shooters, matched to this PC. The app only READS each game's
# own settings file and compares it with the recommended values. It never writes to game files:
# games rewrite them on exit and anti-cheat systems watch them. Setting, menu and launcher names
# stay in English so they match the English game menus exactly.

function Read-OzTextShared {
    # Reads a text file even while a game or launcher has it open. Nothing is returned if it is missing.
    param([string]$Path, [switch]$Lines)
    if (-not $Path -or -not [IO.File]::Exists($Path)) { return }
    $t = $null
    try {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $t = (New-Object IO.StreamReader($fs, $true)).ReadToEnd() } finally { $fs.Dispose() }
    } catch { return }
    if ($Lines) { $t -split "`r?`n" } else { $t }
}

function ConvertTo-OzNumber {
    # "0.000000" -> 0, "144" -> 144, "False" -> nothing
    param([string]$Text)
    $n = 0.0
    if ([double]::TryParse(([string]$Text).Trim(), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
}

function Get-OzSavedGamesDir {
    try {
        $v = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{4C5C32FF-BB9D-43b0-B5B4-2D72E54EAAA4}'
        if ($v) { return [Environment]::ExpandEnvironmentVariables([string]$v) }
    } catch { }
    Join-Path $env:USERPROFILE 'Saved Games'
}

function Get-OzRefreshRate {
    # Refresh rate of the main screen, from the hardware scan ("1920x1080 @ 144 Hz")
    if ($Oz.Sys -and $Oz.Sys.GPU -and $Oz.Sys.GPU.Primary -and ([string]$Oz.Sys.GPU.Primary.Resolution -match '@\s*(\d+)\s*Hz')) {
        $hz = [int]$Matches[1]
        if ($hz -ge 30 -and $hz -le 1000) { return $hz }
    }
    0
}

function Get-OzSteamInfo {
    # Steam's own folder and every Steam library folder on this PC
    $root = $null
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = Get-ItemProperty -LiteralPath $k -ErrorAction Stop
            $v = if ($p.SteamPath) { [string]$p.SteamPath } elseif ($p.InstallPath) { [string]$p.InstallPath } else { '' }
            $v = $v.Replace('/', '\')
            if ($v -and (Test-Path -LiteralPath $v)) { $root = $v; break }
        } catch { }
    }
    $libs = New-Object System.Collections.Generic.List[string]
    if ($root) {
        $libs.Add($root)
        foreach ($line in (Read-OzTextShared (Join-Path $root 'steamapps\libraryfolders.vdf') -Lines)) {
            if ($line -match '^\s*"path"\s+"(.+)"\s*$') {
                $lp = $Matches[1].Replace('\\', '\')
                if (-not ($libs | Where-Object { $_.TrimEnd('\') -eq $lp.TrimEnd('\') }) -and (Test-Path -LiteralPath $lp)) { $libs.Add($lp) }
            }
        }
    }
    [pscustomobject]@{ Root = $root; Libraries = @($libs) }
}

function Find-OzSteamGame {
    # Install folder of a Steam game, from its appmanifest in any library
    param($Steam, [int]$AppId)
    foreach ($lib in @($Steam.Libraries)) {
        foreach ($line in (Read-OzTextShared (Join-Path $lib "steamapps\appmanifest_$AppId.acf") -Lines)) {
            if ($line -match '^\s*"installdir"\s+"(.+)"\s*$') {
                $dir = Join-Path $lib ('steamapps\common\' + $Matches[1].Replace('\\', '\'))
                if (Test-Path -LiteralPath $dir) { return $dir }
            }
        }
    }
}

function Get-OzEpicGames {
    # Games installed with the Epic Games Launcher, from its install manifests
    $dir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.item' -File -ErrorAction SilentlyContinue)) {
        try {
            $raw = Read-OzTextShared $f.FullName
            if (-not $raw) { continue }
            $j = $raw | ConvertFrom-Json
            if ($j.InstallLocation) {
                [pscustomobject]@{ AppName = [string]$j.AppName; Name = [string]$j.DisplayName; Location = [string]$j.InstallLocation; Exe = [string]$j.LaunchExecutable }
            }
        } catch { }
    }
}

function Get-OzUninstallEntries {
    # Installed programs as Windows lists them (both registry views, machine and user)
    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($hive in [Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryHive]::CurrentUser) {
        foreach ($view in [Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32) {
            $base = $null; $root = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $root = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
                if ($root) {
                    foreach ($name in $root.GetSubKeyNames()) {
                        $k = $null
                        try {
                            $k = $root.OpenSubKey($name)
                            $dn = if ($k) { [string]$k.GetValue('DisplayName') } else { '' }
                            if ($dn -and -not $seen.ContainsKey("$name|$dn")) {
                                $seen["$name|$dn"] = $true
                                $list.Add([pscustomobject]@{ Key = $name; Name = $dn; Location = [string]$k.GetValue('InstallLocation'); Icon = [string]$k.GetValue('DisplayIcon') })
                            }
                        } catch { } finally { if ($k) { $k.Close() } }
                    }
                }
            } catch { } finally {
                if ($root) { $root.Close() }
                if ($base) { $base.Close() }
            }
        }
    }
    $list
}

function Get-OzIconFile {
    # First existing .exe / .ico among: the DisplayIcon from Windows, then known files in the install folder
    param([string]$DisplayIcon, [string]$Location, [string[]]$Exes)
    $cands = @()
    if ($DisplayIcon) { $cands += (($DisplayIcon -replace ',\s*-?\d+\s*$', '').Trim().Trim('"')) }
    if ($Location) { foreach ($e in @($Exes)) { if ($e) { $cands += (Join-Path $Location $e.Replace('/', '\')) } } }
    foreach ($c in $cands) {
        try { if ($c -match '\.(exe|ico)$' -and [IO.File]::Exists($c)) { return $c } } catch { }
    }
}

function Get-OzFileIcon {
    # The icon Windows shows for a file, as an image WPF can draw. Nothing if it cannot be read.
    param([string]$Path)
    if (-not $Path -or -not [IO.File]::Exists($Path)) { return }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($Path)
        if (-not $ico) { return }
        try {
            $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($ico.Handle, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
            $src.Freeze()
            $src
        } finally { $ico.Dispose() }
    } catch { }
}

function Read-OzGameConfig {
    # Flat view of a game's settings file. INI keys become "Section|Key"; KeyValues (VDF) keys stay as they are.
    param([string]$Path, [ValidateSet('Vdf', 'Ini')][string]$Format)
    $map = @{}
    $section = ''
    foreach ($line in (Read-OzTextShared $Path -Lines)) {
        if ($Format -eq 'Vdf') {
            if ($line -match '^\s*"([^"]+)"\s+"([^"]*)"') { $map[$Matches[1]] = $Matches[2] }
        } else {
            if ($line -match '^\s*\[(.+)\]\s*$') { $section = $Matches[1]; continue }
            if ($line -match '^\s*([^=;#\[]+?)\s*=\s*(.*?)\s*$') { $map["$section|$($Matches[1])"] = $Matches[2] }
        }
    }
    $map
}

function Format-OzGameValue {
    param($Check, [string]$Raw)
    $n = ConvertTo-OzNumber $Raw
    $norm = if ($null -ne $n) { $n.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture) } else { $Raw.Trim() }
    if ($Check.Labels) {
        foreach ($k in @($Check.Labels.Keys)) { if ([string]$k -ieq $norm) { return [string]$Check.Labels[$k] } }
    }
    if ($Check.Suffix -and $null -ne $n) { return $norm + $Check.Suffix }
    $norm
}

function Test-OzGameCheck {
    # Compares one value in the game's file with the recommended one. Ok is $null when the
    # value is not in this version of the file (games rename settings between updates).
    param($Check, $Map)
    $key = $null
    foreach ($k in @($Check.Entries)) { if ($Map.ContainsKey($k)) { $key = $k; break } }
    $raw = if ($key) { [string]$Map[$key] } elseif ($null -ne $Check.Default) { [string]$Check.Default } else { $null }
    if ($null -eq $raw) { return [pscustomobject]@{ Name = $Check.Name; Current = ''; Want = $Check.WantText; Ok = $null } }
    $a = ConvertTo-OzNumber $raw
    $b = ConvertTo-OzNumber ([string]$Check.Want)
    $ok = switch ([string]$Check.Op) {
        'ge' { ($null -ne $a) -and ($null -ne $b) -and ($a -ge $b) }
        default {
            if ($null -ne $a -and $null -ne $b) { $a -eq $b } else { $raw.Trim() -ieq ([string]$Check.Want).Trim() }
        }
    }
    [pscustomobject]@{ Name = $Check.Name; Current = (Format-OzGameValue $Check $raw); Want = $Check.WantText; Ok = [bool]$ok }
}

function Get-OzGameCatalog {
    # Every supported game. Recommendations follow this PC: GPU maker, video memory, laptop or not.
    $sys = $Oz.Sys
    $gpu = if ($sys -and $sys.GPU) { $sys.GPU.Primary } else { $null }
    $nvidia = [bool]($gpu -and $gpu.Vendor -eq 'NVIDIA')
    $vram = if ($gpu) { [double]$gpu.VramGB } else { 0 }
    $laptop = [bool]($sys -and $sys.IsLaptop)
    $hz = Get-OzRefreshRate
    $tex = if ($vram -ge 6) { 'Medium' } else { 'Low' }
    $reflex = 'On + Boost'

    $where = @{
        'Steam'  = 'Steam > Library > right-click {0} > Properties > General > Launch Options'
        'EA app' = 'EA app > Library > three dots on {0} > View properties > Advanced launch options'
        'Epic'   = 'Epic Games Launcher > Library > three dots on {0} > Manage > Launch Options'
    }

    # ---------------- Apex Legends ----------------
    $apexBudget = if ($vram -ge 10) { 'Very High (6GB VRAM)' } elseif ($vram -ge 7) { 'High (4GB VRAM)' } elseif ($vram -ge 5) { 'Medium (3GB VRAM)' } elseif ($vram -ge 3.5) { 'Low (2-3GB VRAM)' } else { 'Very Low (2GB VRAM)' }
    $apexMenu = @(
        @('Display Mode', 'Full Screen'),
        @('V-Sync', 'Disabled')
    )
    if ($nvidia) { $apexMenu += , @('NVIDIA Reflex', 'Enabled + Boost') }
    $apexMenu += @(
        @('Adaptive Resolution FPS Target', '0'),
        @('Texture Streaming Budget', $apexBudget),
        @('Ambient Occlusion Quality', 'Disabled'),
        @('Sun Shadow Coverage', 'Low'),
        @('Sun Shadow Detail', 'Low'),
        @('Spot Shadow Detail', 'Disabled'),
        @('Volumetric Lighting', 'Disabled'),
        @('Model Detail', 'Low'),
        @('Effects Detail', 'Low'),
        @('Impact Marks', 'Disabled'),
        @('Ragdolls', 'Low')
    )
    $apexArgs = @(@{ Label = (T 'Highest FPS'); Args = '-dev +fps_max 0'; Rec = -not ($laptop -and $hz) })
    if ($hz) { $apexArgs += @{ Label = (T 'Capped to your {0} Hz screen (cooler, steadier)' $hz); Args = "-dev +fps_max $hz"; Rec = $laptop } }

    # ---------------- Fortnite ----------------
    $fnMenu = @(
        @('Window Mode', 'Fullscreen'),
        @('Rendering Mode', 'Performance'),
        @('Frame Rate Limit', $(if ($laptop -and $hz) { "$hz FPS" } else { 'Unlimited' })),
        @('V-Sync', 'Off'),
        @('3D Resolution', '100%'),
        @('View Distance', 'Near'),
        @('Textures', 'Low'),
        @('Meshes', 'Low')
    )
    if ($nvidia) { $fnMenu += , @('NVIDIA Reflex Low Latency', $reflex) }
    $fnMenu += , @('Show FPS', 'On')
    $fs = '/Script/FortniteGame.FortGameUserSettings'

    # ---------------- Counter-Strike 2 ----------------
    $csMenu = @(
        @('Display Mode', 'Fullscreen'),
        @('Boost Player Contrast', 'Enabled'),
        @('Wait for Vertical Sync', 'Disabled')
    )
    if ($nvidia) { $csMenu += , @('NVIDIA Reflex Low Latency', 'Enabled') }
    $csMenu += @(
        @('Multisampling Anti-Aliasing Mode', 'CMAA2'),
        @('Global Shadow Quality', 'Low'),
        @('Dynamic Shadows', 'All'),
        @('Texture Detail', $tex),
        @('Shader Detail', 'Low'),
        @('Particle Detail', 'Low'),
        @('Ambient Occlusion', 'Disabled'),
        @('FidelityFX Super Resolution', 'Disabled')
    )
    $csChecks = @(
        @{ Name = 'Display mode'; Entries = @('setting.fullscreen'); Want = '1'; WantText = 'Fullscreen'; Labels = @{ '1' = 'Fullscreen'; '0' = 'Windowed' } },
        @{ Name = 'Vertical sync'; Entries = @('setting.mat_vsync'); Want = '0'; WantText = 'Disabled'; Labels = @{ '0' = 'Disabled'; '1' = 'Enabled' } }
    )
    if ($nvidia) { $csChecks += @{ Name = 'NVIDIA Reflex'; Entries = @('setting.r_low_latency'); Want = '1'; Op = 'ge'; WantText = 'Enabled'; Labels = @{ '0' = 'Disabled'; '1' = 'Enabled'; '2' = 'Enabled + Boost' } } }

    # ---------------- Valorant ----------------
    $valMenu = @(
        @('Display Mode', 'Fullscreen'),
        @('Multithreaded Rendering', 'On'),
        @('Material Quality', 'Low'),
        @('Texture Quality', $tex),
        @('Detail Quality', 'Low'),
        @('UI Quality', 'Low'),
        @('Vignette', 'Off'),
        @('VSync', 'Off'),
        @('Anti-Aliasing', 'MSAA 2x'),
        @('Anisotropic Filtering', '4x'),
        @('Bloom', 'Off'),
        @('Distortion', 'Off'),
        @('Cast Shadows', 'Off')
    )
    if ($nvidia) { $valMenu += , @('NVIDIA Reflex Low Latency', $reflex) }
    $valMenu += @(@('Limit FPS in Menus', 'On'), @('Limit FPS in Background', 'On'))

    # ---------------- Overwatch 2 ----------------
    $owMenu = @(
        @('Display Mode', 'Fullscreen'),
        @('VSync', 'Off'),
        @('Triple Buffering', 'Off'),
        @('Reduce Buffering', 'On')
    )
    if ($nvidia) { $owMenu += , @('NVIDIA Reflex', 'Enabled + Boost') }
    $owMenu += @(
        @('Frame Rate', $(if ($hz) { "Custom, at least $hz" } else { 'Custom, at least your refresh rate' })),
        @('Dynamic Render Scale', 'Off'),
        @('Render Scale', '100%'),
        @('Graphics Quality', 'Low'),
        @('Texture Quality', $tex),
        @('Ambient Occlusion', 'Off')
    )

    # ---------------- Rainbow Six Siege X ----------------
    $r6Menu = @(
        @('Display Mode', 'Fullscreen'),
        @('V-Sync', 'Off')
    )
    if ($nvidia) { $r6Menu += , @('NVIDIA Reflex', 'On + Boost') }
    $r6Menu += @(
        @('Texture Quality', $tex),
        @('Shadow Quality', 'Low'),
        @('Reflection Quality', 'Low'),
        @('Ambient Occlusion', 'Off'),
        @('Lens Effects', 'Off'),
        @('Zoom-In Depth of Field', 'Off'),
        @('Render Scaling', '100')
    )

    @(
        [pscustomobject]@{
            Id = 'apex'; Name = 'Apex Legends'; Mono = 'AL'; Match = '^Apex Legends'; SteamAppId = 1172470; EpicApp = ''
            DefaultLauncher = 'EA app'; Launchers = @('Steam', 'EA app'); Exes = @('r5apex.exe', 'r5apex_dx12.exe')
            Config = { Join-Path (Get-OzSavedGamesDir) 'Respawn\Apex\local\videoconfig.txt' }; Format = 'Vdf'
            Checks = @(
                @{ Name = 'Display mode'; Entries = @('setting.fullscreen'); Want = '1'; WantText = 'Full Screen'; Labels = @{ '1' = 'Full Screen'; '0' = 'Windowed / Borderless' } },
                @{ Name = 'V-Sync'; Entries = @('setting.mat_vsync_mode', 'setting.mat_vsync_mod'); Want = '0'; WantText = 'Disabled'; Labels = @{ '0' = 'Disabled'; '1' = 'Double Buffered'; '2' = 'Triple Buffered'; '3' = 'Adaptive'; '4' = 'Adaptive (1/2 Rate)' } },
                @{ Name = 'Adaptive resolution'; Entries = @('setting.dvs_enable'); Want = '0'; WantText = 'Off'; Labels = @{ '0' = 'Off'; '1' = 'On' } },
                @{ Name = 'Ambient occlusion'; Entries = @('setting.ssao_enabled', 'setting.ssao_quality'); Want = '0'; WantText = 'Disabled'; Labels = @{ '0' = 'Disabled'; '1' = 'On'; '2' = 'On'; '3' = 'On'; '4' = 'On' } },
                @{ Name = 'Volumetric lighting'; Entries = @('setting.volumetric_lighting'); Want = '0'; WantText = 'Disabled'; Labels = @{ '0' = 'Disabled'; '1' = 'Enabled' } }
            )
            MenuPath = 'Settings > Video'; Menu = $apexMenu
            LaunchArgs = $apexArgs
            LaunchNote = (T '-dev skips the intro videos. +fps_max 0 removes the frame cap; the capped version runs cooler and steadier, which suits laptops.')
            LaunchWhere = $where
        }
        [pscustomobject]@{
            Id = 'fortnite'; Name = 'Fortnite'; Mono = 'FN'; Match = '^Fortnite$'; SteamAppId = 0; EpicApp = 'Fortnite'
            DefaultLauncher = 'Epic'; Launchers = @('Epic'); Exes = @('FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe', 'FortniteGame\Binaries\Win64\FortniteLauncher.exe')
            Config = { Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini' }; Format = 'Ini'
            Checks = @(
                @{ Name = 'Rendering mode'; Entries = @('D3DRHIPreference|PreferredFeatureLevel'); Default = 'sm5'; Want = 'es31'; WantText = 'Performance'; Labels = @{ 'es31' = 'Performance'; 'sm5' = 'DirectX 11 / 12'; 'sm6' = 'DirectX 12' } },
                @{ Name = 'Window mode'; Entries = @("$fs|FullscreenMode"); Want = '0'; WantText = 'Fullscreen'; Labels = @{ '0' = 'Fullscreen'; '1' = 'Windowed Fullscreen'; '2' = 'Windowed' } },
                @{ Name = 'V-Sync'; Entries = @("$fs|bUseVSync"); Want = 'False'; WantText = 'Off'; Labels = @{ 'False' = 'Off'; 'True' = 'On' } },
                @{ Name = 'Motion blur'; Entries = @("$fs|bMotionBlur"); Want = 'False'; WantText = 'Off'; Labels = @{ 'False' = 'Off'; 'True' = 'On' } },
                @{ Name = 'Ray tracing'; Entries = @("$fs|bRayTracing"); Want = 'False'; WantText = 'Off'; Labels = @{ 'False' = 'Off'; 'True' = 'On' } }
            )
            MenuPath = 'Settings > Display and Graphics'; Menu = $fnMenu
            LaunchArgs = @(@{ Label = (T 'Force Performance mode'); Args = '-FeatureLevelES31'; Rec = $false })
            LaunchNote = (T 'Only needed if Rendering Mode keeps switching back from Performance. Epic documents this option to force it.')
            LaunchWhere = $where
        }
        [pscustomobject]@{
            Id = 'cs2'; Name = 'Counter-Strike 2'; Mono = 'CS'; Match = '^Counter-Strike 2$'; SteamAppId = 730; EpicApp = ''
            DefaultLauncher = 'Steam'; Launchers = @('Steam'); Exes = @('game\bin\win64\cs2.exe')
            Config = {
                param($Steam)
                if ($Steam -and $Steam.Root) {
                    Get-ChildItem -Path (Join-Path $Steam.Root 'userdata\*\730\local\cfg\cs2_video.txt') -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
                }
            }; Format = 'Vdf'
            Checks = $csChecks
            MenuPath = 'Settings > Video'; Menu = $csMenu
            LaunchArgs = @()
            LaunchNote = (T 'Not needed. CS2 ignores most old CS:GO launch options (-tickrate, -high, -threads). Set everything in the game menu.')
            LaunchWhere = $where
        }
        [pscustomobject]@{
            Id = 'valorant'; Name = 'VALORANT'; Mono = 'VA'; Match = '^VALORANT$'; SteamAppId = 0; EpicApp = ''
            DefaultLauncher = 'Riot Client'; Launchers = @(); Exes = @('VALORANT.exe', 'ShooterGame\Binaries\Win64\VALORANT-Win64-Shipping.exe')
            Config = $null; Format = ''; Checks = @()
            MenuPath = 'Settings > Video'; Menu = $valMenu
            LaunchArgs = @()
            LaunchNote = (T 'Not available. The Riot Client has no launch options; everything is set in the game menu.')
            LaunchWhere = $where
        }
        [pscustomobject]@{
            Id = 'overwatch'; Name = 'Overwatch 2'; Mono = 'OW'; Match = '^Overwatch( 2)?$'; SteamAppId = 2357570; EpicApp = ''
            DefaultLauncher = 'Battle.net'; Launchers = @(); Exes = @('_retail_\Overwatch.exe', 'Overwatch.exe', 'Overwatch Launcher.exe')
            Config = $null; Format = ''; Checks = @()
            MenuPath = 'Options > Video'; Menu = $owMenu
            LaunchArgs = @()
            LaunchNote = (T 'Not needed. Overwatch 2 has no launch options that raise FPS.')
            LaunchWhere = $where
        }
        [pscustomobject]@{
            Id = 'r6'; Name = 'Rainbow Six Siege X'; Mono = 'R6'; Match = 'Rainbow Six.*Siege'; SteamAppId = 359550; EpicApp = ''
            DefaultLauncher = 'Ubisoft Connect'; Launchers = @(); Exes = @('RainbowSix.exe', 'RainbowSix_Vulkan.exe')
            Config = $null; Format = ''; Checks = @()
            MenuPath = 'Options > Display and Graphics'; Menu = $r6Menu
            LaunchArgs = @()
            LaunchNote = (T 'Not needed. Siege X has no launch options that raise FPS.')
            LaunchWhere = $where
        }
    )
}

function Find-OzGame {
    # Where a game is installed and which launcher manages it. Nothing if it is not installed.
    param($Game, $Uninstall, $Steam, $Epic)
    if ($Game.EpicApp) {
        $e = @($Epic | Where-Object { $_.AppName -eq $Game.EpicApp -or $_.Name -eq $Game.Name }) | Select-Object -First 1
        if ($e -and (Test-Path -LiteralPath $e.Location)) {
            return [pscustomobject]@{ Launcher = 'Epic'; Location = $e.Location; Icon = (Get-OzIconFile -Location $e.Location -Exes (@($e.Exe) + $Game.Exes)) }
        }
    }
    if ($Game.SteamAppId) {
        $d = Find-OzSteamGame $Steam $Game.SteamAppId
        if ($d) { return [pscustomobject]@{ Launcher = 'Steam'; Location = $d; Icon = (Get-OzIconFile -Location $d -Exes $Game.Exes) } }
    }
    $u = @($Uninstall | Where-Object { $_.Name -match $Game.Match }) | Select-Object -First 1
    if ($u) {
        $l = if ($u.Key -like 'Steam App *') { 'Steam' } elseif ($u.Key -like 'Uplay Install *') { 'Ubisoft Connect' } elseif ($u.Key -like 'Riot Game *') { 'Riot Client' } else { $Game.DefaultLauncher }
        return [pscustomobject]@{ Launcher = $l; Location = $u.Location; Icon = (Get-OzIconFile -DisplayIcon $u.Icon -Location $u.Location -Exes $Game.Exes) }
    }
}

function Get-OzGameScan {
    # Every supported game: installed or not, where, its settings file and how it compares
    $un = @(Get-OzUninstallEntries)
    $steam = Get-OzSteamInfo
    $epic = @(Get-OzEpicGames)
    foreach ($g in (Get-OzGameCatalog)) {
        $found = $null
        try { $found = Find-OzGame $g $un $steam $epic } catch { }
        $cfg = $null
        if ($g.Config) { try { $cfg = [string](& $g.Config $steam | Select-Object -First 1) } catch { } }
        $review = @()
        $cfgFound = [bool]($cfg -and [IO.File]::Exists($cfg))
        if ($cfgFound -and $g.Checks.Count) {
            $map = Read-OzGameConfig $cfg $g.Format
            foreach ($c in $g.Checks) { $review += Test-OzGameCheck $c $map }
        }
        [pscustomobject]@{
            Game = $g; Installed = [bool]$found
            Launcher = $(if ($found) { $found.Launcher } else { '' })
            Location = $(if ($found) { $found.Location } else { '' })
            IconPath = $(if ($found) { $found.Icon } else { '' })
            ConfigPath = $cfg; ConfigFound = $cfgFound; Review = $review
        }
    }
}

function Show-OzGames {
    param($Games)
    $Games = @($Games | Where-Object { $_ })
    $Oz.LastGames = $Games
    $panel = $Oz.UI.GamesPanel
    $panel.Children.Clear()
    $inst = @($Games | Where-Object { $_.Installed }).Count
    $Oz.UI.GamesHint.Text = if ($inst) {
        T '{0} of {1} games found on this PC. Setting and launcher names are shown as they appear in English menus.' $inst $Games.Count
    } else {
        T 'None of these games were found on this PC. The recommended settings still apply if you install one.'
    }
    # Installed games first, in catalog order
    foreach ($r in @($Games | Where-Object { $_.Installed }) + @($Games | Where-Object { -not $_.Installed })) {
        [void]$panel.Children.Add((New-OzGameCard $r))
    }
    Write-OzLog (T 'Games checked: {0} found on this PC.' $inst) 'OK'
}

function New-OzGameCard {
    param($R)
    $g = $R.Game
    $card = New-OzCard
    $sp = New-Object System.Windows.Controls.StackPanel

    # ---- header: icon, name, where it is installed, settings summary, details toggle ----
    $head = New-OzColumns @('Auto', '*', 'Auto')
    $tile = New-Object System.Windows.Controls.Border
    $tile.Width = 48; $tile.Height = 48
    $tile.CornerRadius = New-Object System.Windows.CornerRadius(12)
    $tile.Background = Get-OzBrush '#0C1222'
    $tile.BorderBrush = Get-OzBrush $(if ($R.Installed) { '#5500E5FF' } else { '#1B2A48' })
    $tile.BorderThickness = New-OzThickness '1'
    $tile.Margin = New-OzThickness '0,0,14,0'
    $img = if ($R.IconPath) { Get-OzFileIcon $R.IconPath } else { $null }
    if ($img) {
        $im = New-Object System.Windows.Controls.Image
        $im.Source = $img
        $im.Width = 32; $im.Height = 32
        [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($im, [System.Windows.Media.BitmapScalingMode]::HighQuality)
        $tile.Child = $im
    } else {
        $mono = New-OzText -Text $g.Mono -Size 16 -Color $(if ($R.Installed) { '#00E5FF' } else { '#5D6E92' }) -Display -Bold
        $mono.HorizontalAlignment = 'Center'; $mono.VerticalAlignment = 'Center'
        $tile.Child = $mono
    }
    Add-OzGridChild $head $tile 0
    $ttl = New-Object System.Windows.Controls.StackPanel
    $ttl.VerticalAlignment = 'Center'
    [void]$ttl.Children.Add((New-OzText -Text $g.Name -Size 17 -Color '#E6F1FF' -Display -Bold))
    $status = if ($R.Installed) { New-OzText -Text (T 'Installed with {0}' $R.Launcher) -Size 11.5 -Color '#2BFF9A' -Display -Semi -Margin '0,2,0,0' }
    else { New-OzText -Text (T 'Not found on this PC') -Size 11.5 -Color '#5D6E92' -Display -Semi -Margin '0,2,0,0' }
    [void]$ttl.Children.Add($status)
    Add-OzGridChild $head $ttl 1
    $right = New-Object System.Windows.Controls.StackPanel
    $right.Orientation = 'Horizontal'
    $right.VerticalAlignment = 'Center'
    $checked = @($R.Review | Where-Object { $null -ne $_.Ok })
    if ($checked.Count) {
        $good = @($checked | Where-Object { $_.Ok }).Count
        $color = if ($good -eq $checked.Count) { '#2BFF9A' } else { '#FFB020' }
        $badge = New-OzBadge -Text (T '{0} / {1} SETTINGS OK' $good $checked.Count) -Color $color
        $badge.Margin = New-OzThickness '0,0,10,0'
        [void]$right.Children.Add($badge)
    }
    $details = New-Object System.Windows.Controls.StackPanel
    $details.Margin = New-OzThickness '0,14,0,0'
    $details.Visibility = if ($R.Installed) { 'Visible' } else { 'Collapsed' }
    $toggle = New-OzButton -Text $(if ($R.Installed) { T 'HIDE' } else { T 'DETAILS' }) -Style 'Neon' -Margin '0'
    $toggle.Tag = @{ Panel = $details; Show = (T 'DETAILS'); Hide = (T 'HIDE') }
    $toggle.Add_Click({
            $t = $this.Tag
            $open = $t.Panel.Visibility -ne 'Visible'
            $t.Panel.Visibility = $(if ($open) { 'Visible' } else { 'Collapsed' })
            $this.Content = $(if ($open) { $t.Hide } else { $t.Show })
        })
    [void]$right.Children.Add($toggle)
    Add-OzGridChild $head $right 2
    [void]$sp.Children.Add($head)

    # ---- the game's own settings file ----
    if ($g.Checks.Count -and ($R.Installed -or $R.ConfigFound)) {
        [void]$details.Children.Add((New-OzText -Text (T 'YOUR SETTINGS FILE') -Size 10.5 -Color '#5D6E92' -Display -Bold -Margin '0,0,0,6'))
        if (-not $R.ConfigFound) {
            [void]$details.Children.Add((New-OzText -Text (T 'Settings file not found. Start the game once, close it, then press RESCAN GAMES.') -Size 12.5 -Wrap -Margin '0,0,0,12'))
        } else {
            foreach ($c in $R.Review) {
                $row = New-OzRowBorder -Margin '0,0,0,6' -Padding '12,7,12,7'
                $cols = New-OzColumns @('Auto', '*', 'Auto')
                if ($null -eq $c.Ok) { $gl = [char]0xE9CE; $gc = '#5D6E92' } elseif ($c.Ok) { $gl = [char]0xE73E; $gc = '#2BFF9A' } else { $gl = [char]0xE7BA; $gc = '#FFB020' }
                Add-OzGridChild $cols (New-OzText -Text ([string]$gl) -Size 13 -Color $gc -Icon -Margin '0,1,10,0') 0
                Add-OzGridChild $cols (New-OzText -Text $c.Name -Size 12.5 -Color '#E6F1FF') 1
                $val = if ($null -eq $c.Ok) { New-OzText -Text (T 'not in this version of the file') -Size 12 -Color '#5D6E92' }
                elseif ($c.Ok) { New-OzText -Text $c.Current -Size 12 -Color '#2BFF9A' -Mono }
                else { New-OzText -Text (T '{0}  ->  set to {1}' $c.Current $c.Want) -Size 12 -Color '#FFB020' -Mono }
                Add-OzGridChild $cols $val 2
                $row.Child = $cols
                [void]$details.Children.Add($row)
            }
            $folder = Split-Path -Parent $R.ConfigPath
            $ob = New-OzButton -Text (T 'OPEN SETTINGS FOLDER') -Style 'NeonViolet' -Tag $folder -Margin '0,4,0,14'
            $ob.HorizontalAlignment = 'Left'
            $ob.Add_Click({ Open-OzLink ([string]$this.Tag) })
            [void]$details.Children.Add($ob)
        }
    }

    # ---- what to set in the game menu ----
    [void]$details.Children.Add((New-OzText -Text ((T 'SET IN THE GAME MENU') + '   //   ' + $g.MenuPath) -Size 10.5 -Color '#5D6E92' -Display -Bold -Margin '0,0,0,6'))
    $menu = New-Object System.Windows.Controls.Primitives.UniformGrid
    $menu.Columns = 2
    $menu.Margin = New-OzThickness '0,0,0,12'
    foreach ($m in $g.Menu) {
        $line = New-OzColumns @('*', 'Auto')
        $line.Margin = New-OzThickness '0,2,24,2'
        Add-OzGridChild $line (New-OzText -Text $m[0] -Size 12.5 -Color '#8A9BBF') 0
        Add-OzGridChild $line (New-OzText -Text $m[1] -Size 12.5 -Color '#E6F1FF' -Semi -Margin '12,0,0,0') 1
        [void]$menu.Children.Add($line)
    }
    [void]$details.Children.Add($menu)

    # ---- launch options ----
    [void]$details.Children.Add((New-OzText -Text (T 'LAUNCH OPTIONS') -Size 10.5 -Color '#5D6E92' -Display -Bold -Margin '0,0,0,6'))
    foreach ($a in $g.LaunchArgs) {
        $row = New-OzRowBorder -Margin '0,0,0,6' -Padding '12,8,12,8'
        $cols = New-OzColumns @('*', 'Auto')
        $left = New-Object System.Windows.Controls.StackPanel
        $lh = New-Object System.Windows.Controls.StackPanel
        $lh.Orientation = 'Horizontal'
        [void]$lh.Children.Add((New-OzText -Text $a.Label -Size 12 -Color '#8A9BBF'))
        if ($a.Rec) { [void]$lh.Children.Add((New-OzBadge -Text (T 'RECOMMENDED') -Color '#00E5FF')) }
        [void]$left.Children.Add($lh)
        $box = New-Object System.Windows.Controls.TextBox
        $box.Text = $a.Args
        $box.IsReadOnly = $true
        $box.Background = Get-OzBrush '#00000000'
        $box.BorderThickness = New-OzThickness '0'
        $box.Foreground = Get-OzBrush '#9FE9FF'
        $box.FontFamily = $Oz.Window.FindResource('Mono')
        $box.FontSize = 13.5
        $box.Margin = New-OzThickness '0,3,0,0'
        [void]$left.Children.Add($box)
        Add-OzGridChild $cols $left 0
        $cb = New-OzButton -Text (T 'COPY') -Style 'Neon' -Tag $a.Args -Margin '0'
        $cb.VerticalAlignment = 'Center'
        $cb.Add_Click({
                try { [System.Windows.Clipboard]::SetText([string]$this.Tag); Write-OzLog (T 'Copied: {0}' ([string]$this.Tag)) 'OK' }
                catch { Write-OzLog (T 'Could not copy. Select the text and press Ctrl+C.') 'WARN' }
            })
        Add-OzGridChild $cols $cb 1
        $row.Child = $cols
        [void]$details.Children.Add($row)
    }
    if ($g.LaunchArgs.Count) {
        $launchers = if ($R.Installed -and $g.Launchers -contains $R.Launcher) { @($R.Launcher) } else { @($g.Launchers) }
        foreach ($l in $launchers) {
            if ($g.LaunchWhere[$l]) { [void]$details.Children.Add((New-OzText -Text (($g.LaunchWhere[$l]) -f $g.Name) -Size 12 -Color '#E6F1FF' -Mono -Wrap -Margin '0,4,0,0')) }
        }
    }
    [void]$details.Children.Add((New-OzText -Text $g.LaunchNote -Size 12.5 -Wrap -Margin '0,6,0,0'))

    [void]$sp.Children.Add($details)
    $card.Child = $sp
    $card
}
#endregion

#region ============================ DEBLOAT VIEW ============================
function Show-OzBloat {
    param($Found)
    $list = $Oz.UI.BloatList
    $keep = @{}
    foreach ($c in @($Oz.BloatChecks)) { if ($c) { $keep[$c.Tag.Pattern] = [bool]$c.IsChecked } }
    $list.Children.Clear()
    $Oz.BloatChecks = @()
    $Found = @($Found)
    $Oz.LastBloat = $Found
    if (-not $Found.Count) { $Oz.UI.BloatHint.Text = T 'No known bloat found - this Windows is already clean.'; return }
    $Oz.UI.BloatHint.Text = T '{0} removable app(s) found. Recommended ones are pre-selected.' $Found.Count
    foreach ($b in $Found) {
        $row = New-OzRowBorder -Margin '0,0,10,8'
        $grid = New-OzColumns @('*', 'Auto')
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Style = $Oz.Window.FindResource('Tick')
        $cb.Tag = $b
        $cb.IsChecked = if ($keep.ContainsKey($b.Pattern)) { $keep[$b.Pattern] } else { [bool]$b.Rec }
        $content = New-Object System.Windows.Controls.StackPanel
        [void]$content.Children.Add((New-OzText -Text (T $b.Name) -Size 13 -Color '#E6F1FF' -Semi))
        [void]$content.Children.Add((New-OzText -Text (($b.Packages | Select-Object -First 2) -join ', ') -Size 10.5 -Color '#5D6E92' -Mono))
        $cb.Content = $content
        Add-OzGridChild $grid $cb 0
        if ($b.Rec) { Add-OzGridChild $grid (New-OzBadge (T 'RECOMMENDED') '#B79BFF') 1 }
        $row.Child = $grid
        [void]$list.Children.Add($row)
        $Oz.BloatChecks += $cb
    }
}
#endregion

#region ============================ DRIVERS VIEW ============================
function Show-OzDriverRecs {
    $panel = $Oz.UI.DriverRecPanel
    $panel.Children.Clear()
    $catColor = @{ GPU = '#FF2BD6'; Chipset = '#00E5FF'; OEM = '#FFB020'; Board = '#FFB020'; Network = '#2BFF9A'; Windows = '#B79BFF' }
    foreach ($r in @(Get-OzDriverRecommendations $Oz.Sys)) {
        $card = New-OzCard
        $sp = New-Object System.Windows.Controls.StackPanel
        $col = if ($catColor.ContainsKey($r.Cat)) { $catColor[$r.Cat] } else { '#00E5FF' }
        [void]$sp.Children.Add((New-OzText -Text (T $r.Cat).ToUpper() -Size 10.5 -Color $col -Display -Semi))
        [void]$sp.Children.Add((New-OzText -Text $r.Title -Size 14 -Color '#E6F1FF' -Display -Semi -Wrap -Margin '0,4,0,4'))
        [void]$sp.Children.Add((New-OzText -Text $r.Text -Size 12 -Wrap -Margin '0,0,0,10'))
        $btn = New-OzButton -Text $r.Button -Tag $r.Url
        $btn.HorizontalAlignment = 'Left'
        $btn.ToolTip = $r.Url
        $btn.Add_Click({ Open-OzLink $this.Tag })
        [void]$sp.Children.Add($btn)
        $card.Child = $sp
        [void]$panel.Children.Add($card)
    }
}

function Show-OzDriverScan {
    param($Scan, [switch]$Quiet)
    $pp = $Oz.UI.DriverProblemPanel
    $pp.Children.Clear()
    if (-not $Scan) { return }
    $Oz.LastDriverScan = $Scan
    if (-not @($Scan.Problems).Count) {
        [void]$pp.Children.Add((New-OzText -Text (T 'No devices with problems. Every device has a working driver.') -Size 12.5 -Color '#2BFF9A'))
    } else {
        foreach ($p in $Scan.Problems) {
            $row = New-OzRowBorder
            $row.BorderBrush = Get-OzBrush '#55FF3B5C'
            $sp = New-Object System.Windows.Controls.StackPanel
            [void]$sp.Children.Add((New-OzText -Text $p.Name -Size 13 -Color '#E6F1FF' -Semi))
            $code = [int]$p.Code
            $meaning = if ($Oz.DeviceCodes -and $Oz.DeviceCodes.ContainsKey($code)) { T $Oz.DeviceCodes[$code] } else { T 'error code {0}' $code }
            [void]$sp.Children.Add((New-OzText -Text (T 'Code {0}: {1}' $code $meaning) -Size 12 -Color '#FF8FA3'))
            $row.Child = $sp
            [void]$pp.Children.Add($row)
        }
    }
    $lp = $Oz.UI.DriverListPanel
    $lp.Children.Clear()
    foreach ($d in @($Scan.Drivers)) {
        $row = New-OzRowBorder -Margin '0,0,0,4' -Padding '12,6,12,6'
        $grid = New-OzColumns @('90', '*', '170', '110', '80')
        Add-OzGridChild $grid (New-OzText -Text ([string]$d.Class) -Size 11 -Color '#00E5FF' -Display -Semi) 0
        $nm = New-OzText -Text ('{0}  ({1})' -f $d.Name, $d.Provider) -Size 12 -Color '#E6F1FF'
        $nm.TextTrimming = 'CharacterEllipsis'
        Add-OzGridChild $grid $nm 1
        Add-OzGridChild $grid (New-OzText -Text ([string]$d.Version) -Size 11 -Mono) 2
        $dt = ''
        try { if ($d.Date) { $dt = ([datetime]$d.Date).ToString('yyyy-MM-dd') } } catch { }
        Add-OzGridChild $grid (New-OzText -Text $dt -Size 11 -Mono) 3
        $ageCol = if ($null -eq $d.AgeDays) { '#5D6E92' } elseif ($d.AgeDays -gt 730) { '#FF3B5C' } elseif ($d.AgeDays -gt 365) { '#FFB020' } else { '#2BFF9A' }
        $ageTxt = if ($null -eq $d.AgeDays) { '' } elseif ($d.AgeDays -gt 365) { (T '{0:N1} y' ($d.AgeDays / 365)) } else { (T '{0} d' $d.AgeDays) }
        Add-OzGridChild $grid (New-OzText -Text $ageTxt -Size 11 -Color $ageCol -Mono) 4
        $row.Child = $grid
        [void]$lp.Children.Add($row)
    }
    if (-not $Quiet) { Write-OzLog (T 'Driver scan: {0} key drivers, {1} problem device(s).' @($Scan.Drivers).Count @($Scan.Problems).Count) 'OK' }
}
#endregion

#region ============================ TOOLS VIEW ============================
function Update-OzPowerText {
    if (-not $Oz.UI.PowerCurrent -or -not $Oz.Sys) { return }
    $Oz.UI.PowerCurrent.Text = T 'Active plan: {0}. PERFORMANCE = max boost, cool idle. SMART = fast + cool (best for laptops). COOL = turbo off, much cooler and quieter.' $Oz.Sys.Power.Name
}

function Show-OzCleanDrives {
    # The drive tick boxes of CLEAN UP FILES. Only the Windows drive is ticked at first.
    $panel = $Oz.UI.CleanDrivePanel
    if (-not $panel) { return }
    if ($null -eq $Oz.CleanDrives) { $Oz.CleanDrives = @(Get-OzCleanDrive) }
    if ($null -eq $Oz.CleanDriveSel) { $Oz.CleanDriveSel = @{} }
    foreach ($d in $Oz.CleanDrives) { if (-not $Oz.CleanDriveSel.ContainsKey($d.Drive)) { $Oz.CleanDriveSel[$d.Drive] = [bool]$d.IsWindows } }
    $panel.Children.Clear()
    if (-not $Oz.CleanDrives.Count) { [void]$panel.Children.Add((New-OzText -Text (T 'No local drives found.') -Size 12.5)); return }
    foreach ($d in $Oz.CleanDrives) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Style = $Oz.Window.FindResource('Tick')
        $cb.Tag = $d.Drive
        $cb.IsChecked = [bool]$Oz.CleanDriveSel[$d.Drive]
        $cb.Margin = New-OzThickness '0,0,22,8'
        $sp = New-Object System.Windows.Controls.StackPanel
        $title = if ($d.IsWindows) { T '{0}  Windows drive' $d.Drive } elseif ($d.Label) { '{0}  {1}' -f $d.Drive, $d.Label } else { T '{0}  Local drive' $d.Drive }
        [void]$sp.Children.Add((New-OzText -Text $title -Size 13 -Color '#E6F1FF' -Semi))
        [void]$sp.Children.Add((New-OzText -Text (T '{0:N1} GB free of {1:N1} GB' $d.FreeGB $d.SizeGB) -Size 10.5 -Color '#5D6E92' -Mono))
        $cb.Content = $sp
        $cb.Add_Click({ $Oz.CleanDriveSel[[string]$this.Tag] = [bool]$this.IsChecked })
        [void]$panel.Children.Add($cb)
    }
}

function Show-OzCleanList {
    # The scan result: one block per drive, one tick box per item with its size and folders
    param($Items, [switch]$KeepChecks)
    $list = $Oz.UI.CleanList
    if (-not $list) { return }
    $keep = @{}
    if ($KeepChecks) { foreach ($c in @($Oz.CleanChecks)) { if ($c) { $keep[$c.Tag.Key] = [bool]$c.IsChecked } } }
    $list.Children.Clear()
    $Oz.CleanChecks = @()
    $Items = @($Items)
    $Oz.LastCleanScan = $Items
    if (-not $Items.Count) {
        $Oz.UI.CleanHint.Text = T 'Nothing to clean on the drives you picked.'
        Update-OzCleanTotal
        return
    }
    $Oz.UI.CleanHint.Text = T 'Tick what you want to delete. Recommended items that have something to clean are already ticked.'
    $win = Get-OzWindowsDrive
    foreach ($drive in @($Items | ForEach-Object { $_.Drive } | Select-Object -Unique)) {
        $head = if ($drive -eq $win) { T '{0}  WINDOWS DRIVE' $drive } else { T '{0}  OTHER DRIVE  -  only its Recycle Bin can be emptied here, your files are never listed' $drive }
        [void]$list.Children.Add((New-OzText -Text $head -Size 11 -Color '#00E5FF' -Display -Semi -Wrap -Margin '0,6,0,8'))
        foreach ($it in @($Items | Where-Object { $_.Drive -eq $drive })) {
            $empty = ($it.Bytes -eq 0)
            $row = New-OzRowBorder -Margin '0,0,0,8'
            $grid = New-OzColumns @('*', 'Auto', 'Auto')
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Style = $Oz.Window.FindResource('Tick')
            $cb.Tag = $it
            $cb.IsChecked = if ($keep.ContainsKey($it.Key)) { $keep[$it.Key] } else { [bool]$it.Rec -and -not $empty }
            if ($empty) { $cb.IsChecked = $false; $cb.IsEnabled = $false; $row.Opacity = 0.55 }
            $cb.Add_Click({ Update-OzCleanTotal })
            $content = New-Object System.Windows.Controls.StackPanel
            [void]$content.Children.Add((New-OzText -Text (T $it.Name) -Size 13 -Color '#E6F1FF' -Semi -Wrap))
            [void]$content.Children.Add((New-OzText -Text (T $it.Desc) -Size 11.5 -Wrap -Margin '0,2,0,0'))
            $paths = @($it.Paths)
            if ($paths.Count) {
                $shown = ($paths | Select-Object -First 3) -join "`n"
                if ($paths.Count -gt 3) { $shown += "`n" + (T '+{0} more' ($paths.Count - 3)) }
                [void]$content.Children.Add((New-OzText -Text $shown -Size 10.5 -Color '#5D6E92' -Mono -Wrap -Margin '0,4,0,0'))
            }
            foreach ($s in @($it.Skipped)) {
                if ($s) { [void]$content.Children.Add((New-OzText -Text (T 'Left alone: {0} ({1})' $s.Path (T $s.Why)) -Size 10.5 -Color '#FFB020' -Wrap -Margin '0,4,0,0')) }
            }
            $cb.Content = $content
            Add-OzGridChild $grid $cb 0
            $sizeText = if ($empty) { T 'nothing to clean' } else { Format-OzBytes $it.Bytes }
            $size = New-OzText -Text $sizeText -Size 13 -Color $(if ($empty) { '#5D6E92' } else { '#00E5FF' }) -Mono -Semi -Margin '14,0,0,0'
            $size.VerticalAlignment = 'Top'
            Add-OzGridChild $grid $size 1
            if ($it.Rec) {
                $badge = New-OzBadge (T 'RECOMMENDED') '#B79BFF'
                $badge.VerticalAlignment = 'Top'
                Add-OzGridChild $grid $badge 2
            }
            $row.Child = $grid
            [void]$list.Children.Add($row)
            $Oz.CleanChecks += $cb
        }
    }
    Update-OzCleanTotal
}

function Update-OzCleanTotal {
    if (-not $Oz.UI.CleanTotal) { return }
    if (-not @($Oz.CleanChecks).Count) { $Oz.UI.CleanTotal.Text = ''; return }
    $sel = @($Oz.CleanChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    $bytes = [int64]0
    foreach ($s in $sel) { if ($s.Bytes -gt 0) { $bytes += $s.Bytes } }
    $Oz.UI.CleanTotal.Text = T 'Selected: {0} item(s), about {1}' $sel.Count (Format-OzBytes $bytes)
}

function Set-OzCleanChecks {
    # SELECT RECOMMENDED / SELECT NONE
    param([switch]$Recommended)
    foreach ($c in @($Oz.CleanChecks)) { if ($c.IsEnabled) { $c.IsChecked = [bool]($Recommended -and $c.Tag.Rec) } }
    Update-OzCleanTotal
}

function Update-OzCleanText {
    if (-not $Oz.UI.CleanResult) { return }
    $Oz.UI.CleanResult.Text = if ($null -ne $Oz.LastCleanMB) { T 'Last clean freed {0:N0} MB' $Oz.LastCleanMB } else { '' }
    if ($Oz.UI.CleanHint -and -not $Oz.CleanShown) { $Oz.UI.CleanHint.Text = T 'Pick the drives, then press SCAN to see what can be cleaned on them.' }
}

function Set-OzPlanTweak {
    param([string]$Id)
    $target = $Oz.TweakIndex[$Id]
    $j = Read-OzJournal
    $others = @($Oz.Tweaks | Where-Object { $_.Group -eq 'plan' -and $_.Id -ne $Id -and $j.ContainsKey($_.Id) })
    Invoke-OzChangeSet -ToApply @($target) -ToRevert $others
}

function Initialize-OzTools {
    $Oz.UI.DnsPanel.Children.Clear()
    $cur = $Oz.DnsNow
    if ($null -eq $cur) { $cur = Get-OzCurrentDns; $Oz.DnsNow = $cur }
    $Oz.DnsChoice = $null
    foreach ($k in $Oz.DnsChoices.Keys) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $Oz.Window.FindResource('Chip')
        $rb.GroupName = 'dns'
        $rb.Content = T $k
        $rb.Tag = $k
        if ($k -eq $cur) { $rb.IsChecked = $true; $Oz.DnsChoice = $k }
        $rb.Add_Checked({ $Oz.DnsChoice = $this.Tag })
        [void]$Oz.UI.DnsPanel.Children.Add($rb)
    }
    $Oz.UI.DnsCurrent.Text = if ($cur) {
        $label = if ($Oz.DnsChoices.Contains($cur)) { T $cur } else { $cur }
        T 'Now: {0}. Pick a resolver and apply it to every connected adapter.' $label
    } else { T 'Faster, more private name resolution for every connected adapter.' }

    $Oz.UI.ShortcutPanel.Children.Clear()
    $shortcuts = [ordered]@{
        'Device Manager' = 'devmgmt.msc'; 'Services' = 'services.msc'; 'Task Manager' = 'taskmgr.exe'; 'System Config' = 'msconfig.exe'
        'Programs' = 'appwiz.cpl'; 'Power Options' = 'powercfg.cpl'; 'Network' = 'ncpa.cpl'; 'System Properties' = 'sysdm.cpl'
        'Disk Management' = 'diskmgmt.msc'; 'Event Viewer' = 'eventvwr.msc'; 'Resource Monitor' = 'resmon.exe'; 'Windows Security' = 'windowsdefender:'
    }
    foreach ($k in $shortcuts.Keys) {
        $b = New-OzButton -Text (T $k).ToUpper() -Style 'Neon' -Tag $shortcuts[$k] -Margin '0,0,6,6'
        $b.Padding = New-OzThickness '10,5,10,5'
        $b.FontSize = 11
        $b.Add_Click({ try { Start-Process $this.Tag } catch { Write-OzLog ((T 'Could not open {0}') -f $this.Tag) 'WARN' } })
        [void]$Oz.UI.ShortcutPanel.Children.Add($b)
    }
    Update-OzPowerText
    Show-OzCleanDrives
    if ($Oz.CleanShown -and $null -ne $Oz.LastCleanScan) { Show-OzCleanList $Oz.LastCleanScan -KeepChecks }
    Update-OzCleanText
    Update-OzStartupList
}

function Update-OzStartupList {
    $panel = $Oz.UI.StartupPanel
    $panel.Children.Clear()
    $apps = @(Get-OzStartupApps)
    if ($Oz.Sys) { $Oz.Sys.StartupCount = @($apps | Where-Object Enabled).Count }
    if (-not $apps.Count) { [void]$panel.Children.Add((New-OzText -Text (T 'No startup apps found.') -Size 12.5)); return }
    foreach ($a in $apps) {
        $row = New-OzRowBorder -Margin '0,0,0,6' -Padding '12,8,12,8'
        $grid = New-OzColumns @('Auto', '*', 'Auto')
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Style = $Oz.Window.FindResource('Switch')
        $cb.IsChecked = $a.Enabled
        $cb.Tag = $a
        $cb.Margin = New-OzThickness '0,0,14,0'
        $cb.VerticalAlignment = 'Center'
        $cb.Add_Click({ $item = $this.Tag; $on = [bool]$this.IsChecked; Invoke-OzSafe 'Startup app' { Set-OzStartupApp $item $on } })
        Add-OzGridChild $grid $cb 0
        $sp = New-Object System.Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-OzText -Text $a.Name -Size 13 -Color '#E6F1FF' -Semi))
        $cmd = New-OzText -Text $a.Command -Size 10.5 -Color '#5D6E92' -Mono
        $cmd.TextTrimming = 'CharacterEllipsis'
        [void]$sp.Children.Add($cmd)
        Add-OzGridChild $grid $sp 1
        Add-OzGridChild $grid (New-OzBadge (T $a.Scope).ToUpper() '#8A9BBF') 2
        $row.Child = $grid
        [void]$panel.Children.Add($row)
    }
}
#endregion

#region ============================ BACKUP VIEW ============================
function Update-OzJournalView {
    $panel = $Oz.UI.JournalPanel
    if (-not $panel) { return }
    $panel.Children.Clear()
    $j = Read-OzJournal
    $keys = @($j.Keys | Sort-Object { [string]$j[$_].Applied } -Descending)
    $Oz.UI.JournalSummary.Text = T '{0} change(s) tracked. Journal file: {1}' $keys.Count $Oz.Journal
    if (-not $keys.Count) { [void]$panel.Children.Add((New-OzText -Text (T 'Nothing applied yet. Changes you make will appear here with a one-click revert.') -Size 12.5)); return }
    foreach ($k in $keys) {
        $e = $j[$k]
        $row = New-OzRowBorder -Margin '0,0,0,6' -Padding '12,8,12,8'
        $grid = New-OzColumns @('*', 'Auto', 'Auto')
        $name = if ($Oz.TweakIndex.ContainsKey($k)) { T $Oz.TweakIndex[$k].Name } elseif ($e.Name) { T $e.Name } else { $k }
        Add-OzGridChild $grid (New-OzText -Text $name -Size 13 -Color '#E6F1FF' -Semi) 0
        $when = ([string]$e.Applied).Replace('T', ' ')
        $w = New-OzText -Text $when -Size 11 -Mono -Margin '12,0,12,0'
        $w.VerticalAlignment = 'Center'
        Add-OzGridChild $grid $w 1
        if ($Oz.TweakIndex.ContainsKey($k)) {
            $b = New-OzButton -Text (T 'REVERT') -Style 'NeonDanger' -Tag $k -Margin '0'
            $b.Padding = New-OzThickness '10,4,10,4'
            $b.Add_Click({ $id = $this.Tag; Invoke-OzSafe 'Revert' { Invoke-OzChangeSet -ToRevert @($Oz.TweakIndex[$id]) } })
            Add-OzGridChild $grid $b 2
        }
        $row.Child = $grid
        [void]$panel.Children.Add($row)
    }
}
#endregion

#region ============================ THEMES VIEW ============================
function Set-OzThemeValue {
    # Every control on the THEMES page writes through here, then the preview follows
    param([string]$Key, $Value)
    $Oz.ThemeCfg[$Key] = $Value
    $Oz.ThemeDirty = $true
    if ($Key -in 'AutoInk', 'InkMode') { Show-OzThemeClockPanel }
    if ($Key -eq 'Look') { Show-OzThemeLooks }
    Update-OzThemePreview
    Update-OzThemeButtons
}

function New-OzThemeRow {
    # A settings line: title and explanation on the left, the control on the right
    param([string]$Title, [string]$Sub, $Control)
    $row = New-OzRowBorder -Margin '0,0,0,6' -Padding '14,9,14,9'
    $cols = New-OzColumns @('*', 'Auto')
    $left = New-Object System.Windows.Controls.StackPanel
    $left.VerticalAlignment = 'Center'
    [void]$left.Children.Add((New-OzText -Text $Title -Size 13 -Color '#E6F1FF' -Semi))
    if ($Sub) { [void]$left.Children.Add((New-OzText -Text $Sub -Size 11.5 -Color '#5D6E92' -Wrap -Margin '0,2,12,0')) }
    Add-OzGridChild $cols $left 0
    if ($Control) {
        $Control.VerticalAlignment = 'Center'
        $Control.HorizontalAlignment = 'Right'
        Add-OzGridChild $cols $Control 1
    }
    $row.Child = $cols
    $row
}

function New-OzThemeChips {
    # One choice out of a few. Items: @{ Value = ...; Label = '...'; Tip = '...'; Swatch = '#hex' }
    param([string]$Key, [object[]]$Items, [double]$MaxWidth = 0)
    $p = New-Object System.Windows.Controls.WrapPanel
    if ($MaxWidth) { $p.MaxWidth = $MaxWidth }
    $group = 'theme-{0}-{1}' -f $Key, [guid]::NewGuid().ToString('N').Substring(0, 6)
    foreach ($it in $Items) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Style = $Oz.Window.FindResource('Chip')
        $rb.GroupName = $group
        if ($it.Swatch) {
            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = 'Horizontal'
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 12; $dot.Height = 12
            $dot.Fill = Get-OzBrush $it.Swatch
            $dot.Stroke = Get-OzBrush $(if ($it.Edge) { $it.Edge } else { '#5D6E92' })
            $dot.StrokeThickness = 1.5
            $dot.Margin = New-OzThickness '0,0,7,0'
            $dot.VerticalAlignment = 'Center'
            [void]$sp.Children.Add($dot)
            [void]$sp.Children.Add((New-OzText -Text $it.Label -Size 11.5 -Color '#E6F1FF' -Display -Semi))
            $rb.Content = $sp
        } else { $rb.Content = $it.Label }
        if ($it.Tip) { $rb.ToolTip = $it.Tip }
        $rb.Tag = @{ Key = $Key; Value = $it.Value }
        $rb.IsChecked = ([string]$Oz.ThemeCfg[$Key] -eq [string]$it.Value)
        $rb.Add_Checked({ Set-OzThemeValue $this.Tag.Key $this.Tag.Value })
        [void]$p.Children.Add($rb)
    }
    $p
}

function New-OzThemeSwitch {
    param([string]$Key, [switch]$Disabled)
    $c = New-Object System.Windows.Controls.CheckBox
    $c.Style = $Oz.Window.FindResource('Switch')
    $c.IsChecked = [bool]$Oz.ThemeCfg[$Key]
    $c.Tag = $Key
    if ($Disabled) { $c.IsEnabled = $false }
    $c.Add_Checked({ Set-OzThemeValue $this.Tag $true })
    $c.Add_Unchecked({ Set-OzThemeValue $this.Tag $false })
    $c
}

function New-OzThemeStepper {
    # A number with - and + buttons, like the settings panels this page is modeled on
    param([string]$Key, [double]$Step, [double]$Min, [double]$Max, [string]$Format = '0', [string]$Unit = '', [switch]$Disabled)
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $val = New-OzText -Text ((([double]$Oz.ThemeCfg[$Key]).ToString($Format, $Oz.Inv)) + $Unit) -Size 13 -Color '#E6F1FF' -Display -Semi -Margin '0,0,10,0'
    $val.MinWidth = 48
    $val.TextAlignment = 'Right'
    $val.VerticalAlignment = 'Center'
    [void]$sp.Children.Add($val)
    foreach ($d in @(-1, 1)) {
        $b = New-OzButton -Text $(if ($d -lt 0) { [string][char]0x2212 } else { '+' }) -Style 'Neon' -Margin '0,0,6,0'
        $b.Padding = New-OzThickness '11,3'
        $b.Tag = @{ Key = $Key; Delta = $d * $Step; Min = $Min; Max = $Max; Format = $Format; Unit = $Unit; Text = $val }
        $b.Add_Click({
                $t = $this.Tag
                $v = [math]::Round([math]::Min($t.Max, [math]::Max($t.Min, [double]$Oz.ThemeCfg[$t.Key] + $t.Delta)), 2)
                if ($t.Format -eq '0') { $v = [int]$v }
                $t.Text.Text = ([double]$v).ToString($t.Format, $Oz.Inv) + $t.Unit
                Set-OzThemeValue $t.Key $v
            })
        if ($Disabled) { $b.IsEnabled = $false }
        [void]$sp.Children.Add($b)
    }
    if ($Disabled) { $sp.Opacity = 0.45 }
    $sp
}

function New-OzThemeColor {
    # A #RRGGBB box with a live swatch
    param([string]$Key)
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $sw = New-Object System.Windows.Controls.Border
    $sw.Width = 26; $sw.Height = 26
    $sw.CornerRadius = New-Object System.Windows.CornerRadius(6)
    $sw.BorderBrush = Get-OzBrush '#3A4C70'
    $sw.BorderThickness = New-OzThickness '1'
    $sw.Background = Get-OzBrush ([string]$Oz.ThemeCfg[$Key])
    $sw.Margin = New-OzThickness '0,0,8,0'
    [void]$sp.Children.Add($sw)
    $tb = New-Object System.Windows.Controls.TextBox
    $tb.Style = $Oz.Window.FindResource('Input')
    $tb.Padding = New-OzThickness '10,5,10,5'
    $tb.Width = 96
    $tb.MaxLength = 7
    $tb.FontFamily = $Oz.Window.FindResource('Mono')
    $tb.Text = [string]$Oz.ThemeCfg[$Key]
    $tb.Tag = @{ Key = $Key; Swatch = $sw }
    $tb.Add_TextChanged({
            $t = $this.Text.Trim()
            if ($t -notmatch '^#?[0-9A-Fa-f]{6}$') { return }
            if (-not $t.StartsWith('#')) { $t = '#' + $t }
            $t = $t.ToUpperInvariant()
            $this.Tag.Swatch.Background = Get-OzBrush $t
            if ($Oz.ThemeCfg[$this.Tag.Key] -ne $t) { Set-OzThemeValue $this.Tag.Key $t }
        })
    [void]$sp.Children.Add($tb)
    $sp
}

function Get-OzThemeScaleNow {
    # This screen's scaling as a percentage (100, 125, 150...)
    try { return [int][math]::Round([System.Windows.PresentationSource]::FromVisual($Oz.Window).CompositionTarget.TransformToDevice.M11 * 100) } catch { return 100 }
}

function Update-OzThemeStatus {
    $rm = Get-OzRainmeter
    $Oz.Rainmeter = $rm
    $ui = $Oz.UI
    if ($rm.Installed) {
        $state = if ($rm.Running) { T 'running' } else { T 'not running (APPLY THEME starts it)' }
        $ui.ThemeRmText.Text = T 'Rainmeter {0} is installed, {1}. Skins folder: {2}' $rm.Version $state $rm.SkinPath
        $ui.ThemeRmText.Foreground = Get-OzBrush '#2BFF9A'
        $ui.BtnRmGet.Visibility = 'Collapsed'
    } else {
        $ui.ThemeRmText.Text = T 'Rainmeter is not installed. It is free and open source: press GET RAINMETER, install it from the official site, then press CHECK AGAIN. This app never downloads it for you.'
        $ui.ThemeRmText.Foreground = Get-OzBrush '#FFB020'
        $ui.BtnRmGet.Visibility = 'Visible'
    }
    Update-OzThemeButtons
}

function Update-OzThemeButtons {
    $ui = $Oz.UI
    $rm = $Oz.Rainmeter
    $installed = [bool]($rm -and $rm.Installed)
    $hasTheme = $installed -and $rm.SkinPath -and [IO.Directory]::Exists((Join-Path $rm.SkinPath 'OZZYHN'))
    $ui.BtnThemeApply.IsEnabled = $installed
    $ui.BtnThemeRemove.IsEnabled = $hasTheme
    $ui.BtnWallOpen.IsEnabled = $hasTheme -and $rm.Running
    if (-not $installed) { $ui.ThemeStatus.Text = T 'Install Rainmeter to apply a theme. You can set everything up now.' }
    elseif ($Oz.ThemeDirty) { $ui.ThemeStatus.Text = T 'Changes are not on your desktop yet. Press APPLY THEME.' }
    elseif ($hasTheme) { $ui.ThemeStatus.Text = T 'Theme is on your desktop. Right-click the clock for more options.' }
    else { $ui.ThemeStatus.Text = '' }
}

function Show-OzThemeLooks {
    $p = $Oz.UI.ThemeLookPanel
    $p.Children.Clear()
    $items = foreach ($k in $Oz.ThemeLooks.Keys) { @{ Value = $k; Label = (T $Oz.ThemeLooks[$k].Name); Swatch = $Oz.ThemeLooks[$k].Swatch; Edge = $Oz.ThemeLooks[$k].Edge } }
    $p.Children.Add((New-OzThemeChips -Key 'Look' -Items $items)) | Out-Null
}

function Show-OzThemeWidgets {
    $p = $Oz.UI.ThemeWidgetPanel
    $p.Children.Clear()
    [void]$p.Children.Add((New-OzThemeRow (T 'Clock') (T 'The big clock with the greeting, date and wallpaper-aware color.') (New-OzThemeSwitch 'Clock')))
    [void]$p.Children.Add((New-OzThemeRow (T 'Status bar') (T 'Date, time, CPU, RAM, network, volume and battery at the top. The left button opens the wallpaper picker.') (New-OzThemeSwitch 'Bar')))
    [void]$p.Children.Add((New-OzThemeRow (T 'Keep the bar above windows') (T 'Off: the bar lives on the desktop, under your windows.') (New-OzThemeSwitch 'BarOnTop')))
    [void]$p.Children.Add((New-OzThemeRow (T 'Dock') (T 'Your apps in a floating bar at the bottom. Hover to lift, click to open.') (New-OzThemeSwitch 'Dock')))
    [void]$p.Children.Add((New-OzThemeRow (T 'Hide the Rainmeter sample skins') (T 'Unloads the illustro skins Rainmeter shows the first time.') (New-OzThemeSwitch 'HideSamples')))
}

function Show-OzThemeClockPanel {
    $p = $Oz.UI.ThemeClockPanel
    if (-not $p) { return }
    $p.Children.Clear()
    $cfg = $Oz.ThemeCfg
    if (-not $Oz.UI.ThemeTabLook.IsChecked) {
        # ---- GENERAL ----
        $grid = New-Object System.Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 3; $grid.Rows = 3
        $names = 'Top left', 'Top', 'Top right', 'Left', 'Center', 'Right', 'Bottom left', 'Bottom', 'Bottom right'
        $group = 'theme-pos-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
        for ($i = 0; $i -lt 9; $i++) {
            $rb = New-Object System.Windows.Controls.RadioButton
            $rb.Style = $Oz.Window.FindResource('Chip')
            $rb.GroupName = $group
            $rb.Content = [string][char]0x25CF
            $rb.FontSize = 9
            $rb.Margin = New-OzThickness '0,0,4,4'
            $rb.ToolTip = T $names[$i]
            $rb.Tag = @{ Key = 'Pos'; Value = $Oz.ThemePositions[$i] }
            $rb.IsChecked = ($cfg.Pos -eq $Oz.ThemePositions[$i])
            $rb.Add_Checked({ Set-OzThemeValue 'Pos' $this.Tag.Value })
            [void]$grid.Children.Add($rb)
        }
        [void]$p.Children.Add((New-OzThemeRow (T 'Position') (T 'Where the clock sits on the desktop.') $grid))
        [void]$p.Children.Add((New-OzThemeRow (T 'Horizontal margin') (T 'Distance from the left or right edge, in pixels.') (New-OzThemeStepper 'MarginX' 10 0 2000)))
        [void]$p.Children.Add((New-OzThemeRow (T 'Vertical margin') (T 'Distance from the top or bottom edge, in pixels.') (New-OzThemeStepper 'MarginY' 10 0 2000)))
        $sizes = foreach ($v in 75, 100, 125, 150, 175, 200) { @{ Value = $v; Label = "$v%" } }
        [void]$p.Children.Add((New-OzThemeRow (T 'Size') (T 'Everything in the theme grows with this. This screen uses {0}% scaling.' (Get-OzThemeScaleNow)) (New-OzThemeChips -Key 'Scale' -Items $sizes -MaxWidth 260)))
        [void]$p.Children.Add((New-OzThemeRow (T '24-hour format') (T 'Use 24-hour time instead of AM/PM.') (New-OzThemeSwitch 'Hour24')))
        $culture = if ($Oz.Lang -eq 'es') { [Globalization.CultureInfo]::GetCultureInfo('es-ES') } else { [Globalization.CultureInfo]::GetCultureInfo('en-US') }
        $now = Get-Date
        $dates = for ($i = 0; $i -lt $Oz.ThemeDateFormats.Count; $i++) { @{ Value = $i; Label = $now.ToString($Oz.ThemeDateFormats[$i].Net, $culture).Replace('.', '').ToUpperInvariant() } }
        [void]$p.Children.Add((New-OzThemeRow (T 'Date format') (T 'How the date is written.') (New-OzThemeChips -Key 'DateFmt' -Items $dates -MaxWidth 300)))
    } else {
        # ---- APPEARANCE ----
        $styles = @(
            @{ Value = 'Horizon'; Label = 'HORIZON'; Tip = (T 'The day spelled wide, with the date and time under it.') }
            @{ Value = 'Blade'; Label = 'BLADE'; Tip = (T 'A greeting and the short day between two lines.') }
            @{ Value = 'Stack'; Label = 'STACK'; Tip = (T 'Big hours over minutes, day and date below.') }
            @{ Value = 'Pulse'; Label = 'PULSE'; Tip = (T 'Neon time in the theme colors with a seconds line.') }
            @{ Value = 'Minimal'; Label = 'MINIMAL'; Tip = (T 'One quiet line.') })
        [void]$p.Children.Add((New-OzThemeRow (T 'Style') (T 'The look of the clock. Right-click the clock on the desktop to switch styles there too.') (New-OzThemeChips -Key 'Style' -Items $styles -MaxWidth 300)))
        [void]$p.Children.Add((New-OzThemeRow (T 'Automatic text color') (T 'Reads the wallpaper under the clock and picks the most readable of your three colors. Follows wallpaper changes.') (New-OzThemeSwitch 'AutoInk')))
        if ($cfg.AutoInk) {
            $modes = @(@{ Value = 'contrast'; Label = (T 'BEST CONTRAST') }, @{ Value = 'threshold'; Label = (T 'BRIGHTNESS LIMITS') })
            [void]$p.Children.Add((New-OzThemeRow (T 'How to choose') (T 'BEST CONTRAST measures which color reads best. BRIGHTNESS LIMITS uses the two limits below.') (New-OzThemeChips -Key 'InkMode' -Items $modes -MaxWidth 300)))
            [void]$p.Children.Add((New-OzThemeRow (T 'Area read (%)') (T 'Size of the part of the wallpaper read around the clock.') (New-OzThemeStepper 'InkRegion' 5 5 100)))
            $lim = $cfg.InkMode -ne 'threshold'
            [void]$p.Children.Add((New-OzThemeRow (T 'Dark limit') (T 'Below this brightness the light text color is used.') (New-OzThemeStepper 'InkDarkTh' 0.05 0 1 '0.00' -Disabled:$lim)))
            [void]$p.Children.Add((New-OzThemeRow (T 'Light limit') (T 'Above this brightness the dark text color is used.') (New-OzThemeStepper 'InkLightTh' 0.05 0 1 '0.00' -Disabled:$lim)))
        } else {
            $fixed = @(@{ Value = 0; Label = (T 'DARK') }, @{ Value = 1; Label = (T 'MID') }, @{ Value = 2; Label = (T 'LIGHT') })
            [void]$p.Children.Add((New-OzThemeRow (T 'Text color') (T 'The clock always uses this color.') (New-OzThemeChips -Key 'InkFixed' -Items $fixed)))
        }
        [void]$p.Children.Add((New-OzThemeRow (T 'Dark text') (T 'Used on bright wallpapers.') (New-OzThemeColor 'InkDark')))
        [void]$p.Children.Add((New-OzThemeRow (T 'Mid text') (T 'Used on medium wallpapers.') (New-OzThemeColor 'InkMid')))
        [void]$p.Children.Add((New-OzThemeRow (T 'Light text') (T 'Used on dark wallpapers.') (New-OzThemeColor 'InkLight')))
    }
}

function Show-OzThemeWalls {
    $p = $Oz.UI.ThemeWallPanel
    $p.Children.Clear()
    $folders = @($Oz.ThemeCfg.WallFolders)
    if (-not $folders.Count) { [void]$p.Children.Add((New-OzText -Text (T 'No folders yet. Press ADD FOLDER or CREATE OZZYHN WALLPAPERS.') -Size 12 -Wrap -Margin '0,0,0,6')) }
    foreach ($f in $folders) {
        $row = New-OzRowBorder -Margin '0,0,0,6' -Padding '12,6,8,6'
        $cols = New-OzColumns @('Auto', '*', 'Auto')
        Add-OzGridChild $cols (New-OzText -Text ([string][char]0xE8B7) -Size 14 -Color '#00E5FF' -Icon -Margin '0,0,10,0') 0
        $t = New-OzText -Text $f -Size 12 -Color $(if ([IO.Directory]::Exists($f)) { '#E6F1FF' } else { '#5D6E92' }) -Mono
        $t.TextTrimming = 'CharacterEllipsis'
        $t.VerticalAlignment = 'Center'
        $t.ToolTip = $f
        Add-OzGridChild $cols $t 1
        $x = New-OzButton -Text (T 'REMOVE') -Style 'NeonDanger' -Margin '8,0,0,0'
        $x.Padding = New-OzThickness '10,3'
        $x.Tag = $f
        $x.Add_Click({
                $Oz.ThemeCfg.WallFolders = @(@($Oz.ThemeCfg.WallFolders) | Where-Object { $_ -ne $this.Tag })
                Show-OzThemeWalls
                Set-OzThemeValue 'WallFolders' $Oz.ThemeCfg.WallFolders
            })
        Add-OzGridChild $cols $x 2
        $row.Child = $cols
        [void]$p.Children.Add($row)
    }
}

function Show-OzThemeDock {
    $p = $Oz.UI.ThemeDockPanel
    $p.Children.Clear()
    $cat = @(Get-OzDockCatalog)
    $Oz.ThemeDockCatalog = $cat
    $chosen = @($Oz.ThemeCfg.DockApps)
    foreach ($a in $cat) {
        $c = New-Object System.Windows.Controls.CheckBox
        $c.Style = $Oz.Window.FindResource('Tick')
        $c.Content = $a.Name
        $c.Margin = New-OzThickness '0,0,18,8'
        $c.IsChecked = $(if ($chosen.Count) { $chosen -contains $a.Id } else { [bool]$a.Default })
        $c.Tag = $a.Id
        $c.Add_Click({ Update-OzThemeDockChoice })
        [void]$p.Children.Add($c)
    }
    foreach ($d in @($Oz.ThemeCfg.DockCustom)) {
        $c = New-Object System.Windows.Controls.CheckBox
        $c.Style = $Oz.Window.FindResource('Tick')
        $c.Content = [string]$d.Name
        $c.ToolTip = [string]$d.Target
        $c.Margin = New-OzThickness '0,0,18,8'
        $c.IsChecked = $true
        $c.Tag = 'custom|' + [string]$d.Target
        $c.Add_Click({ Update-OzThemeDockChoice })
        [void]$p.Children.Add($c)
    }
}

function Update-OzThemeDockChoice {
    $ids = @(); $custom = @()
    foreach ($c in @($Oz.UI.ThemeDockPanel.Children)) {
        if (-not $c.IsChecked) { continue }
        $tag = [string]$c.Tag
        if ($tag.StartsWith('custom|')) {
            $target = $tag.Substring(7)
            $custom += @($Oz.ThemeCfg.DockCustom | Where-Object { [string]$_.Target -eq $target })
        } else { $ids += $tag }
    }
    $Oz.ThemeCfg.DockCustom = @($custom)
    Set-OzThemeValue 'DockApps' @($ids)
    if (-not $ids.Count -and -not $custom.Count) { $Oz.ThemeCfg.Dock = $false; Show-OzThemeWidgets }
}

function Update-OzThemePreview {
    # A small picture of the desktop with these settings: wallpaper, clock, bar and dock
    $ui = $Oz.UI
    $layer = $ui.ThemePreviewLayer
    if (-not $layer -or -not $Oz.ThemeCfg) { return }
    $cfg = $Oz.ThemeCfg
    $look = $Oz.ThemeLooks[[string]$cfg.Look]
    $box = $ui.ThemePreviewBox
    $pw = if ($box.ActualWidth -gt 40) { $box.ActualWidth - 2 } else { 380 }
    $box.Height = [math]::Round($pw * 9 / 16) + 2

    # wallpaper picture (read once per file change)
    $luma = Get-OzWallLuma $cfg
    $key = '{0}|{1}' -f $luma.File, $(if ($luma.File -and [IO.File]::Exists($luma.File)) { (Get-Item -LiteralPath $luma.File).LastWriteTimeUtc.Ticks } else { 0 })
    if ($Oz.ThemePreviewKey -ne $key) {
        $Oz.ThemePreviewKey = $key
        $ui.ThemePreviewImg.Source = $null
        if ($luma.File) {
            try {
                $bi = New-Object System.Windows.Media.Imaging.BitmapImage
                $bi.BeginInit()
                $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bi.DecodePixelWidth = 720
                $bi.StreamSource = New-Object IO.MemoryStream (, [IO.File]::ReadAllBytes($luma.File))
                $bi.EndInit()
                $bi.Freeze()
                $ui.ThemePreviewImg.Source = $bi
            } catch { }
        }
    }
    $layer.Children.Clear()

    # screen size in real pixels, which is what Rainmeter uses
    $dpi = (Get-OzThemeScaleNow) / 100
    $sw = [math]::Max(800, [System.Windows.SystemParameters]::PrimaryScreenWidth * $dpi)
    $f = $pw / $sw
    $s = [double]$cfg.Scale / 100
    $toHex = { param($rgb) $c = @($rgb -split ',' | ForEach-Object { [int]$_ }); $a = if ($c.Count -ge 4) { $c[3] } else { 255 }; '#{0:X2}{1:X2}{2:X2}{3:X2}' -f $a, $c[0], $c[1], $c[2] }
    $slot = if ($cfg.AutoInk) { $luma.Slot } else { [int]$cfg.InkFixed }
    $inkHex = @($cfg.InkDark, $cfg.InkMid, $cfg.InkLight)[$slot]
    $ink = Get-OzBrush $inkHex

    if ($cfg.Bar) {
        $bar = New-Object System.Windows.Controls.Grid
        $bar.VerticalAlignment = 'Top'
        $bar.Margin = New-OzThickness ('{0},{1},{0},0' -f [math]::Max(2, 12 * $s * $f), [math]::Max(2, 8 * $s * $f))
        $bar.Height = [math]::Max(5, 28 * $s * $f)
        foreach ($spec in @(@('Left', 96), @('Center', 230), @('Right', 540))) {
            $pill = New-Object System.Windows.Controls.Border
            $pill.HorizontalAlignment = $spec[0]
            $pill.Width = $spec[1] * $s * $f
            $pill.CornerRadius = New-Object System.Windows.CornerRadius(14 * $s * $f)
            $pill.Background = Get-OzBrush (& $toHex $look.PillBg)
            $pill.BorderBrush = Get-OzBrush (& $toHex $look.PillLine)
            $pill.BorderThickness = New-OzThickness '0.6'
            [void]$bar.Children.Add($pill)
        }
        [void]$layer.Children.Add($bar)
    }
    if ($cfg.Dock) {
        $n = [math]::Max(1, @(Get-OzDockApps $cfg).Count)
        $dock = New-Object System.Windows.Controls.Border
        $dock.VerticalAlignment = 'Bottom'; $dock.HorizontalAlignment = 'Center'
        $dock.Width = (2 * 12 + $n * 46 + ($n - 1) * 12 + 12 + 1 + 12 + 46) * $s * $f
        $dock.Height = (46 + 24) * $s * $f
        $dock.Margin = New-OzThickness ('0,0,0,{0}' -f (12 * $s * $f))
        $dock.CornerRadius = New-Object System.Windows.CornerRadius(20 * $s * $f)
        $dock.Background = Get-OzBrush (& $toHex $look.PillBg)
        $dock.BorderBrush = Get-OzBrush (& $toHex $look.PillLine)
        $dock.BorderThickness = New-OzThickness '0.6'
        $icons = New-Object System.Windows.Controls.StackPanel
        $icons.Orientation = 'Horizontal'; $icons.HorizontalAlignment = 'Center'; $icons.VerticalAlignment = 'Center'
        for ($i = 0; $i -lt $n + 1; $i++) {
            $ic = New-Object System.Windows.Controls.Border
            $ic.Width = 46 * $s * $f; $ic.Height = 46 * $s * $f
            $ic.Margin = New-OzThickness ('{0},0' -f (6 * $s * $f))
            $ic.CornerRadius = New-Object System.Windows.CornerRadius(10 * $s * $f)
            $ic.Background = Get-OzBrush $(if ($i -lt $n) { '#55' + $look.Edge.TrimStart('#') } else { '#22FFFFFF' })
            [void]$icons.Children.Add($ic)
        }
        $dock.Child = $icons
        [void]$layer.Children.Add($dock)
    }
    if ($cfg.Clock) {
        $i = [array]::IndexOf($Oz.ThemePositions, [string]$cfg.Pos)
        $col = $i % 3; $row = [math]::Floor($i / 3)
        $clock = New-Object System.Windows.Controls.StackPanel
        $clock.HorizontalAlignment = @('Left', 'Center', 'Right')[$col]
        $clock.VerticalAlignment = @('Top', 'Center', 'Bottom')[$row]
        $mx = if ($col -eq 1) { 0 } else { $cfg.MarginX * $f }
        $my = if ($row -eq 1) { 0 } else { $cfg.MarginY * $f }
        $clock.Margin = New-OzThickness ('{0},{1},{0},{1}' -f $mx, $my)
        $align = @('Left', 'Center', 'Right')[$col]
        $culture = if ($Oz.Lang -eq 'es') { [Globalization.CultureInfo]::GetCultureInfo('es-ES') } else { [Globalization.CultureInfo]::GetCultureInfo('en-US') }
        $now = Get-Date
        $time = if ($cfg.Hour24) { $now.ToString('HH:mm') } else { $now.ToString('h:mm tt', $culture) }
        $date = $now.ToString($Oz.ThemeDateFormats[[int]$cfg.DateFmt].Net, $culture).Replace('.', '').ToUpperInvariant()
        $day = $now.ToString('dddd', $culture).ToUpperInvariant()
        $spaced = { param($t, [int]$n) ($t.ToCharArray() | ForEach-Object { [string]$_ }) -join ([string][char]0x200A * $n) }
        $add = {
            param([string]$Text, [double]$Size, [string]$Font, [string]$Weight, $Brush, [double]$Top = 0)
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $Text
            $tb.FontSize = [math]::Max(4, $Size * $s * $f * 1.33)
            $tb.FontFamily = New-Object System.Windows.Media.FontFamily($Font)
            $tb.FontWeight = [System.Windows.FontWeights]::$Weight
            $tb.Foreground = $Brush
            $tb.TextAlignment = $align
            $tb.HorizontalAlignment = $align
            $tb.Margin = New-OzThickness ('0,{0},0,0' -f ($Top * $s * $f))
            [void]$clock.Children.Add($tb)
        }
        $font = 'Bahnschrift, Segoe UI'
        switch ($cfg.Style) {
            'Horizon' { & $add (& $spaced $day 2) 80 $font 'Light' $ink; & $add (& $spaced $date 1) 16 $font 'Normal' $ink 2; & $add ('-  ' + $time + '  -') 16 $font 'Normal' $ink 6 }
            'Blade' {
                & $add ([string][char]0x2502) 40 $font 'Light' $ink
                & $add (T 'GOOD') 12 $font 'Bold' $ink 10; & $add (T 'EVENING') 12 $font 'Bold' $ink
                & $add ($now.ToString('ddd', $culture).Replace('.', '').ToUpperInvariant()) 74 $font 'SemiBold' $ink
                & $add $date 12 $font 'Bold' $ink; & $add $time 12 $font 'Bold' $ink 4
                & $add ([string][char]0x2502) 40 $font 'Light' $ink 10
            }
            'Stack' {
                & $add $(if ($cfg.Hour24) { $now.ToString('HH') } else { $now.ToString('%h') }) 120 $font 'Light' $ink
                $mm = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($inkHex))
                $mm.Opacity = 0.6
                & $add $now.ToString('mm') 120 $font 'Light' $mm -48
                & $add ($day + '  ' + [char]0x00B7 + '  ' + $date) 13 $font 'SemiBold' $ink -10
            }
            'Pulse' {
                $grad = New-Object System.Windows.Media.LinearGradientBrush
                $grad.StartPoint = '0,0'; $grad.EndPoint = '1,0'
                foreach ($stop in @(@($look.Accent, 0.0), @($look.Accent2, 1.0))) {
                    $c = @($stop[0] -split ',' | ForEach-Object { [byte][int]$_ })
                    $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop([System.Windows.Media.Color]::FromRgb($c[0], $c[1], $c[2]), $stop[1])))
                }
                & $add $(if ($cfg.Hour24) { $now.ToString('HH:mm') } else { $now.ToString('h:mm') }) 92 $font 'SemiBold' $grad
                & $add ($day + '  ' + [char]0x00B7 + '  ' + $date) 14 $font 'SemiBold' $ink 4
            }
            default { & $add ($day + '   ' + [char]0x00B7 + '   ' + $date + '   ' + [char]0x00B7 + '   ' + $time) 15 $font 'SemiBold' $ink }
        }
        [void]$layer.Children.Add($clock)
    }
    $names = @((T 'DARK'), (T 'MID'), (T 'LIGHT'))
    if ($cfg.AutoInk) {
        $ui.ThemePreviewNote.Text = T 'Text color: {0}. Wallpaper brightness under the clock: {1}%.' $names[$slot] ([int][math]::Round($luma.Brightness * 100))
    } else { $ui.ThemePreviewNote.Text = T 'Text color: {0} (fixed).' $names[$slot] }
}

function Show-OzThemes {
    # Builds the THEMES page from the saved settings
    if (-not $Oz.ThemeCfg) { $Oz.ThemeCfg = Read-OzThemeSettings }
    $Oz.ThemesShown = $true
    Update-OzThemeStatus
    Show-OzThemeLooks
    Show-OzThemeWidgets
    Show-OzThemeClockPanel
    Show-OzThemeWalls
    Show-OzThemeDock
    Update-OzThemePreview
    Update-OzThemeButtons
}

function Invoke-OzThemeApply {
    $cfg = $Oz.ThemeCfg
    if (-not $Oz.Rainmeter -or -not $Oz.Rainmeter.Installed) { Update-OzThemeStatus; if (-not $Oz.Rainmeter.Installed) { Write-OzLog (T 'Rainmeter is not installed. Press GET RAINMETER, install it, then try again.') 'WARN'; return } }
    $r = @(Invoke-OzJob -Activity (T 'Applying the theme...') -ArgumentList @(, $cfg) -ScriptBlock {
            param($c)
            try { Install-OzTheme $c; [pscustomobject]@{ Ok = $true; Msg = '' } }
            catch { [pscustomobject]@{ Ok = $false; Msg = $_.Exception.Message } }
        }) | Select-Object -Last 1
    $Oz.ThemeDirty = -not ($r -and $r.Ok)
    Update-OzThemeStatus
    if ($r -and -not $r.Ok) {
        Write-OzLog ((T 'Theme failed: {0}') -f $r.Msg) 'WARN'
        [void](Show-OzDialog -Text (T "The theme could not be applied:`n`n{0}" $r.Msg) -Kind Warning)
    }
}

function Invoke-OzThemeRemove {
    $msg = T "Remove the OZZYHN theme?`n`nIts skins are unloaded and the OZZYHN skins folder is deleted. Your wallpaper, your pictures and your other Rainmeter skins stay as they are."
    if ((Show-OzDialog -Text $msg -Buttons YesNo -Kind Question) -ne 'Yes') { return }
    $r = @(Invoke-OzJob -Activity (T 'Removing the theme...') -ScriptBlock {
            try { Remove-OzTheme; [pscustomobject]@{ Ok = $true; Msg = '' } }
            catch { [pscustomobject]@{ Ok = $false; Msg = $_.Exception.Message } }
        }) | Select-Object -Last 1
    if ($r -and -not $r.Ok) { Write-OzLog ((T 'Theme failed: {0}') -f $r.Msg) 'WARN' }
    $Oz.ThemeDirty = $true
    Update-OzThemeStatus
}

function Invoke-OzThemeWallpapers {
    $pics = [Environment]::GetFolderPath('MyPictures')
    $dir = Join-Path $pics 'OZZYHN Wallpapers'
    $made = @(Invoke-OzJob -Activity (T 'Drawing the OZZYHN wallpapers...') -ArgumentList @($dir) -ScriptBlock {
            param($d)
            try { New-OzWallpaperArt -Folder $d | ForEach-Object { [pscustomobject]@{ Path = $_ } } }
            catch { [pscustomobject]@{ Path = ''; Err = $_.Exception.Message } }
        })
    $err = $made | Where-Object { $_.Err } | Select-Object -First 1
    if ($err) { Write-OzLog ((T 'Theme failed: {0}') -f $err.Err) 'WARN'; return }
    if (@($Oz.ThemeCfg.WallFolders) -notcontains $dir) { $Oz.ThemeCfg.WallFolders = @(@($Oz.ThemeCfg.WallFolders) + $dir) }
    Show-OzThemeWalls
    Set-OzThemeValue 'WallFolders' $Oz.ThemeCfg.WallFolders
    Write-OzLog ((T '{0} wallpapers saved in {1}') -f @($made).Count, $dir) 'OK'
    Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList ('"{0}"' -f $dir)
}

function Add-OzThemeFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = T 'Pick a folder with wallpapers (JPG, PNG or BMP).'
    $d.ShowNewFolderButton = $true
    if ($d.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $p = $d.SelectedPath
    if (-not $p -or $p -notmatch '^[A-Za-z]:\\') { return }
    if (@($Oz.ThemeCfg.WallFolders) -notcontains $p) { $Oz.ThemeCfg.WallFolders = @(@($Oz.ThemeCfg.WallFolders) + $p | Select-Object -First 8) }
    Show-OzThemeWalls
    Set-OzThemeValue 'WallFolders' $Oz.ThemeCfg.WallFolders
}

function Add-OzThemeDockApp {
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.Filter = (T 'Programs and shortcuts') + ' (*.exe;*.lnk)|*.exe;*.lnk'
    $d.DereferenceLinks = $false
    if (-not $d.ShowDialog($Oz.Window)) { return }
    $p = $d.FileName
    if (@($Oz.ThemeCfg.DockCustom | Where-Object { $_.Target -eq $p }).Count) { return }
    $Oz.ThemeCfg.DockCustom = @(@($Oz.ThemeCfg.DockCustom) + [pscustomobject]@{ Name = [IO.Path]::GetFileNameWithoutExtension($p); Target = $p } | Select-Object -First 12)
    Show-OzThemeDock
    Set-OzThemeValue 'DockCustom' $Oz.ThemeCfg.DockCustom
}
#endregion

#region ============================ EVENTS ============================
function Initialize-OzEvents {
    $ui = $Oz.UI
    $win = $Oz.Window

    # title bar
    $ui.BtnClose.Add_Click({ $Oz.Window.Close() })
    $ui.BtnMin.Add_Click({ $Oz.Window.WindowState = 'Minimized' })
    $ui.BtnMax.Add_Click({ $Oz.Window.WindowState = $(if ($Oz.Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) })
    $ui.BtnGitHub.Add_Click({ Open-OzLink $Oz.RepoUrl })
    $ui.BtnProfile.Add_Click({ Open-OzLink $Oz.ProfileUrl })
    $ui.LangEn.Add_Checked({ if ($Oz.Lang -ne 'en') { Set-OzLanguage 'en' -Save } })
    $ui.LangEs.Add_Checked({ if ($Oz.Lang -ne 'es') { Set-OzLanguage 'es' -Save } })
    $win.Add_StateChanged({ $Oz.UI.RootBorder.BorderThickness = New-OzThickness $(if ($Oz.Window.WindowState -eq 'Maximized') { '7' } else { '1' }) })
    $win.Add_SizeChanged({ Update-OzCompactLayout })
    $win.Add_PreviewKeyDown({
            $ctrl = ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
            if ($ctrl -and $_.Key -eq [System.Windows.Input.Key]::F) { Invoke-OzSearchShortcut; $_.Handled = $true }
            elseif ($_.Key -eq [System.Windows.Input.Key]::Escape -and $Oz.UI.TweakSearch.IsKeyboardFocusWithin -and $Oz.UI.TweakSearch.Text) {
                $Oz.UI.TweakSearch.Text = ''
                $_.Handled = $true
            }
        })

    # navigation
    foreach ($p in 'Dash', 'Tweaks', 'Profiles', 'Games', 'Themes', 'Debloat', 'Drivers', 'Tools', 'Backup', 'Log') {
        $nav = $ui["Nav$p"]
        $nav.Add_Checked({ Show-OzPage ($this.Name -replace '^Nav', '') })
    }

    # dashboard
    $ui.BtnRescan.Add_Click({ Invoke-OzSafe 'Rescan' { Invoke-OzScan -Rescan } })
    $ui.BtnCopySpecs.Add_Click({
            if ($Oz.Sys) { [System.Windows.Clipboard]::SetText((Get-OzSpecSheet $Oz.Sys)); Write-OzLog (T 'Spec sheet copied to clipboard.') 'OK' }
        })
    $ui.BtnAutoTune.Add_Click({
            Invoke-OzSafe 'Auto-tune' {
                if (-not $Oz.Rows.Count) { return }
                $p = $Oz.Profiles | Where-Object Key -EQ 'auto' | Select-Object -First 1
                $ids = Resolve-OzProfile $p
                $new = @($ids | Where-Object { $Oz.Rows[$_] -and $Oz.Rows[$_].Applicable -and -not $Oz.Rows[$_].Applied }).Count
                if (-not $new) { Write-OzLog (T 'This PC is already fully tuned. Nothing to change.') 'OK'; return }
                $msg = T "AUTO-TUNE found {0} improvement(s) for this {1} ({2}).`n`nApply them now (a restore point is made first), or look at the list first?" $new (T $Oz.Sys.Form).ToLower() (T $Oz.Sys.Score.TierName)
                $r = Show-OzDialog -Text $msg -Buttons YesNoCancel -Kind Question -Labels @((T 'APPLY NOW'), (T 'SHOW ME FIRST'), (T 'CANCEL'))
                if ($r -eq 'Yes') { Invoke-OzProfile 'auto'; Invoke-OzApplyPending }
                elseif ($r -eq 'No') { Invoke-OzProfile 'auto' }
            }
        })

    # tweaks
    $ui.TweakSearch.Add_TextChanged({
            $Oz.UI.TweakSearchHint.Visibility = $(if ($Oz.UI.TweakSearch.Text) { 'Hidden' } else { 'Visible' })
            Update-OzFilter
        })
    $ui.BtnApply.Add_Click({ Invoke-OzSafe 'Apply' { Invoke-OzApplyPending } })
    $ui.BtnClearPending.Add_Click({
            foreach ($row in @($Oz.Rows.Values)) { if ($row.Pending) { $row.Check.IsChecked = $row.Applied; Set-OzRowVisual $row } }
            Update-OzPendingBar; Update-OzFilter
        })
    $ui.BtnSelectRec.Add_Click({
            $n = 0
            foreach ($row in @($Oz.Rows.Values)) {
                if ($row.Rec -and $row.Applicable -and -not $row.Check.IsChecked -and $row.Tweak.Risk -ne 'Danger') { $row.Check.IsChecked = $true; Update-OzRowState $row.Tweak.Id; $n++ }
            }
            Update-OzPendingBar
            Write-OzLog (T '{0} recommended switch(es) staged.' $n) 'OK'
            Select-OzChip 'PENDING'
        })
    $ui.BtnReapply.Add_Click({
            Invoke-OzSafe 'Re-apply' {
                $list = @(Get-OzUndoneRows | ForEach-Object { $_.Tweak })
                if ($list.Count) { Invoke-OzChangeSet -ToApply $list }
            }
        })

    # games
    $ui.BtnScanGames.Add_Click({ Invoke-OzSafe 'Game scan' { $Oz.GamesShown = $true; Show-OzGames (Get-OzGameScan) } })

    # themes
    $ui.BtnRmGet.Add_Click({ Open-OzLink $Oz.RainmeterUrl })
    $ui.BtnRmCheck.Add_Click({ Invoke-OzSafe 'Themes' { Update-OzThemeStatus } })
    $ui.BtnThemeApply.Add_Click({ Invoke-OzSafe 'Themes' { Invoke-OzThemeApply } })
    $ui.BtnThemeRemove.Add_Click({ Invoke-OzSafe 'Themes' { Invoke-OzThemeRemove } })
    $ui.BtnWallMake.Add_Click({ Invoke-OzSafe 'Themes' { Invoke-OzThemeWallpapers } })
    $ui.BtnWallAdd.Add_Click({ Invoke-OzSafe 'Themes' { Add-OzThemeFolder } })
    $ui.BtnWallOpen.Add_Click({
            Invoke-OzSafe 'Themes' {
                $rm = Get-OzRainmeter
                if ($rm.Running -and [IO.Directory]::Exists((Join-Path $rm.SkinPath 'OZZYHN\Walls'))) { Send-OzRainmeterBang $rm '!ActivateConfig' @('OZZYHN\Walls', 'Walls.ini') }
            }
        })
    $ui.BtnDockAdd.Add_Click({ Invoke-OzSafe 'Themes' { Add-OzThemeDockApp } })
    $ui.ThemeTabGeneral.Add_Checked({ if ($Oz.ThemesShown) { Show-OzThemeClockPanel } })
    $ui.ThemeTabLook.Add_Checked({ if ($Oz.ThemesShown) { Show-OzThemeClockPanel } })
    $ui.ThemePreviewBox.Add_SizeChanged({
            if ($Oz.ThemesShown -and [math]::Abs($_.NewSize.Width - $_.PreviousSize.Width) -gt 2) { try { Update-OzThemePreview } catch { } }
        })

    # debloat
    $ui.BtnScanApps.Add_Click({ Invoke-OzSafe 'App scan' { $Oz.BloatChecks = @(); Show-OzBloat (Get-OzInstalledBloat) } })
    $ui.BtnBloatRec.Add_Click({ foreach ($c in @($Oz.BloatChecks)) { $c.IsChecked = [bool]$c.Tag.Rec } })
    $ui.BtnBloatNone.Add_Click({ foreach ($c in @($Oz.BloatChecks)) { $c.IsChecked = $false } })
    $ui.BtnBloatRemove.Add_Click({
            Invoke-OzSafe 'Debloat' {
                $sel = @($Oz.BloatChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
                if (-not $sel.Count) { Write-OzLog (T 'Select at least one app.') 'WARN'; return }
                $msg = T "Remove these {0} app(s) for all users?`n`n{1}`n`nYou can reinstall them from the Microsoft Store." $sel.Count (($sel | ForEach-Object { '  - ' + (T $_.Name) }) -join "`n")
                if ((Show-OzDialog -Text $msg -Buttons YesNo -Kind Warning) -ne 'Yes') { return }
                Remove-OzBloat -Patterns @($sel | ForEach-Object { $_.Pattern })
                $Oz.BloatChecks = @()
                Show-OzBloat (Get-OzInstalledBloat)
            }
        })
    $ui.BtnEdgeUninstall.Add_Click({
            $msg = T "Try Microsoft's official Edge uninstall through winget?`n`nThis only works where Microsoft allows it (European Economic Area). WebView2, which other apps need, stays installed."
            if ((Show-OzDialog -Text $msg -Buttons YesNo -Kind Warning) -eq 'Yes') {
                Start-OzConsole 'Edge uninstall' 'winget uninstall --id Microsoft.Edge -e --accept-source-agreements'
            }
        })

    # drivers
    $ui.BtnScanDrivers.Add_Click({ Invoke-OzSafe 'Driver scan' { $Oz.DriversShown = $true; Show-OzDriverRecs; Show-OzDriverScan (Get-OzDriverScan) } })
    $ui.BtnDevMgr.Add_Click({ Start-Process 'devmgmt.msc' })
    $ui.BtnPnpScan.Add_Click({
            Invoke-OzSafe 'Hardware scan' {
                Invoke-OzJob -Activity (T 'Asking Windows to detect new hardware...') -ScriptBlock { & pnputil.exe /scan-devices | Out-String } | Out-Null
                Write-OzLog (T 'Hardware detection finished.') 'OK'
            }
        })

    # tools
    $ui.BtnCleanScan.Add_Click({ Invoke-OzSafe 'Cleanup scan' { Invoke-OzCleanScan } })
    $ui.BtnCleanRec.Add_Click({ Set-OzCleanChecks -Recommended })
    $ui.BtnCleanNone.Add_Click({ Set-OzCleanChecks })
    $ui.BtnCleanSelected.Add_Click({ Invoke-OzSafe 'Cleanup' { Invoke-OzCleanSelected } })
    $ui.BtnDeepClean.Add_Click({ Start-OzConsole 'Ozzyhn - DISM component cleanup' 'dism /online /cleanup-image /startcomponentcleanup' })
    $ui.BtnCleanMgr.Add_Click({ Start-Process 'cleanmgr.exe' })
    $ui.BtnSfc.Add_Click({ Start-OzConsole 'Ozzyhn - Windows repair' 'dism /online /cleanup-image /restorehealth & sfc /scannow' })
    $ui.BtnChkdsk.Add_Click({ Start-OzConsole 'Ozzyhn - Scan disk' "chkdsk $env:SystemDrive /scan" })
    $ui.BtnNetReset.Add_Click({
            Invoke-OzSafe 'Network reset' {
                if ((Show-OzDialog -Text (T "Reset Winsock, TCP/IP and the DNS cache?`n`nUse this when internet is broken or slow for no reason. A restart is required after.") -Buttons YesNo -Kind Question) -ne 'Yes') { return }
                Invoke-OzJob -Activity (T 'Resetting network stack...') -ScriptBlock {
                    ipconfig /flushdns | Out-Null; T 'DNS cache flushed'
                    netsh winsock reset | Out-Null; T 'Winsock reset'
                    netsh int ip reset | Out-Null; T 'TCP/IP reset'
                } | Out-Null
                Write-OzLog (T 'Network stack reset. Restart the PC to finish.') 'OK'
            }
        })
    $ui.BtnApplyDns.Add_Click({
            Invoke-OzSafe 'DNS' {
                if (-not $Oz.DnsChoice) { Write-OzLog (T 'Pick a DNS option first.') 'WARN'; return }
                Set-OzDns $Oz.DnsChoice
                $Oz.DnsNow = $Oz.DnsChoice
                Initialize-OzTools
            }
        })
    $ui.BtnPlanPerf.Add_Click({ Invoke-OzSafe 'Plan' { Set-OzPlanTweak 'plan-perf' } })
    $ui.BtnPlanSmart.Add_Click({ Invoke-OzSafe 'Plan' { Set-OzPlanTweak 'plan-smart' } })
    $ui.BtnPlanCool.Add_Click({ Invoke-OzSafe 'Plan' { Set-OzPlanTweak 'plan-cool' } })
    $ui.BtnPlanReset.Add_Click({
            Invoke-OzSafe 'Reset plans' {
                if ((Show-OzDialog -Text (T 'Restore the Windows default power plans? Custom plans (including Ozzyhn ones) are removed.') -Buttons YesNo -Kind Warning) -ne 'Yes') { return }
                Invoke-OzPowercfg @('-restoredefaultschemes') | Out-Null
                $j = Read-OzJournal
                foreach ($id in 'plan-perf', 'plan-smart', 'plan-cool') { if ($j.ContainsKey($id)) { $j.Remove($id) } }
                Save-OzJournal
                $Oz.Sys.Power = Get-OzActivePlan
                Update-OzAllRowStates; Update-OzPowerText; Update-OzJournalView
                Write-OzLog (T 'Default power plans restored.') 'OK'
            }
        })
    $ui.BtnBatteryReport.Add_Click({
            if (-not $Oz.Sys.Battery.Present) { Write-OzLog (T 'No battery on this PC.') 'WARN'; return }
            $out = Join-Path $Oz.DataDir 'battery-report.html'
            Invoke-OzPowercfg @('/batteryreport', '/output', $out) | Out-Null
            if (Test-Path $out) { Start-Process $out }
        })
    $ui.BtnCompactOn.Add_Click({ Start-OzConsole 'Ozzyhn - CompactOS ON' 'compact /compactos:always' })
    $ui.BtnCompactOff.Add_Click({ Start-OzConsole 'Ozzyhn - CompactOS OFF' 'compact /compactos:never' })
    $ui.BtnOptimizeDrives.Add_Click({ Start-Process 'dfrgui.exe' })
    $ui.BtnRefreshStartup.Add_Click({ Invoke-OzSafe 'Startup' { Update-OzStartupList } })

    # backup
    $ui.BtnRestorePoint.Add_Click({ Invoke-OzSafe 'Restore point' { [void](New-OzRestorePoint -Force) } })
    $ui.BtnOpenRestore.Add_Click({ Start-Process 'rstrui.exe' })
    $ui.BtnExport.Add_Click({ Invoke-OzSafe 'Export' { Export-OzSetup } })
    $ui.BtnImport.Add_Click({ Invoke-OzSafe 'Import' { Import-OzSetup } })
    $ui.BtnOpenData.Add_Click({ Start-Process $Oz.DataDir })
    $ui.BtnRevertAll.Add_Click({ Invoke-OzSafe 'Revert all' { Invoke-OzRevertAll } })

    # log
    $ui.BtnCopyLog.Add_Click({ [System.Windows.Clipboard]::SetText($Oz.UI.LogBox.Text); Write-OzLog (T 'Log copied.') 'OK' })
    $ui.BtnOpenLogs.Add_Click({ Start-Process $Oz.LogDir })

    # One light timer: shows log lines from background work and the latest live stats
    $Oz.Timer = New-Object System.Windows.Threading.DispatcherTimer
    $Oz.Timer.Interval = [TimeSpan]::FromMilliseconds(1000)
    $Oz.Timer.Add_Tick({
            Show-OzQueuedLog
            $d = $Oz.LiveData
            if ($d -and -not [object]::ReferenceEquals($d, $Oz.LiveShown) -and $Oz.UI.PageDash.Visibility -eq 'Visible') {
                $Oz.LiveShown = $d
                Update-OzLive $d
            }
        })

    $win.Add_ContentRendered({ Invoke-OzSafe 'Startup' { Invoke-OzScan } })
    $win.Add_Closing({
            $Oz.Closing = $true
            if ($Oz.Timer) { $Oz.Timer.Stop() }
            if ($Oz.LiveWorker) { try { [void]$Oz.LiveWorker.PS.BeginStop($null, $null) } catch { } }
            Write-OzLog (T 'Closed.')
        })
}
#endregion

#region ============================ STARTUP ============================
function Invoke-OzScan {
    # Hardware scan and tweak detection run at the same time on background runspaces,
    # while the window builds the tweak list. Nothing here blocks the window.
    param([switch]$Rescan)
    Set-OzBusy $true (T 'Scanning hardware: CPU, GPU, RAM, storage, board, battery...')
    $Oz.NoThermal = $false
    $Oz.EeeCache = $null
    $Oz.NicPropCache = @{}
    [void](Read-OzJournal)
    if (-not $Rescan) {
        Initialize-OzCatalog
        $Oz.TweakIndex = @{}
        foreach ($t in $Oz.Tweaks) { $Oz.TweakIndex[$t.Id] = $t }
        Initialize-OzProfiles
    }
    $slow = @($Oz.Tweaks | Where-Object { $_.Detect })
    $fast = @($Oz.Tweaks | Where-Object { -not $_.Detect })
    $wHw = Start-OzWorker -ScriptBlock {
        $s = Get-OzSystemInfo
        try { $s.StartupCount = @(Get-OzStartupApps | Where-Object Enabled).Count } catch { }
        $s
        $dns = ''
        try { $dns = Get-OzCurrentDns } catch { }
        [pscustomobject]@{ Kind = 'Dns'; Value = $dns }
    }
    $wSlow = Start-OzWorker -ArgumentList @(, $slow) -ScriptBlock { param($list) [void](Get-OzEthernetPowerProps); Get-OzAllStates $list }
    $wFast = Start-OzWorker -ArgumentList @(, $fast) -ScriptBlock { param($list) Get-OzAllStates $list }

    if (-not $Rescan) { Initialize-OzTweakList }

    $hw = Wait-OzWorker $wHw (T 'Scanning hardware...')
    $sys = @($hw | Where-Object { $_.PSObject.Properties['OS'] }) | Select-Object -First 1
    $dnsObj = @($hw | Where-Object { $_.PSObject.Properties['Kind'] -and $_.Kind -eq 'Dns' }) | Select-Object -First 1
    if (-not $sys) { throw (T 'The hardware scan did not return a result.') }
    $Oz.Sys = $sys
    if ($dnsObj) { $Oz.DnsNow = [string]$dnsObj.Value }
    Update-OzDashboard
    $s = $Oz.Sys
    Write-OzLog ((T 'Detected: {0} | {1} {2} | {3} | {4} | {5} GB {6} | {7}') -f (T $s.Form), $s.OS.Family, $s.OS.DisplayVersion, $s.CPU.Name,
        $(if ($s.GPU.Primary) { $s.GPU.Primary.Name } else { T 'no GPU' }), $s.Memory.GB, $s.Memory.Type, $s.Storage.SystemKind) 'OK'
    Write-OzLog ((T 'OZ Score {0}/100 -> {1} (weakest part: {2})') -f $s.Score.Overall, (T $s.Score.TierName), (T $s.Score.Bottleneck)) 'OK'

    Set-OzBusy $true (T 'Reading the real state of every tweak...')
    foreach ($w in $wFast, $wSlow) {
        foreach ($h in (Wait-OzWorker $w (T 'Reading the real state of every tweak...'))) {
            if ($h -is [hashtable]) { foreach ($k in @($h.Keys)) { $Oz.States[$k] = $h[$k] } }
        }
    }
    foreach ($row in @($Oz.Rows.Values)) { Set-OzRowFromState $row }
    Update-OzPendingBar
    Update-OzActiveCount
    Update-OzFilter
    if (-not $Rescan) { Initialize-OzProfileCards } else { Update-OzProfileStats }
    Update-OzJournalView
    if ($Oz.ToolsShown) { Update-OzPowerText }
    Start-OzLive
    $Oz.LiveWanted = ($Oz.UI.PageDash.Visibility -eq 'Visible')
    Set-OzBusy $false
    if ($Oz.UI.PageGames.Visibility -eq 'Visible' -and -not $Oz.GamesShown) { $Oz.GamesShown = $true; Show-OzGames (Get-OzGameScan) }

    $rows = @($Oz.Rows.Values)
    $active = @($rows | Where-Object { $_.Applicable -and $_.Applied }).Count
    $na = @($rows | Where-Object { $_.State -eq 'NA' } | ForEach-Object { T $_.Tweak.Name })
    $undone = @($rows | Where-Object { $_.Applicable -and -not $_.Applied -and $_.Flag } | ForEach-Object { T $_.Tweak.Name })
    if ($na.Count) { Write-OzLog (T 'Not present on this PC, so skipped and not counted: {0}' ($na -join ', ')) 'INFO' }
    $legacy = @($rows | Where-Object { $_.Legacy }).Count
    if ($legacy) { Write-OzLog (T 'This update fixes a v1.0 bug: {0} tweak(s) you applied before were never really written. Press RE-APPLY in TWEAKS to apply them properly.' $legacy) 'WARN' }
    elseif ($undone.Count) { Write-OzLog (T 'Applied before but OFF now (see NEEDS ATTENTION in TWEAKS): {0}' ($undone -join ', ')) 'WARN' }
    Write-OzLog (T 'Ready. {0} tweaks loaded, {1} already active on this PC.' $Oz.Tweaks.Count $active) 'OK'
}

function Initialize-OzWindow {
    # Builds the main window and wires every control. Used by Start-Ozzyhn and by the CI UI test,
    # so the test opens exactly the window users get.
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $Oz.Window = [Windows.Markup.XamlReader]::Parse($Oz.Xaml)
    foreach ($m in [regex]::Matches($Oz.Xaml, 'x:Name="(\w+)"')) {
        $n = $m.Groups[1].Value
        $el = $Oz.Window.FindName($n)
        if ($el) { $Oz.UI[$n] = $el }
    }
    $Oz.UI.VersionText.Text = 'v' + $Oz.Version
    $Oz.UI.FooterText.Text = '{0}  |  PowerShell {1}' -f $env:COMPUTERNAME, $PSVersionTable.PSVersion
    Set-OzWindowFit
    Set-OzWindowIcon
    Register-OzXamlTexts
    Set-OzLanguage $Oz.Lang
    Initialize-OzEvents
    $Oz.Timer.Start()
}

function Set-OzWindowFit {
    # Cheap laptops are often 1366x768 at 125% scaling, which leaves about 1093x580 to work with.
    # Fit the window to the screen instead of opening it with the bottom cut off.
    $w = $Oz.Window
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        $maxW = [math]::Max(800, $wa.Width - 16)
        $maxH = [math]::Max(500, $wa.Height - 16)
        if ($w.MinWidth -gt $maxW) { $w.MinWidth = $maxW }
        if ($w.MinHeight -gt $maxH) { $w.MinHeight = $maxH }
        if ($w.Width -gt $maxW) { $w.Width = $maxW }
        if ($w.Height -gt $maxH) { $w.Height = $maxH }
    } catch { }
}

function Update-OzCompactLayout {
    # On short screens the two cards at the bottom of the menu are hidden so every page button fits
    $h = $Oz.Window.ActualHeight
    if ($h -le 0) { return }
    $v = if ($h -lt 760) { 'Collapsed' } else { 'Visible' }
    foreach ($n in 'NavProfileCard', 'NavActiveCard') {
        if ($Oz.UI[$n] -and $Oz.UI[$n].Visibility -ne $v) { $Oz.UI[$n].Visibility = $v }
    }
    # Slightly shorter menu buttons on short screens, so all ten fit
    $nh = if ($h -lt 760) { 38 } else { 42 }
    foreach ($n in 'Dash', 'Tweaks', 'Profiles', 'Games', 'Themes', 'Debloat', 'Drivers', 'Tools', 'Backup', 'Log') {
        $b = $Oz.UI["Nav$n"]
        if ($b -and $b.Height -ne $nh) { $b.Height = $nh }
    }
}

function Set-OzConsoleWindow {
    # Minimizes or restores the PowerShell console behind the app. Does nothing where Windows
    # does not allow it (some terminal hosts).
    param([ValidateSet('Minimize', 'Restore')][string]$State)
    try {
        if (-not ('OzNative.ConsoleWindow' -as [type])) {
            Add-Type -Namespace OzNative -Name ConsoleWindow -ErrorAction Stop -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
        }
        $h = [OzNative.ConsoleWindow]::GetConsoleWindow()
        if ($h -ne [IntPtr]::Zero) { [void][OzNative.ConsoleWindow]::ShowWindow($h, $(if ($State -eq 'Minimize') { 6 } else { 9 })) }
    } catch { }
}

function Start-Ozzyhn {
    if ($env:OS -ne 'Windows_NT') {
        Write-Host 'Optimizaciones de Ozzyhn runs on Windows 10 / 11 only.' -ForegroundColor Red
        return
    }

    $isAdmin = Test-OzAdmin
    # 32-bit PowerShell on 64-bit Windows would write registry tweaks to the wrong (WOW6432Node) place
    $wow = [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess
    $wrongHost = ($PSVersionTable.PSVersion.Major -gt 5) -or ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') -or $wow
    if (-not $isAdmin -or $wrongHost) {
        $sysDir = if ($wow) { 'Sysnative' } else { 'System32' }
        $ps = Join-Path $env:SystemRoot "$sysDir\WindowsPowerShell\v1.0\powershell.exe"
        $self = $PSCommandPath
        if ($self -and (Test-Path -LiteralPath $self)) {
            $argLine = '-NoProfile -ExecutionPolicy Bypass -STA -File "{0}"' -f $self
        } else {
            $cmd = "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; irm '{0}' | iex" -f $Oz.ScriptUrl
            $argLine = '-NoProfile -ExecutionPolicy Bypass -STA -Command "{0}"' -f $cmd
        }
        Write-Host 'Relaunching as Administrator in Windows PowerShell... / Reiniciando como administrador...' -ForegroundColor Cyan
        try {
            if ($isAdmin) { Start-Process -FilePath $ps -ArgumentList $argLine }
            else { Start-Process -FilePath $ps -ArgumentList $argLine -Verb RunAs }
        } catch {
            Write-Host 'Administrator rights are required. Open PowerShell with "Run as administrator" and try again.' -ForegroundColor Red
            Write-Host 'Se necesitan permisos de administrador. Abre PowerShell con "Ejecutar como administrador" e intentalo de nuevo.' -ForegroundColor Red
        }
        return
    }

    # Nothing in the data folder is read or written until it is locked to administrators
    if (-not (Protect-OzDataDir)) {
        [void](Read-Host 'Press Enter to close / Presiona Enter para cerrar')
        return
    }

    Initialize-OzSpanish $Oz.SpanishPairs
    $settings = Read-OzSettings
    $Oz.Lang = if ($settings.Lang -in 'en', 'es') { [string]$settings.Lang } else { Get-OzDefaultLanguage }

    $Host.UI.RawUI.WindowTitle = "$($Oz.AppName) v$($Oz.Version) | $($Oz.Brand) - keep this window open"
    Write-Host ''
    Write-Host '  ====================================================' -ForegroundColor DarkCyan
    Write-Host '     O P T I M I Z A C I O N E S   D E   ' -ForegroundColor Cyan -NoNewline
    Write-Host 'O Z Z Y H N' -ForegroundColor Magenta
    Write-Host '  ====================================================' -ForegroundColor DarkCyan
    Write-Host "  v$($Oz.Version)  |  by $($Oz.Brand)  |  $($Oz.ProfileUrl)" -ForegroundColor White
    Write-Host '  Loading the interface... (this console shows the log)' -ForegroundColor DarkGray
    Write-Host '  Cargando la interfaz... (esta consola muestra el registro)' -ForegroundColor DarkGray
    Write-Host ''

    try {
        Initialize-OzWindow
        Write-OzLog ('{0} v{1} ({2}) started. Data folder: {3}' -f $Oz.AppName, $Oz.Version, $Oz.Brand, $Oz.DataDir) 'STEP'
        Write-OzDataDirNote
        # The console stays open behind the app (closing it closes the app), so tuck it away
        $Oz.Window.Add_Loaded({ Set-OzConsoleWindow 'Minimize' })
        [void]$Oz.Window.ShowDialog()
        $Oz.Closing = $true
        Set-OzConsoleWindow 'Restore'
        if ($Oz.Pool) { try { $Oz.Pool.Close() } catch { } }
    } catch {
        Set-OzConsoleWindow 'Restore'
        Write-Host ''
        Write-Host ('Startup error: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        try { Write-OzLog ('Startup error: {0}' -f $_.Exception.Message) 'ERR' } catch { }
        Write-Host 'Please report this on GitHub (github.com/ozzyhntweaks) with the text above.' -ForegroundColor Yellow
        [void](Read-Host 'Press Enter to close')
    }
}
#endregion


# ---- launch ----
Start-Ozzyhn
