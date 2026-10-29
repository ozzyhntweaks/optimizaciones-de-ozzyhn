<#
    Opens the real app window on Windows (GitHub's Windows runner) and uses it like a person would:
      - waits for the hardware scan and tweak detection
      - opens every page, at normal size and at the size of a cheap 1366x768 laptop at 125% scaling
      - switches to Spanish and back, presses Ctrl+F, opens the dialogs and the results card
      - scans for files to clean on the TOOLS page and ticks items (nothing is deleted: the
        confirmation is answered NO)
      - shows the Games page with a test game whose settings file is known
    Fails on any error the app logs, any unhandled UI exception, or a menu that does not fit.
    With -Shots, saves a PNG of every step to that folder.
    With -Weak, plays a weak PC: the app gets one CPU core (the test machine has no graphics card
    either), only the speed part runs, and the speed budgets are for that kind of PC.
#>
param([string]$Path = 'ozzyhn.ps1', [string]$Shots = '', [switch]$Weak)
$ErrorActionPreference = 'Stop'
trap { Write-Host ('::error::UI test stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

$text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
$cut = $text.LastIndexOf('# ---- launch ----')
if ($cut -lt 0) { throw 'The "# ---- launch ----" marker was not found in the script' }
. ([scriptblock]::Create($text.Substring(0, $cut)))

$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$work = Join-Path $base ('oz-ui-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$Oz.DataDir = $work
$Oz.Journal = Join-Path $work 'journal.json'
$Oz.Settings = Join-Path $work 'settings.json'
$Oz.LogDir = Join-Path $work 'logs'
$Oz.LogFile = Join-Path $Oz.LogDir 'ui-test.log'
$Oz.JournalData = $null
if ($Shots) { New-Item -ItemType Directory -Path $Shots -Force | Out-Null }

$script:Problems = New-Object System.Collections.Generic.List[string]
function Fail([string]$Msg) { $script:Problems.Add($Msg); Write-Host "::error::$Msg" }
function Pass([string]$Msg) { Write-Host "PASS  $Msg" -ForegroundColor Green }

# Watchdog: a second PowerShell that, if this test is still running after a while, says what it was
# doing, which windows are open (a stuck dialog) and which threads use the CPU, saves a picture of
# the screen, then stops it. A hang becomes a failure that explains itself.
$script:PhaseFile = Join-Path $work 'phase.txt'
function Set-Phase([string]$Text) { try { [IO.File]::WriteAllText($script:PhaseFile, $Text) } catch { } }
Set-Phase 'start'
$dogMinutes = if ($Weak) { 10 } else { 14 }
$dog = @'
param([int]$TestPid, [string]$PhaseFile, [string]$Shots, [int]$Minutes)
Start-Sleep -Seconds ($Minutes * 60)
$p = Get-Process -Id $TestPid -ErrorAction SilentlyContinue
if (-not $p) { return }
$phase = try { [IO.File]::ReadAllText($PhaseFile) } catch { '?' }
$wins = @(Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { '{0}: {1}' -f $_.ProcessName, $_.MainWindowTitle }) -join ' | '
$thr = @($p.Threads | Sort-Object TotalProcessorTime -Descending | Select-Object -First 6 | ForEach-Object { 'thread {0} {1} {2} cpu {3:N1}s {4}' -f $_.Id, $_.PriorityLevel, $_.ThreadState, $_.TotalProcessorTime.TotalSeconds, $(if ($_.ThreadState -eq 'Wait') { $_.WaitReason }) }) -join ' | '
Write-Host ('::error::UI test still running after {0} min. Last step: {1}. Process CPU {2:N0}s. Windows: {3}. Threads: {4}' -f $Minutes, $phase, $p.TotalProcessorTime.TotalSeconds, $wins, $thr)
if ($Shots) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $g.Dispose()
        $bmp.Save((Join-Path $Shots 'hang.png'), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    } catch { }
}
Stop-Process -Id $TestPid -Force
'@
$dogFile = Join-Path $work 'watchdog.ps1'
[IO.File]::WriteAllText($dogFile, $dog)
$dogArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -TestPid {1} -PhaseFile "{2}" -Shots "{3}" -Minutes {4}' -f $dogFile, $PID, $script:PhaseFile, $Shots, $dogMinutes
$script:Dog = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $dogArgs -NoNewWindow -PassThru

# One CPU core for the window, its drawing and every background scan, like a cheap or old laptop
$script:BudgetScale = 1
if ($Weak) {
    [Diagnostics.Process]::GetCurrentProcess().ProcessorAffinity = [IntPtr]1
    $script:BudgetScale = 2
    Write-Host "Weak PC: the app runs on one CPU core (of $([Environment]::ProcessorCount))"
}
Initialize-OzSpanish $Oz.SpanishPairs
$Oz.Lang = 'en'
Initialize-OzWindow
Write-Host ('Drawing: {0} (WPF render tier {1})' -f $(if (([System.Windows.Media.RenderCapability]::Tier -shr 16) -eq 0) { 'software, no graphics acceleration' } else { 'graphics card' }), ([System.Windows.Media.RenderCapability]::Tier -shr 16))
$win = $Oz.Window
$win.Dispatcher.Add_UnhandledException({
        $script:Problems.Add('Unhandled UI exception: ' + $_.Exception.Message)
        Write-Host ('::error::Unhandled UI exception: ' + $_.Exception.ToString())
        $_.Handled = $true
    })

function Wait-Ui([int]$Ms = 250) {
    $end = [DateTime]::Now.AddMilliseconds($Ms)
    do {
        $win.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::Background)
        Start-Sleep -Milliseconds 15
    } while ([DateTime]::Now -lt $end)
}
function Wait-Idle([int]$Seconds = 120) {
    $end = [DateTime]::Now.AddSeconds($Seconds)
    do { Wait-Ui 200 } while ($Oz.Busy -and [DateTime]::Now -lt $end)
    if ($Oz.Busy) { Fail "Still busy after $Seconds s" }
}
function Save-Shot([string]$Name, $Visual = $win) {
    if (-not $Shots) { return }
    $Visual.UpdateLayout()
    $w = [int][math]::Ceiling($Visual.ActualWidth)
    $h = [int][math]::Ceiling($Visual.ActualHeight)
    if ($w -lt 1 -or $h -lt 1) { return }
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    if ($Visual -is [System.Windows.Window]) { $rtb.Render($Visual) }
    else {
        # A part of the window, drawn in full even where it is scrolled out of view
        $dv = New-Object System.Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $dc.DrawRectangle((Get-OzBrush '#05070D'), $null, (New-Object System.Windows.Rect(0, 0, $w, $h)))
        $dc.DrawRectangle((New-Object System.Windows.Media.VisualBrush($Visual)), $null, (New-Object System.Windows.Rect(0, 0, $w, $h)))
        $dc.Close()
        $rtb.Render($dv)
    }
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $Shots "$Name.png"))
    try { $enc.Save($fs) } finally { $fs.Dispose() }
}
function Set-Size([int]$W, [int]$H) {
    $win.WindowState = 'Normal'
    $win.MinWidth = [math]::Min($win.MinWidth, $W)
    $win.MinHeight = [math]::Min($win.MinHeight, $H)
    $win.Width = $W
    $win.Height = $H
    Wait-Ui 400
}

