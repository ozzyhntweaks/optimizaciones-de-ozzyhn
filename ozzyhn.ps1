<#
    ===================================================================
     OPTIMIZACIONES DE OZZYHN  //  OZZYHN TWEAKS
     Hardware-aware optimizer for Windows 10 / 11
    ===================================================================
     Launch from an Administrator PowerShell:

         irm https://raw.githubusercontent.com/ozzyhntweaks/optimizaciones-de-ozzyhn/main/ozzyhn.ps1 | iex

     What it does
       - Scans the PC (CPU, GPU, RAM, storage, board, battery, temps)
       - Detects Desktop / Laptop / VM, Windows 10 / 11, and the PC tier
         (CHEAP, BUDGET, MID-RANGE, FANCY)
       - 129 reversible tweaks. Each one detects its current state, so the
         switches show what is really ON in Windows right now.
       - One-click profiles, debloat, driver recommendations, cleanup,
         repair tools, startup manager, restore points and a full undo log.
       - English / Espanol interface.

     Made by OZZYHN TWEAKS - https://github.com/ozzyhntweaks
     License: MIT
#>

#region ============================ STATE ============================
$Oz = [hashtable]::Synchronized(@{})
$Oz.Version   = '1.1.0'
$Oz.AppName   = 'Optimizaciones de Ozzyhn'
$Oz.Brand     = 'OZZYHN TWEAKS'
$Oz.RepoOwner = 'ozzyhntweaks'
$Oz.RepoName  = 'optimizaciones-de-ozzyhn'
$Oz.Branch    = 'main'
$Oz.ScriptUrl = 'https://raw.githubusercontent.com/{0}/{1}/{2}/ozzyhn.ps1' -f $Oz.RepoOwner, $Oz.RepoName, $Oz.Branch
$Oz.RepoUrl   = 'https://github.com/{0}/{1}' -f $Oz.RepoOwner, $Oz.RepoName
$Oz.ProfileUrl = 'https://github.com/{0}' -f $Oz.RepoOwner
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
        foreach ($r in $T.Reg) {
            if ($r.OnlyIfExists -and -not (Test-Path -LiteralPath $r.P)) { continue }
            if ($r.Soft) { continue }   # applied, but Windows keeps re-writing it: not used to decide ON/OFF
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

function Invoke-OzTweakApply {
    param($T)
    foreach ($r in $T.Reg) {
        if ($r.OnlyIfExists -and -not (Test-Path -LiteralPath $r.P)) { continue }
        Save-OzOriginalReg $T.Id $r.P $r.N
        if ($r.Remove) { Remove-OzReg $r.P $r.N } else { Set-OzReg $r.P $r.N $r.V $r.T }
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
    foreach ($r in $T.Reg) {
        if ($r.OnlyIfExists -and -not (Test-Path -LiteralPath $r.P)) { continue }
        $k = "$($r.P)|$($r.N)"
        $done[$k] = $true
        if ($e -and $e.Reg.ContainsKey($k)) { Restore-OzOriginal $r.P $r.N $e.Reg[$k] $r.T }
        elseif ($null -eq $r.D) { Remove-OzReg $r.P $r.N }
        else { Set-OzReg $r.P $r.N $r.D $r.T }
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
        & $add (New-OzInsight warn (T 'Drive {0} is almost full ({1} GB free)' $env:SystemDrive $Sys.Storage.FreeGB) (T 'Low free space slows Windows and updates. Run QUICK CLEAN in TOOLS.') 'Tools')
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
                    'search-highlights-off', 'start-suggest-off', 'tips-off', 'store-autoupdate-off', 'do-p2p-off', 'ntfs-lastaccess-off') + @(Get-OzPlanFor 'cool')
            }
        }
        [pscustomobject]@{
            Key = 'competitive'; Name = 'COMPETITIVE GAMING'; Icon = [char]0xE7FC; Color = '#8A5CFF'; Featured = $false
            Sub = 'Lowest input lag and ping'
            Desc = 'MAX PERFORMANCE plus raw mouse input, no sticky-key pop-ups, TCP no-delay, network card never sleeps, Ethernet power saving off and flip-model for windowed games.'
            Resolve = {
                $Oz.Core + @('priority-sep', 'fth-off', 'mmcss-games', 'game-mode-on', 'gamedvr-off', 'gamebar-tips-off', 'hags-on',
                    'power-throttle-off', 'net-throttle-off', 'nagle-off', 'nic-power-off', 'eee-off', 'mouse-accel-off', 'sticky-keys-off',
                    'windowed-opt-on', 'notif-suggest-off', 'background-apps-off', 'edge-boost-off', 'widgets-off', 'wu-no-autoreboot', 'do-p2p-off') + @(Get-OzPlanFor 'max')
            }
        }
        [pscustomobject]@{
            Key = 'privacy'; Name = 'PRIVACY MAX'; Icon = [char]0xE72E; Color = '#FFB020'; Featured = $false
            Sub = 'Minimum data leaves this PC'
            Desc = 'All privacy, telemetry and AI switches, no cloud search, app permissions locked down, no sync, no ads anywhere. Camera and microphone are left for you to decide.'
            Resolve = {
                @($Oz.Tweaks | Where-Object { $_.Cat -in 'Privacy', 'AI' } | ForEach-Object Id) +
                @('web-search-off', 'cortana-off', 'cloud-search-off', 'search-highlights-off', 'edge-telemetry-off', 'edge-nags-off',
                    'do-p2p-off', 'llmnr-off', 'lockscreen-ads-off', 'start-suggest-off', 'tips-off', 'no-recent-files', 'svc-geo')
            }
        }
        [pscustomobject]@{
            Key = 'clean'; Name = 'CLEAN WINDOWS UI'; Icon = [char]0xE771; Color = '#4FD8FF'; Featured = $false
            Sub = 'Declutter Start, taskbar and Explorer'
            Desc = 'Classic right-click menu, no widgets or chat icon, clean Start, no tips or ads, End Task on the taskbar, file extensions visible.'
            Resolve = { $Oz.Clean + @('classic-context', 'end-task', 'alt-tab-windows', 'shortcut-suffix-off', 'copilot-off', 'edge-nags-off') }
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
function Invoke-OzQuickClean {
    $res = Invoke-OzJob -Activity (T 'Cleaning temporary files...') -ScriptBlock {
        function Get-Size($p) {
            try { [int64](Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { 0 }
        }
        function Clear-Folder($p, $filter = '*') {
            if (-not (Test-Path -LiteralPath $p)) { return 0 }
            $before = Get-Size $p
            Get-ChildItem -LiteralPath $p -Force -Filter $filter -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            [math]::Max(0, $before - (Get-Size $p))
        }
        $total = [int64]0
        $targets = @(
            @("$env:TEMP", 'Your temp folder'),
            @("$env:SystemRoot\Temp", 'Windows temp'),
            @("$env:LOCALAPPDATA\CrashDumps", 'Crash dumps'),
            @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive", 'Error reports (archive)'),
            @("$env:ProgramData\Microsoft\Windows\WER\ReportQueue", 'Error reports (queue)'),
            @("$env:LOCALAPPDATA\Microsoft\Windows\INetCache", 'Legacy web cache'),
            @("$env:SystemRoot\Logs\CBS", 'Servicing logs')
        )
        foreach ($t in $targets) {
            $freed = Clear-Folder $t[0]
            $total += $freed
            '  {0}: {1:N0} MB' -f (T $t[1]), ($freed / 1MB)
        }
        $thumb = Clear-Folder "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" 'thumbcache_*.db'
        $total += $thumb
        '  {0}: {1:N0} MB' -f (T 'Thumbnail cache'), ($thumb / 1MB)
        T 'Stopping Windows Update to clear its download cache...'
        Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
        $wu = Clear-Folder "$env:SystemRoot\SoftwareDistribution\Download"
        Start-Service -Name wuauserv, bits -ErrorAction SilentlyContinue
        $total += $wu
        '  {0}: {1:N0} MB' -f (T 'Windows Update downloads'), ($wu / 1MB)
        try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; '  ' + (T 'Delivery Optimization cache cleared') } catch { }
        try { Clear-RecycleBin -Force -ErrorAction Stop; '  ' + (T 'Recycle Bin emptied') } catch { }
        [pscustomobject]@{ FreedMB = [math]::Round($total / 1MB) }
    }
    $r = @($res) | Select-Object -First 1
    if ($r) { Write-OzLog ((T 'Quick clean finished: {0:N0} MB freed.') -f $r.FreedMB) 'OK' }
    if ($r) { $Oz.LastCleanMB = $r.FreedMB }
    Update-OzCleanText
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
    $ok = [System.Windows.MessageBox]::Show((T "Revert all {0} change(s) made by {1}?`n`nRemoved apps are not reinstalled (get them from the Microsoft Store)." $ids.Count $Oz.AppName), $Oz.AppName, 'YesNo', 'Warning')
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

Low free space slows Windows and updates. Run QUICK CLEAN in TOOLS.
Poco espacio libre vuelve lentos a Windows y a las actualizaciones. Usa LIMPIEZA R&Aacute;PIDA en HERRAMIENTAS.

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

Recycle Bin emptied
Papelera vaciada

Quick clean finished: {0:N0} MB freed.
Limpieza r&aacute;pida terminada: {0:N0} MB liberados.

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

Classic right-click menu, no widgets or chat icon, clean Start, no tips or ads, End Task on the taskbar, file extensions visible.
Men&uacute; contextual cl&aacute;sico, sin widgets ni &iacute;cono de chat, Inicio limpio, sin consejos ni anuncios, Finalizar tarea en la barra y extensiones de archivo visibles.

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

Temp files, crash dumps, error reports, thumbnail cache, Windows Update downloads, Delivery Optimization cache and the Recycle Bin.
Archivos temporales, volcados de errores, informes de errores, cach&eacute; de miniaturas, descargas de Windows Update, cach&eacute; de Optimizaci&oacute;n de distribuci&oacute;n y la Papelera.

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

'@
#endregion

#region ============================ XAML ============================
$Oz.Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Optimizaciones de Ozzyhn | OZZYHN TWEAKS" Width="1320" Height="840" MinWidth="1080" MinHeight="660"
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
            <Setter Property="Foreground" Value="#8A9BBF"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,2"/>
            <Setter Property="GroupName" Value="nav"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="9" Height="42" Padding="14,0">
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
                        <StackPanel Orientation="Horizontal" Background="Transparent">
                            <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" BorderThickness="1" BorderBrush="#3A4C70" Background="#0E1729" VerticalAlignment="Center">
                                <TextBlock x:Name="Mark" Text="&#xE73E;" FontFamily="{StaticResource Icons}" FontSize="11" Foreground="#04060C" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Hidden"/>
                            </Border>
                            <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
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
                            <TextBlock x:Name="VersionText" Text="v1.1.0" FontSize="10.5" Foreground="#B79BFF" FontFamily="{StaticResource Mono}"/>
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
                            <StackPanel>
                                <TextBlock Text="CONTROL DECK" Style="{StaticResource Label}" Margin="14,0,0,8"/>
                                <RadioButton x:Name="NavDash" Style="{StaticResource Nav}" Tag="&#xE9D9;" Content="Dashboard" IsChecked="True"/>
                                <RadioButton x:Name="NavTweaks" Style="{StaticResource Nav}" Tag="&#xE945;" Content="Tweaks"/>
                                <RadioButton x:Name="NavProfiles" Style="{StaticResource Nav}" Tag="&#xE734;" Content="Profiles"/>
                                <RadioButton x:Name="NavDebloat" Style="{StaticResource Nav}" Tag="&#xE74D;" Content="Debloat"/>
                                <RadioButton x:Name="NavDrivers" Style="{StaticResource Nav}" Tag="&#xE896;" Content="Drivers"/>
                                <RadioButton x:Name="NavTools" Style="{StaticResource Nav}" Tag="&#xE90F;" Content="Tools"/>
                                <RadioButton x:Name="NavBackup" Style="{StaticResource Nav}" Tag="&#xE777;" Content="Backup &amp; Undo"/>
                                <RadioButton x:Name="NavLog" Style="{StaticResource Nav}" Tag="&#xE8A5;" Content="Log"/>
                            </StackPanel>
                            <StackPanel Grid.Row="1">
                                <Border CornerRadius="10" Padding="12,10" Background="#0C1222" BorderBrush="#2A00E5FF" BorderThickness="1" Margin="0,0,0,10">
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
                                <Border CornerRadius="10" Padding="14,12" Background="#0C1222" BorderBrush="#1B2A48" BorderThickness="1" Margin="0,0,0,10">
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
                                            <TextBlock x:Name="TierSub" Text="" FontFamily="{StaticResource Display}" FontSize="14" Foreground="#E6F1FF" Margin="0,4,0,0"/>
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
                                    <TextBlock x:Name="TweakSearchHint" Text="Search tweaks..." Foreground="#5D6E92" Margin="35,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
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
                                            <TextBlock Text="Create a System Restore point before applying" Foreground="#8A9BBF" FontSize="12"/>
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
                                <UniformGrid Columns="2">
                                    <Border Style="{StaticResource Card}">
                                        <StackPanel>
                                            <TextBlock Text="CLEANUP" Style="{StaticResource H2}"/>
                                            <TextBlock Style="{StaticResource Body}" Margin="0,4,0,12" Text="Temp files, crash dumps, error reports, thumbnail cache, Windows Update downloads, Delivery Optimization cache and the Recycle Bin."/>
                                            <WrapPanel>
                                                <Button x:Name="BtnQuickClean" Style="{StaticResource Neon}" Content="QUICK CLEAN" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnDeepClean" Style="{StaticResource NeonViolet}" Content="DEEP CLEAN (DISM)" Margin="0,0,8,8"/>
                                                <Button x:Name="BtnCleanMgr" Style="{StaticResource Neon}" Content="DISK CLEANUP" Margin="0,0,8,8"/>
                                            </WrapPanel>
                                            <TextBlock x:Name="CleanResult" Text="" Foreground="#2BFF9A" FontSize="12"/>
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
    foreach ($p in 'Dash', 'Tweaks', 'Profiles', 'Debloat', 'Drivers', 'Tools', 'Backup', 'Log') {
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
    $ui.TweakSearchHint.Text = T 'Search tweaks...'
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
        if ([System.Windows.MessageBox]::Show($msg, $Oz.AppName, 'YesNo', 'Warning') -ne 'Yes') { Write-OzLog (T 'Cancelled.') 'WARN'; return }
    }
    if ($ToApply.Count -and $Oz.UI.ChkRestorePoint.IsChecked) { [void](New-OzRestorePoint) }

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
    if ($reboot) {
        $r = [System.Windows.MessageBox]::Show((T "Some changes take effect after a restart.`n`nRestart now?"), $Oz.AppName, 'YesNo', 'Information')
        if ($r -eq 'Yes') { Restart-Computer -Force }
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
    if ([System.Windows.MessageBox]::Show($msg, $Oz.AppName, 'YesNo', 'Question') -eq 'Yes') { Invoke-OzApplyPending }
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

function Update-OzCleanText {
    if (-not $Oz.UI.CleanResult) { return }
    $Oz.UI.CleanResult.Text = if ($null -ne $Oz.LastCleanMB) { T 'Last clean freed {0:N0} MB' $Oz.LastCleanMB } else { '' }
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

    # navigation
    foreach ($p in 'Dash', 'Tweaks', 'Profiles', 'Debloat', 'Drivers', 'Tools', 'Backup', 'Log') {
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
                $msg = T "AUTO-TUNE found {0} improvement(s) for this {1} ({2}).`n`nYES  = apply them now (restore point first)`nNO   = show me the list first`nCANCEL = do nothing" $new (T $Oz.Sys.Form).ToLower() (T $Oz.Sys.Score.TierName)
                $r = [System.Windows.MessageBox]::Show($msg, $Oz.AppName, 'YesNoCancel', 'Question')
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

    # debloat
    $ui.BtnScanApps.Add_Click({ Invoke-OzSafe 'App scan' { $Oz.BloatChecks = @(); Show-OzBloat (Get-OzInstalledBloat) } })
    $ui.BtnBloatRec.Add_Click({ foreach ($c in @($Oz.BloatChecks)) { $c.IsChecked = [bool]$c.Tag.Rec } })
    $ui.BtnBloatNone.Add_Click({ foreach ($c in @($Oz.BloatChecks)) { $c.IsChecked = $false } })
    $ui.BtnBloatRemove.Add_Click({
            Invoke-OzSafe 'Debloat' {
                $sel = @($Oz.BloatChecks | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
                if (-not $sel.Count) { Write-OzLog (T 'Select at least one app.') 'WARN'; return }
                $msg = T "Remove these {0} app(s) for all users?`n`n{1}`n`nYou can reinstall them from the Microsoft Store." $sel.Count (($sel | ForEach-Object { '  - ' + (T $_.Name) }) -join "`n")
                if ([System.Windows.MessageBox]::Show($msg, $Oz.AppName, 'YesNo', 'Warning') -ne 'Yes') { return }
                Remove-OzBloat -Patterns @($sel | ForEach-Object { $_.Pattern })
                $Oz.BloatChecks = @()
                Show-OzBloat (Get-OzInstalledBloat)
            }
        })
    $ui.BtnEdgeUninstall.Add_Click({
            $msg = T "Try Microsoft's official Edge uninstall through winget?`n`nThis only works where Microsoft allows it (European Economic Area). WebView2, which other apps need, stays installed."
            if ([System.Windows.MessageBox]::Show($msg, $Oz.AppName, 'YesNo', 'Warning') -eq 'Yes') {
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
    $ui.BtnQuickClean.Add_Click({ Invoke-OzSafe 'Quick clean' { Invoke-OzQuickClean } })
    $ui.BtnDeepClean.Add_Click({ Start-OzConsole 'Ozzyhn - DISM component cleanup' 'dism /online /cleanup-image /startcomponentcleanup' })
    $ui.BtnCleanMgr.Add_Click({ Start-Process 'cleanmgr.exe' })
    $ui.BtnSfc.Add_Click({ Start-OzConsole 'Ozzyhn - Windows repair' 'dism /online /cleanup-image /restorehealth & sfc /scannow' })
    $ui.BtnChkdsk.Add_Click({ Start-OzConsole 'Ozzyhn - Scan disk' "chkdsk $env:SystemDrive /scan" })
    $ui.BtnNetReset.Add_Click({
            Invoke-OzSafe 'Network reset' {
                if ([System.Windows.MessageBox]::Show((T "Reset Winsock, TCP/IP and the DNS cache?`n`nUse this when internet is broken or slow for no reason. A restart is required after."), $Oz.AppName, 'YesNo', 'Question') -ne 'Yes') { return }
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
                if ([System.Windows.MessageBox]::Show((T 'Restore the Windows default power plans? Custom plans (including Ozzyhn ones) are removed.'), $Oz.AppName, 'YesNo', 'Warning') -ne 'Yes') { return }
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
        Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
        $Oz.Window = [Windows.Markup.XamlReader]::Parse($Oz.Xaml)
        foreach ($m in [regex]::Matches($Oz.Xaml, 'x:Name="(\w+)"')) {
            $n = $m.Groups[1].Value
            $el = $Oz.Window.FindName($n)
            if ($el) { $Oz.UI[$n] = $el }
        }
        $Oz.UI.VersionText.Text = 'v' + $Oz.Version
        $Oz.UI.FooterText.Text = '{0}  |  PowerShell {1}' -f $env:COMPUTERNAME, $PSVersionTable.PSVersion
        Set-OzWindowIcon
        Register-OzXamlTexts
        Set-OzLanguage $Oz.Lang
        Write-OzLog ('{0} v{1} ({2}) started. Data folder: {3}' -f $Oz.AppName, $Oz.Version, $Oz.Brand, $Oz.DataDir) 'STEP'
        Initialize-OzEvents
        $Oz.Timer.Start()
        [void]$Oz.Window.ShowDialog()
        $Oz.Closing = $true
        if ($Oz.Pool) { try { $Oz.Pool.Close() } catch { } }
    } catch {
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