# ---------- speed: how long each click keeps the window from answering ----------
Set-Phase 'speed: how long each click keeps the window from answering'
# A timer beats every few milliseconds on the window's thread. The longest gap between two beats
# while a click is handled is how long the window was frozen (no hover, no scrolling, no clicks).
$script:Clock = [Diagnostics.Stopwatch]::StartNew()
$script:Beat = @{ Last = 0.0; Max = 0.0 }
$meter = New-Object System.Windows.Threading.DispatcherTimer ([System.Windows.Threading.DispatcherPriority]::Normal)
$meter.Interval = [TimeSpan]::FromMilliseconds(5)
$meter.Add_Tick({
        $now = $script:Clock.Elapsed.TotalMilliseconds
        $gap = $now - $script:Beat.Last
        if ($gap -gt $script:Beat.Max) { $script:Beat.Max = $gap }
        $script:Beat.Last = $now
    })
$meter.Start()
$script:Speed = New-Object System.Collections.Generic.List[object]
function Measure-Click([string]$Name, [scriptblock]$Do, [int]$Budget = 0) {
    Set-Phase "speed: $Name"
    Wait-Ui 150
    if ($null -ne $Oz.Profile) { $Oz.Profile.Add("--- $Name|0"); $Oz.ProfileLast = [Diagnostics.Stopwatch]::GetTimestamp() }
    $script:Beat.Last = $script:Clock.Elapsed.TotalMilliseconds
    $script:Beat.Max = 0.0
    $t0 = $script:Clock.Elapsed.TotalMilliseconds
    & $Do
    # everything the click queued (layout, drawing, work put off for later) has run when this returns
    $win.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::ContextIdle)
    $t1 = $script:Clock.Elapsed.TotalMilliseconds
    $freeze = [math]::Max($script:Beat.Max, $t1 - $script:Beat.Last)
    while ($Oz.Busy) { Wait-Ui 50 }
    $win.Dispatcher.Invoke([Action] {}, [System.Windows.Threading.DispatcherPriority]::ContextIdle)
    $t2 = $script:Clock.Elapsed.TotalMilliseconds
    $script:Speed.Add([pscustomobject]@{ Step = $Name; Freeze = [int]$freeze; Done = [int]($t2 - $t0); Budget = $Budget })
}
# ---------- open the window and let the startup scan finish ----------
Set-Phase 'open the window and let the startup scan finish'
# (measured too: the user can already click while the hardware scan runs)
$script:Beat.Last = $script:Clock.Elapsed.TotalMilliseconds
$script:Beat.Max = 0.0
$t0 = $script:Clock.Elapsed.TotalMilliseconds
# the app's own timing marks (Step-OzProfile) during startup and the first visit of each page
$Oz.Profile = New-Object System.Collections.Generic.List[string]
$Oz.ProfileLast = [Diagnostics.Stopwatch]::GetTimestamp()
Set-Phase 'window opens, startup scan'
$win.Show()
Wait-Ui 500
Wait-Idle 180
$script:Speed.Add([pscustomobject]@{ Step = 'startup until ready'; Freeze = [int]$script:Beat.Max; Done = [int]($script:Clock.Elapsed.TotalMilliseconds - $t0); Budget = 0 })
# memory the whole app uses once it is ready (window, background runspaces, all pages built later)
[GC]::Collect()
$script:MemReady = [int]([Diagnostics.Process]::GetCurrentProcess().WorkingSet64 / 1MB)
if ($Oz.Sys) { Pass "hardware scan finished: $($Oz.Sys.Score.TierName), $($Oz.Rows.Count) tweak rows" } else { Fail 'The hardware scan did not finish' }

$pages = 'Dash', 'Tweaks', 'Profiles', 'Games', 'Themes', 'Debloat', 'Drivers', 'Tools', 'Backup', 'Log'

function Find-Child($Root, [scriptblock]$Where) {
    foreach ($c in [System.Windows.LogicalTreeHelper]::GetChildren($Root)) {
        if ($c -isnot [System.Windows.DependencyObject]) { continue }
        if (& $Where $c) { return $c }
        $f = Find-Child $c $Where
        if ($f) { return $f }
    }
}
foreach ($round in 'first', 'again') {
    foreach ($p in @($pages[1..($pages.Count - 1)]) + 'Dash') {
        # budgets: generous for the test machine (no graphics card, shared CPU), they catch the lag of 1.4 coming back
        $budget = if ($round -eq 'again') { 500 } elseif ($p -eq 'Themes') { 1500 } elseif ($p -eq 'Games') { 800 } else { 600 }
        Measure-Click "$round open $p" { $Oz.UI["Nav$p"].IsChecked = $true } $budget
    }
    if ($round -eq 'first') {
        foreach ($m in @($Oz.Profile)) { $a = $m -split '\|'; $script:Speed.Add([pscustomobject]@{ Step = "mark: $($a[0])"; Freeze = [int]$a[1]; Done = [int]$a[1]; Budget = 0 }) }
        $Oz.Profile = $null
    }
}
$Oz.UI.NavThemes.IsChecked = $true
Wait-Ui 300
foreach ($i in 1..2) {
    Measure-Click 'THEMES tab APPEARANCE' { $Oz.UI.ThemeTabLook.IsChecked = $true } 900
    Measure-Click 'THEMES tab GENERAL' { $Oz.UI.ThemeTabGeneral.IsChecked = $true } 900
}
$lookChips = @(Find-Child $Oz.UI.ThemeLookPanel { param($c) $c -is [System.Windows.Controls.Panel] }).Children
foreach ($i in 1, 2, 0) { Measure-Click "THEMES look chip $i" { $lookChips[$i].IsChecked = $true } 900 }
$plus = Find-Child $Oz.UI.ThemeClockPanel { param($c) $c -is [System.Windows.Controls.Button] -and [string]$c.Content -eq '+' }
$clickEvent = [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
foreach ($i in 1..3) { Measure-Click "THEMES margin + ($i)" { $plus.RaiseEvent((New-Object System.Windows.RoutedEventArgs($clickEvent))) } 900 }
$posChip = Find-Child $Oz.UI.ThemeClockPanel { param($c) $c -is [System.Windows.Controls.RadioButton] -and -not $c.IsChecked }
Measure-Click 'THEMES clock position' { $posChip.IsChecked = $true } 900
$barSwitch = @(@(Find-Child $Oz.UI.ThemeWidgetPanel { param($c) $c -is [System.Windows.Controls.Grid] }).Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] }) | Select-Object -First 1
if (-not $barSwitch) { $barSwitch = Find-Child $Oz.UI.ThemeWidgetPanel { param($c) $c -is [System.Windows.Controls.CheckBox] } }
Measure-Click 'THEMES widget switch off' { $barSwitch.IsChecked = -not $barSwitch.IsChecked } 900
Measure-Click 'THEMES widget switch on' { $barSwitch.IsChecked = -not $barSwitch.IsChecked } 900
Measure-Click 'THEMES style' { Set-OzThemeValue 'Style' 'Blade' } 900
Measure-Click 'THEMES style back' { Set-OzThemeValue 'Style' 'Horizon' } 900
$Oz.UI.NavTweaks.IsChecked = $true
Wait-Ui 300
foreach ($k in 'ACTIVE', 'RECOMMENDED', 'ALL') { Measure-Click "TWEAKS chip $k" { $Oz.Chips[$k].IsChecked = $true } 900 }
foreach ($q in 'p', 'po', 'pow', 'powe', 'power', '') { Measure-Click "TWEAKS search '$q'" { $Oz.UI.TweakSearch.Text = $q } 900 }
# switching language is rare and redraws every page: only a gross slowdown fails here
$Oz.Profile = New-Object System.Collections.Generic.List[string]
Measure-Click 'language ES' { $Oz.UI.LangEs.IsChecked = $true } 6000
Measure-Click 'language EN' { $Oz.UI.LangEn.IsChecked = $true } 6000
foreach ($m in @($Oz.Profile)) { $a = $m -split '\|'; $script:Speed.Add([pscustomobject]@{ Step = "mark: $($a[0])"; Freeze = [int]$a[1]; Done = [int]$a[1]; Budget = 0 }) }
$Oz.Profile = $null
# Where the time goes: each part on its own (window's thread, no waiting)
function Measure-Part([string]$Name, [scriptblock]$Do) {
    Set-Phase "part: $Name"
    Wait-Ui 50
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Do
    $sw.Stop()
    $script:Speed.Add([pscustomobject]@{ Step = "part: $Name"; Freeze = [int]$sw.Elapsed.TotalMilliseconds; Done = [int]$sw.Elapsed.TotalMilliseconds; Budget = 0 })
}
$Oz.UI.NavThemes.IsChecked = $true
Wait-Ui 300
Measure-Part 'THEMES status' { Update-OzThemeStatus }
Measure-Part 'THEMES looks' { Show-OzThemeLooks }
Measure-Part 'THEMES widgets' { Show-OzThemeWidgets }
Measure-Part 'THEMES clock panel' { Show-OzThemeClockPanel }
Measure-Part 'THEMES walls' { Show-OzThemeWalls; Show-OzThemeWallFit }
Measure-Part 'THEMES dock apps' { Show-OzThemeDock }
Measure-Part 'THEMES bar and dock' { Show-OzThemeBarDock }
Measure-Part 'THEMES screen list' { $Oz.ThemeScreens = @(Get-OzScreens) }
Measure-Part 'THEMES screens card' { Show-OzThemeScreens }
Measure-Part 'THEMES preview' { Update-OzThemePreview }
Measure-Part 'THEMES preview, new wallpaper' { $Oz.ThemeLumaKey = $null; $Oz.ThemeLumaReads = $null; $Oz.ThemePreviewKey = $null; $Oz.WallPrefetch = $null; Update-OzThemePreview }
Measure-Part 'THEMES whole page' { Show-OzThemes }
Measure-Part 'THEMES whole page + layout' { Show-OzThemes; $win.UpdateLayout() }
Measure-Part 'lang: window texts' { foreach ($x in @($Oz.XamlTexts)) { try { $x.El.($x.Prop) = T $x.En } catch { } } }
Measure-Part 'lang: dashboard' { Update-OzDashboard }
Measure-Part 'lang: tweak rows' { foreach ($row in @($Oz.Rows.Values)) { Set-OzRowText $row; Set-OzRowBadges $row; Set-OzRowVisual $row } }
Measure-Part 'lang: profiles' { Initialize-OzProfileCards }
Measure-Part 'lang: tools' { Initialize-OzTools }
Measure-Part 'lang: games' { Show-OzGames $Oz.LastGames -Quiet }
Measure-Part 'lang: drivers' { Show-OzDriverRecs; if ($Oz.LastDriverScan) { Show-OzDriverScan $Oz.LastDriverScan -Quiet } }
Measure-Part 'lang: debloat' { if ($null -ne $Oz.LastBloat) { Show-OzBloat $Oz.LastBloat } }
Measure-Part 'lang: journal' { $Oz.JournalViewSig = $null; Update-OzJournalView }
Measure-Part 'startup: rows from state' { foreach ($row in @($Oz.Rows.Values)) { Set-OzRowFromState $row } }
Measure-Part 'startup: filter + counts' { Update-OzPendingBar; Update-OzActiveCount; Update-OzFilter }
$Oz.UI.NavDash.IsChecked = $true
Wait-Ui 300
$meter.Stop()
$memEnd = [int]([Diagnostics.Process]::GetCurrentProcess().WorkingSet64 / 1MB)
$speedLines = @('Speed in ms. Freeze = longest time the window did not answer. Done = until everything finished.',
    ('Memory: {0} MB when ready, {1} MB after every page was opened. CPU cores used: {2}.' -f $script:MemReady, $memEnd, $(if ($Weak) { 1 } else { [Environment]::ProcessorCount }))) +
    @($script:Speed | ForEach-Object { '{0,-34} freeze {1,6}   done {2,6}' -f $_.Step, $_.Freeze, $_.Done })
$speedLines | ForEach-Object { Write-Host "SPEED  $_" }
# The table is also kept as a file next to the screenshots and shown as a note on the run
if ($Shots) { [IO.File]::WriteAllLines((Join-Path $Shots 'speed.txt'), [string[]]$speedLines) }
Write-Host ('::notice title=UI speed' + $(if ($Weak) { ' on one CPU core' }) + '::' + (($speedLines -join "`n") -replace '%', '%25' -replace "`r", '' -replace "`n", '%0A'))
foreach ($s in $script:Speed) {
    if ($s.Budget -and $s.Freeze -gt $s.Budget * $script:BudgetScale) { Fail ('{0}: the window froze for {1} ms (budget {2} ms)' -f $s.Step, $s.Freeze, ($s.Budget * $script:BudgetScale)) }
}
# A single slow click can be the test machine; the middle value of each group is what users feel.
# Version 1.4 took about 100 ms for every THEMES click: these budgets catch that coming back.
foreach ($g in @(@('THEMES ', 90), @('TWEAKS ', 90))) {
    $vals = @($script:Speed | Where-Object { $_.Step.StartsWith($g[0]) } | ForEach-Object { $_.Freeze } | Sort-Object)
    if (-not $vals.Count) { continue }
    $mid = $vals[[int][math]::Floor(($vals.Count - 1) / 2)]
    $limit = $g[1] * $script:BudgetScale
    if ($mid -gt $limit) { Fail ('{0}clicks: the window froze for {1} ms in the middle of {2} clicks (budget {3} ms)' -f $g[0], $mid, $vals.Count, $limit) }
    else { Pass ('{0}clicks: {1} ms in the middle of {2} clicks (budget {3} ms)' -f $g[0], $mid, $vals.Count, $limit) }
}
if ($Weak) {
    # only the speed part runs for the weak PC
    $win.Close()
    Wait-Ui 300
    try { Stop-Process -Id $script:Dog.Id -Force -ErrorAction SilentlyContinue } catch { }
    if ($script:Problems.Count) { Write-Host "$($script:Problems.Count) problem(s)"; exit 1 }
    Write-Host 'Weak PC speed test passed' -ForegroundColor Green
    exit 0
}
$Oz.UI.NavDash.IsChecked = $true
Wait-Ui 300

foreach ($size in @(@('normal', 1320, 840), @('laptop', 1093, 574))) {
    Set-Size $size[1] $size[2]
    foreach ($p in $pages) {
        $Oz.UI["Nav$p"].IsChecked = $true
        Wait-Ui 300
        Wait-Idle 120
        if ($Oz.UI["Page$p"].Visibility -ne 'Visible') { Fail "$p page did not open" }
        Save-Shot ('{0}-{1}' -f $size[0], $p.ToLower())
    }
    # Every menu button must be on screen without scrolling
    $statusTop = $win.ActualHeight - 30
    foreach ($p in $pages) {
        $nav = $Oz.UI["Nav$p"]
        $y = $nav.TranslatePoint((New-Object System.Windows.Point(0, 0)), $win).Y
        if ($y + $nav.ActualHeight -gt $statusTop + 0.5) { Fail ('{0}: menu button {1} is cut off (bottom {2:N0}, space ends at {3:N0})' -f $size[0], $p, ($y + $nav.ActualHeight), $statusTop) }
    }
    Pass "$($size[0]) size ($($size[1])x$($size[2])): every page opened"
}
if ($Oz.UI.NavProfileCard.Visibility -ne 'Collapsed') { Fail 'laptop size: the profile card in the menu should be hidden' }
Set-Size 1320 840
if ($Oz.UI.NavProfileCard.Visibility -ne 'Visible') { Fail 'normal size: the profile card in the menu should be shown' }

# ---------- CLEAN UP FILES on the Tools page (scan only, nothing is deleted) ----------
Set-Phase 'CLEAN UP FILES on the Tools page (scan only, nothing is deleted)'
$Oz.UI.NavTools.IsChecked = $true
Wait-Ui 300
$driveBoxes = @($Oz.UI.CleanDrivePanel.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] })
if ($driveBoxes.Count -ge 1 -and @($driveBoxes | Where-Object IsChecked).Count -eq 1) { Pass "cleanup: $($driveBoxes.Count) drive(s) listed, only the Windows drive ticked" }
else { Fail "cleanup: $($driveBoxes.Count) drive boxes, $(@($driveBoxes | Where-Object IsChecked).Count) ticked" }
Invoke-OzSafe 'Cleanup scan' { Invoke-OzCleanScan }
Wait-Idle 120
$cleanCount = @($Oz.CleanChecks).Count
if ($cleanCount -ge 2) { Pass "cleanup: scan lists $cleanCount items" } else { Fail "cleanup: scan listed $cleanCount items" }
if (@($Oz.CleanChecks | Where-Object { $_.IsChecked -and -not $_.Tag.Rec }).Count) { Fail 'cleanup: an item that is not recommended was ticked by the scan' }
Set-OzCleanChecks
if (@($Oz.CleanChecks | Where-Object IsChecked).Count) { Fail 'cleanup: SELECT NONE left items ticked' }
Set-OzCleanChecks -Recommended
$recTicked = @($Oz.CleanChecks | Where-Object IsChecked)
if (@($recTicked | Where-Object { -not $_.Tag.Rec }).Count) { Fail 'cleanup: SELECT RECOMMENDED ticked an item that is not recommended' }
else { Pass "cleanup: SELECT NONE / SELECT RECOMMENDED ($($recTicked.Count) ticked): $($Oz.UI.CleanTotal.Text)" }
Save-Shot 'tools-cleanup' $Oz.UI.CleanList.Parent
Set-Size 1093 574
Save-Shot 'laptop-tools-cleanup' $Oz.UI.CleanList.Parent
Set-Size 1320 840
Set-OzLanguage 'es'
Wait-Ui 300
if (@($Oz.CleanChecks).Count -ne $cleanCount) { Fail "cleanup: Spanish shows $(@($Oz.CleanChecks).Count) items instead of $cleanCount" }
elseif ($Oz.UI.BtnCleanSelected.Content -ne 'LIMPIAR SELECCIONADOS') { Fail "cleanup: Spanish button says '$($Oz.UI.BtnCleanSelected.Content)'" }
else { Pass 'cleanup: Spanish list and buttons' }
Save-Shot 'es-tools-cleanup' $Oz.UI.CleanList.Parent
Set-OzLanguage 'en'
Wait-Ui 300
# Every drive ticked: other drives offer only their Recycle Bin
foreach ($b in @($Oz.UI.CleanDrivePanel.Children | Where-Object { $_ -is [System.Windows.Controls.CheckBox] })) { $b.IsChecked = $true; $Oz.CleanDriveSel[[string]$b.Tag] = $true }
Invoke-OzSafe 'Cleanup scan' { Invoke-OzCleanScan }
Wait-Idle 120
$win0 = Get-OzWindowsDrive
$otherItems = @($Oz.CleanChecks | Where-Object { $_.Tag.Drive -ne $win0 })
if (@($otherItems | Where-Object { $_.Tag.Id -ne 'bin' }).Count) { Fail 'cleanup: another drive lists something other than its Recycle Bin' }
elseif (@($otherItems | Where-Object IsChecked).Count) { Fail "cleanup: another drive's Recycle Bin was ticked by the scan" }
else { Pass "cleanup: every drive scanned, other drives offer only their Recycle Bin ($($otherItems.Count))" }
Save-Shot 'tools-cleanup-all-drives' $Oz.UI.CleanList.Parent

# ---------- THEMES page: every control, both tabs, a few settings, Spanish ----------
Set-Phase 'THEMES page: every control, both tabs, a few settings, Spanish'
$Oz.UI.NavThemes.IsChecked = $true
Wait-Ui 400
if ($Oz.ThemesShown) { Pass "THEMES page built (Rainmeter installed: $([bool]$Oz.Rainmeter.Installed))" } else { Fail 'THEMES page was not built' }
$general = @($Oz.UI.ThemeClockPanel.Children).Count
$Oz.UI.ThemeTabLook.IsChecked = $true
Wait-Ui 300
$look = @($Oz.UI.ThemeClockPanel.Children).Count
if ($general -ge 5 -and $look -ge 5) { Pass "clock settings: $general rows (general), $look rows (appearance)" } else { Fail "clock settings rows: $general general, $look appearance" }
Save-Shot 'themes-appearance' $Oz.UI.PageThemes.Content
foreach ($pair in @(@('Style', 'Blade'), @('Pos', 'BR'), @('Look', 'neon'), @('AutoInk', $false), @('Style', 'Pulse'), @('AutoInk', $true), @('InkMode', 'threshold'), @('Scale', 150), @('Bar', $false), @('Pos', 'TL'))) {
    Set-OzThemeValue $pair[0] $pair[1]
    Wait-Ui 100
}
if ($Oz.ThemeDirty -and $Oz.UI.ThemeStatus.Text) { Pass "settings changes are marked as not applied: $($Oz.UI.ThemeStatus.Text)" } else { Fail 'THEMES page did not mark changes as not applied' }
if (@($Oz.UI.ThemePreviewLayer.Children).Count -ge 2) { Pass 'theme preview draws the clock and dock' } else { Fail "theme preview has $(@($Oz.UI.ThemePreviewLayer.Children).Count) parts" }
Save-Shot 'themes-changed' $Oz.UI.PageThemes.Content
# SCREENS card, IDENTIFY, status bar items, dock size, background, picture fit
$nScreens = @($Oz.ThemeScreens).Count
if ($nScreens -ge 1 -and @($Oz.UI.ThemeScreenPanel.Children).Count -ge 3 -and $Oz.UI.ThemeScreenMap.Child.Children.Count -eq $nScreens) { Pass "SCREENS card: $nScreens screen(s), a row for the clock, the bar and the dock" }
else { Fail "SCREENS card: $nScreens screen(s), $(@($Oz.UI.ThemeScreenPanel.Children).Count) rows" }
Invoke-OzSafe 'Themes' { Show-OzScreenNumbers }
Wait-Ui 300
if (@($Oz.IdentifyWindows).Count -eq $nScreens -and @($Oz.IdentifyWindows | Where-Object { $_.IsVisible }).Count -eq $nScreens) { Pass 'IDENTIFY shows a number on every screen' } else { Fail "IDENTIFY showed $(@($Oz.IdentifyWindows).Count) number(s) for $nScreens screen(s)" }
if (@($Oz.IdentifyWindows).Count) { Save-Shot 'themes-identify' $Oz.IdentifyWindows[0] }
Wait-Ui 3200
if (@($Oz.IdentifyWindows).Count) { Fail 'IDENTIFY numbers were still open after 3 seconds' } else { Pass 'IDENTIFY numbers close by themselves' }
Set-OzThemeValue 'Bar' $true
Set-OzThemeValue 'BarItems' @('Cpu', 'Ram')
Set-OzThemeValue 'DockSize' 'L'
Set-OzThemeValue 'BgStyle' 'Glass'
Set-OzThemeValue 'WallFit' 'Fit'
Set-OzThemeValue 'ScreenBar' 'all'
Wait-Ui 300
$pbar = @($Oz.UI.ThemePreviewLayer.Children | Where-Object { $_ -is [System.Windows.Controls.Grid] }) | Select-Object -First 1
# wallpapers button + CPU + RAM + settings button, no date pill
if ($pbar -and $pbar.Children.Count -eq 4) { Pass 'preview: the status bar shows only the picked items' } else { Fail "preview: the status bar has $(if ($pbar) { $pbar.Children.Count } else { 'no' }) pills (expected 4)" }
$fitChip = Find-Child $Oz.UI.ThemeWallFitPanel { param($c) $c -is [System.Windows.Controls.RadioButton] -and $c.Tag.Value -eq 'Fit' }
if ($fitChip -and $fitChip.IsChecked) { Pass 'picture fit chips follow the setting' } else { Fail 'picture fit chip FIT is not checked' }
Save-Shot 'themes-options' $Oz.UI.PageThemes.Content
Set-OzThemeValue 'BarItems' @($Oz.ThemeBarItems)
Set-OzThemeValue 'ScreenBar' 'main'
Set-OzThemeValue 'BgStyle' 'Normal'
Wait-Ui 200
# A job that returns several objects: the result is read item by item (APPLY / REMOVE THEME)
$jr = Get-OzJobResult (Invoke-OzJob -ScriptBlock { [pscustomobject]@{ Path = 'a' }; [pscustomobject]@{ Path = 'b' }; [pscustomobject]@{ Ok = $false; Msg = 'boom' } })
if ($jr -and $jr.Ok -eq $false -and $jr.Msg -eq 'boom') { Pass 'background job results are read one by one' } else { Fail "background job result read wrong: $($jr | ConvertTo-Json -Compress)" }
$jr = Get-OzJobResult (Invoke-OzJob -ScriptBlock { [pscustomobject]@{ Ok = $true; Msg = '' } })
if ($jr -and $jr.Ok -eq $true) { Pass 'a single job result is read' } else { Fail 'a single job result was not read' }
# CREATE OZZYHN WALLPAPERS, the real button handler
$before = @(Get-Content -LiteralPath $Oz.LogFile -ErrorAction SilentlyContinue).Count
Invoke-OzSafe 'Wallpapers' { Invoke-OzThemeWallpapers }
Wait-Idle 120
$newLines = @(Get-Content -LiteralPath $Oz.LogFile -ErrorAction SilentlyContinue | Select-Object -Skip $before)
$wallDir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'OZZYHN Wallpapers'
$wallFiles = @(Get-ChildItem -LiteralPath $wallDir -Filter 'ozzyhn-*.jpg' -ErrorAction SilentlyContinue)
$bad = @($newLines | Where-Object { $_ -match '\[(WARN|ERR ?)\]' })
if ($bad.Count) { Fail "CREATE OZZYHN WALLPAPERS logged: $($bad -join ' | ')" }
elseif ($wallFiles.Count -eq 6 -and @($Oz.ThemeCfg.WallFolders) -contains $wallDir -and ($newLines -match '6 wallpapers saved')) { Pass 'CREATE OZZYHN WALLPAPERS draws 6 wallpapers and adds the folder' }
else { Fail "CREATE OZZYHN WALLPAPERS: $($wallFiles.Count) files, folder added: $(@($Oz.ThemeCfg.WallFolders) -contains $wallDir), log: $($newLines -join ' | ')" }
# close the folder window it opened
Start-Sleep -Seconds 2
try { foreach ($w in @((New-Object -ComObject Shell.Application).Windows())) { if ([string]$w.LocationURL -like '*OZZYHN%20Wallpapers*') { $w.Quit() } } } catch { }
$Oz.UI.ThemeTabGeneral.IsChecked = $true
Wait-Ui 300
Set-OzLanguage 'es'
Wait-Ui 300
if ($Oz.UI.NavThemes.Content -eq 'Temas') { Pass 'THEMES page in Spanish' } else { Fail "Spanish: the Themes button says '$($Oz.UI.NavThemes.Content)'" }
Save-Shot 'es-themes' $Oz.UI.PageThemes.Content
Set-OzLanguage 'en'
Wait-Ui 300
Set-Size 1093 574
Save-Shot 'laptop-themes'
Set-Size 1320 840

# ---------- battery wear from powercfg's report (laptops whose WMI battery data is empty) ----------
Set-Phase 'battery wear from powercfg''s report (laptops whose WMI battery data is empty)'
$sample = '<?xml version="1.0" encoding="utf-8"?><BatteryReport xmlns="http://schemas.microsoft.com/battery/2012"><Batteries><Battery><Id>Primary</Id><DesignCapacity>83000</DesignCapacity><FullChargeCapacity>74700</FullChargeCapacity><CycleCount>12</CycleCount></Battery></Batteries></BatteryReport>'
$cap = Read-OzBatteryReport $sample
if ($cap -and $cap.Design -eq 83000 -and $cap.Full -eq 74700) { Pass 'battery report: design and full-charge capacity read' } else { Fail "battery report read wrong: $($cap | ConvertTo-Json -Compress)" }
if ($null -eq (Read-OzBatteryReport '<BatteryReport xmlns="http://schemas.microsoft.com/battery/2012"><Batteries /></BatteryReport>')) { Pass 'battery report without a battery gives nothing' } else { Fail 'battery report without a battery gave a value' }
$capNow = Get-OzBatteryCapacity
if (-not (Test-Path -LiteralPath (Join-Path $Oz.DataDir 'battery-report.xml'))) { Pass "powercfg battery report ran and was cleaned up (this PC: $(if ($capNow) { 'battery found' } else { 'no battery' }))" } else { Fail 'the battery report file was left behind' }
$sheet = Get-OzSpecSheet $Oz.Sys
if ($sheet -notmatch 'wear %') { Pass 'spec sheet never prints an empty wear value' } else { Fail 'spec sheet printed "wear %" with no number' }

# ---------- Ctrl+F ----------
Set-Phase 'Ctrl+F'
$Oz.UI.NavDash.IsChecked = $true
Wait-Ui 200
Invoke-OzSearchShortcut
Wait-Ui 300
if ($Oz.UI.PageTweaks.Visibility -eq 'Visible') { Pass 'Ctrl+F opens the tweak search' } else { Fail 'Ctrl+F did not open TWEAKS' }

# ---------- Spanish ----------
Set-Phase 'Spanish'
Set-OzLanguage 'es'
Wait-Ui 300
foreach ($p in 'Dash', 'Tweaks', 'Games', 'Backup') {
    $Oz.UI["Nav$p"].IsChecked = $true
    Wait-Ui 300
    Wait-Idle 60
    Save-Shot ('es-{0}' -f $p.ToLower())
}
if ($Oz.UI.NavGames.Content -ne 'Juegos') { Fail "Spanish: the Games button says '$($Oz.UI.NavGames.Content)'" } else { Pass 'Spanish switch' }
Set-OzLanguage 'en'
Wait-Ui 300

# ---------- dialogs (closed automatically; a picture of each is saved) ----------
Set-Phase 'dialogs (closed automatically; a picture of each is saved)'
$script:DialogSeen = New-Object System.Collections.Generic.List[string]
$closer = New-Object System.Windows.Threading.DispatcherTimer
$closer.Interval = [TimeSpan]::FromMilliseconds(400)
$closer.Add_Tick({
        $d = $Oz.Dialog
        if ($d -and $d.IsLoaded) {
            $n = $script:DialogSeen.Count + 1
            Save-Shot ("dialog-$n") $d
            $script:DialogSeen.Add([string]$d.Title)
            $d.Tag = 'No'
            $d.Close()
        }
    })
$closer.Start()
$r = Show-OzDialog -Text 'Test question with a long line of text so the wrapping can be seen in the picture.' -Buttons YesNoCancel -Kind Question -Labels @('APPLY NOW', 'SHOW ME FIRST', 'CANCEL')
if ($r -ne 'No') { Fail "Dialog returned '$r' instead of 'No'" }
Show-OzResults -Total 12 -Ok 11 -Fail 1 -Blocked @('Example tweak') -Reboot $true -ActiveBefore 10
# CLEAN SELECTED asks first; the answer here is NO, so nothing is deleted
$expect = 2
$pick = @($Oz.CleanChecks | Where-Object { $_.IsEnabled }) | Select-Object -First 1
if ($pick) {
    $pick.IsChecked = $true
    $probe = Join-Path $env:SystemRoot 'Temp\oz-ui-probe.tmp'
    Set-Content -LiteralPath $probe -Value 'probe'
    Invoke-OzSafe 'Cleanup' { Invoke-OzCleanSelected }
    $expect = 3
    if (Test-Path -LiteralPath $probe) { Pass 'cleanup: answering NO deletes nothing' } else { Fail 'cleanup: files were deleted after answering NO' }
}
$closer.Stop()
if ($script:DialogSeen.Count -eq $expect) { Pass "themed dialogs and results card ($expect)" } else { Fail "Expected $expect dialogs, saw $($script:DialogSeen.Count)" }

# ---------- Games page with a test game ----------
Set-Phase 'Games page with a test game'
$cfg = Join-Path $work 'videoconfig.txt'
[IO.File]::WriteAllText($cfg, "`"VideoConfig`"`r`n{`r`n`t`"setting.fullscreen`"`t`t`"1`"`r`n`t`"setting.mat_vsync_mode`"`t`t`"1`"`r`n`t`"setting.dvs_enable`"`t`t`"0`"`r`n`t`"setting.ssao_enabled`"`t`t`"1`"`r`n}`r`n")
$apex = Get-OzGameCatalog | Where-Object Id -EQ 'apex'
$map = Read-OzGameConfig $cfg 'Vdf'
$fake = [pscustomobject]@{
    Game = $apex; Installed = $true; Launcher = 'Steam'; Location = $work
    IconPath = (Join-Path $env:SystemRoot 'explorer.exe'); ConfigPath = $cfg; ConfigFound = $true
    Review = @($apex.Checks | ForEach-Object { Test-OzGameCheck $_ $map })
}
if (-not (Get-OzFileIcon $fake.IconPath)) { Fail 'Could not read the icon of explorer.exe' }
$Oz.UI.NavGames.IsChecked = $true
Wait-Ui 200
Show-OzGames (@($fake) + @(Get-OzGameScan | Where-Object { $_.Game.Id -ne 'apex' }))
Wait-Ui 400
Save-Shot 'games-test-game'
foreach ($lang in 'en', 'es') {
    if ($lang -eq 'es') {
        Set-OzLanguage 'es'
        Show-OzGames (@($fake) + @(Get-OzGameScan | Where-Object { $_.Game.Id -ne 'apex' }))
        Wait-Ui 300
    }
    $i = 0
    foreach ($card in @($Oz.UI.GamesPanel.Children)) {
        $i++
        $card.Child.Children[1].Visibility = 'Visible'   # open the details
        Wait-Ui 150
        Save-Shot ('card-{0}-{1}' -f $lang, $i) $card
    }
}
Set-OzLanguage 'en'
Show-OzGames (@($fake) + @(Get-OzGameScan | Where-Object { $_.Game.Id -ne 'apex' }))
Set-Size 1093 574
Save-Shot 'laptop-games-test-game'
if ($Oz.UI.GamesPanel.Children.Count -eq 6) { Pass 'Games page shows all 6 games' } else { Fail "Games page shows $($Oz.UI.GamesPanel.Children.Count) cards" }

# ---------- close ----------
Set-Phase 'close'
$win.Close()
Wait-Ui 300

$errLines = @(Get-Content -LiteralPath $Oz.LogFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '\[ERR ?\]' })
foreach ($l in $errLines) { Fail "App logged an error: $l" }
Write-Host '--- app log (warnings) ---'
Get-Content -LiteralPath $Oz.LogFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '\[WARN\]' } | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
try { Stop-Process -Id $script:Dog.Id -Force -ErrorAction SilentlyContinue } catch { }
if ($script:Problems.Count) { Write-Host "$($script:Problems.Count) problem(s)"; exit 1 }
Write-Host 'UI test passed' -ForegroundColor Green
# GitHub Actions fails the step on the last native command's exit code (powercfg returns 1 on a PC
# without a battery), so the result of this test is stated here.
exit 0
