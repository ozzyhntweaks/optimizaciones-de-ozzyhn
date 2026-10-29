<#
    Tests the THEMES page end to end on a real Windows machine (GitHub's Windows runner):
      1. builds the skin files for every clock style, look, position, size and language, and checks
         that every size placeholder was filled in and the ASCII files stay ASCII
      2. draws the OZZYHN wallpapers
      3. installs Rainmeter from its official GitHub release (the app itself never downloads it),
         applies the theme like the APPLY THEME button does, loads every clock style, opens the
         wallpaper picker and lets it list the wallpapers
      4. changes the wallpaper and checks that the clock's own script picks a fitting text color
      5. fails on any error or warning in Rainmeter's log, then removes the theme again
    With -Shots, saves a picture of the screen at each step to that folder.
#>
param([string]$Path = 'ozzyhn.ps1', [string]$Shots = '')
$ErrorActionPreference = 'Stop'
trap { Write-Host ('::error::Theme test stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

$text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
$cut = $text.LastIndexOf('# ---- launch ----')
if ($cut -lt 0) { throw 'The "# ---- launch ----" marker was not found in the script' }
. ([scriptblock]::Create($text.Substring(0, $cut)))

$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$work = Join-Path $base ('oz-themes-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$Oz.DataDir = $work
$Oz.Journal = Join-Path $work 'journal.json'
$Oz.Settings = Join-Path $work 'settings.json'
$Oz.LogDir = Join-Path $work 'logs'
$Oz.LogFile = Join-Path $Oz.LogDir 'themes-test.log'
$Oz.JournalData = $null
if ($Shots) { New-Item -ItemType Directory -Path $Shots -Force | Out-Null }
Initialize-OzSpanish $Oz.SpanishPairs
$Oz.Lang = 'en'

$script:Problems = New-Object System.Collections.Generic.List[string]
function Fail([string]$Msg) { $script:Problems.Add($Msg); Write-Host "::error::$Msg" }
function Pass([string]$Msg) { Write-Host "PASS  $Msg" -ForegroundColor Green }
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if ($Shots) { Add-Type -Namespace OzTest -Name Win -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int c);' }
function Save-Screen([string]$Name) {
    if (-not $Shots) { return }
    # The runner's console sits over the desktop: minimize it so the skins are in the picture
    foreach ($p in @(Get-Process | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.ProcessName -notin 'explorer', 'Rainmeter' })) { [void][OzTest.Win]::ShowWindow($p.MainWindowHandle, 6) }
    Start-Sleep -Milliseconds 700
    $b =[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size) } catch { Write-Host "Screenshot failed: $($_.Exception.Message)" }
    $g.Dispose()
    $bmp.Save((Join-Path $Shots "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$Oz.Sys = Get-OzSystemInfo
Pass "hardware scan: $($Oz.Sys.Form), battery: $($Oz.Sys.Battery.Present)"

# ---------- 1. skin files for every combination ----------
$n = 0
foreach ($lang in 'en', 'es') {
    $Oz.Lang = $lang
    foreach ($look in $Oz.ThemeLooks.Keys) {
        foreach ($i in 0..($Oz.ThemeStyles.Count - 1)) {
            $cfg = Get-OzThemeDefaults
            $cfg.Look = $look
            $cfg.Style = $Oz.ThemeStyles[$i]
            $cfg.Pos = $Oz.ThemePositions[($i * 2 + $n) % 9]
            $cfg.Scale = @(75, 100, 125, 150, 200)[$i]
            $cfg.Hour24 = ($i % 2 -eq 0)
            $cfg.DateFmt = $i % $Oz.ThemeDateFormats.Count
            $files = New-OzThemeFiles -Cfg $cfg -InkSlot 1
            foreach ($k in $files.Keys) {
                $t = $files[$k].Text
                if ($t -match '\{\{') { Fail "$k ($look, $($cfg.Style), $lang): a size placeholder was left in the file" }
                if (-not $files[$k].Unicode -and $t -match '[^\x09\x0A\x0D\x20-\x7E]') { Fail "$k is written as ASCII but holds other characters" }
            }
            $n++
        }
    }
}
$Oz.Lang = 'en'
if (-not $script:Problems.Count) { Pass "skin files built for $n combinations of look, style, position, size and language" }
# Three screens (made up: this machine has one): the clock on screen 2, the bar on every screen,
# the dock on screen 3, only some bar items, large dock icons, solid backgrounds
$fake = @(
    [pscustomobject]@{ N = 1; Primary = $true; X = 0; Y = 0; W = 1920; H = 1080; WX = 0; WY = 0; WW = 1920; WH = 1040 }
    [pscustomobject]@{ N = 2; Primary = $false; X = 1920; Y = 0; W = 2560; H = 1440; WX = 1920; WY = 0; WW = 2560; WH = 1440 }
    [pscustomobject]@{ N = 3; Primary = $false; X = -1280; Y = 0; W = 1280; H = 1024; WX = -1280; WY = 0; WW = 1280; WH = 1024 })
$cfg = Get-OzThemeDefaults
$cfg.ScreenClock = '2'; $cfg.ScreenBar = 'all'; $cfg.ScreenDock = '3'
$cfg.BarItems = @('Cpu', 'Vol'); $cfg.DockSize = 'L'; $cfg.BgStyle = 'Solid'; $cfg.Scale = 100
$files = New-OzThemeFiles -Cfg $cfg -InkSlot 1 -Screens $fake
$set = $files['@Resources\Settings.inc'].Text
$copies = @(Get-OzThemeCopies $cfg $fake | ForEach-Object { $_.Config })
$want = 'OZZYHN\Clock', 'OZZYHN\Bar', 'OZZYHN\Bar2', 'OZZYHN\Bar3', 'OZZYHN\Dock'
if (($copies -join ',') -eq ($want -join ',')) { Pass "three screens: one clock, a bar on each screen, one dock ($($copies -join ', '))" } else { Fail "three screens: copies are $($copies -join ', ')" }
$checks = [ordered]@{
    'the clock is placed on screen 2'           = ($set -match 'PosX=\(#WORKAREAX@2#' -and $set -match 'PosY=\(#WORKAREAY@2#')
    'the first bar is on the main screen'       = ($files['Bar\Bar.ini'].Text -match 'BarCX=50%' -and $files['Bar\Bar.ini'].Text -match 'BarSW=#SCREENAREAWIDTH#')
    'the second bar is on screen 2'             = ($files['Bar2\Bar.ini'].Text -match 'BarSW=#SCREENAREAWIDTH@2#' -and $files['Bar2\Bar.ini'].Text -match 'BarY=\(#WORKAREAY@2#')
    'the third bar is on screen 3'              = ($files['Bar3\Bar.ini'].Text -match 'BarCX=\(#SCREENAREAX@3#\+#SCREENAREAWIDTH@3#/2\)')
    'the dock is on screen 3'                   = ($files['Dock\Dock.ini'].Text -match '#WORKAREAX@3#' -and $files['Dock\Dock.ini'].Text -match '#WORKAREAHEIGHT@3#')
    'the bar shows only CPU and volume'         = ($set -match 'ShowCpu=1' -and $set -match 'ShowVol=1' -and $set -match 'NoDate=1' -and $set -match 'NoRam=1' -and $set -match 'NoNet=1' -and $set -match 'NoBat=1')
    'large dock icons'                          = ($files['Dock\Dock.ini'].Text -match '\bW=56\b')
    'solid backgrounds'                         = ($set -match 'PillBg=\d+,\d+,\d+,250')
    'the picker opens under the main bar'       = ($set -match 'WallsX=50%')
}
foreach ($k in $checks.Keys) { if ($checks[$k]) { Pass "three screens: $k" } else { Fail "three screens: $k" } }
$cfg.ScreenClock = '7'
if ((Get-OzThemeCopies $cfg $fake | Where-Object Part -EQ 'Clock').At -eq '') { Pass 'a screen that is not connected falls back to the main screen' } else { Fail 'screen 7 (not connected) did not fall back to the main screen' }
foreach ($k in $files.Keys) {
    if ($files[$k].Text -match '\{\{') { Fail "$k (three screens): a size placeholder was left in the file" }
    if (-not $files[$k].Unicode -and $files[$k].Text -match '[^\x09\x0A\x0D\x20-\x7E]') { Fail "$k (three screens) is written as ASCII but holds other characters" }
}

# Windows set to a comma-decimal region (Spanish, German...) must write the same skin files
$cfg = Get-OzThemeDefaults
$cfg.Scale = 125
$ref = New-OzThemeFiles -Cfg $cfg -InkSlot 1
$old = [Threading.Thread]::CurrentThread.CurrentCulture
$comma = & { [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('es-ES'); try { New-OzThemeFiles -Cfg $cfg -InkSlot 1 } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $old } }
$diff = @($ref.Keys | Where-Object { $ref[$_].Text -ne $comma[$_].Text })
if ($diff.Count) { Fail "skin files change with the Windows region: $($diff -join ', ')" } else { Pass 'skin files are the same with a comma-decimal Windows region' }

# ---------- 2. wallpapers ----------
$art = Join-Path $work 'Pictures\OZZYHN Wallpapers'
$made = @(New-OzWallpaperArt -Folder $art -Width 1600 -Height 900)
if ($made.Count -eq 6 -and -not @($made | Where-Object { -not (Test-Path -LiteralPath $_) }).Count) { Pass "6 wallpapers drawn" } else { Fail "Expected 6 wallpapers, got $($made.Count)" }
if ($Shots) {
    foreach ($m in $made) {
        $img = [System.Drawing.Image]::FromFile($m)
        $sm = New-Object System.Drawing.Bitmap 480, 270
        $g = [System.Drawing.Graphics]::FromImage($sm); $g.DrawImage($img, 0, 0, 480, 270); $g.Dispose(); $img.Dispose()
        $sm.Save((Join-Path $Shots ('wallpaper-' + [IO.Path]::GetFileNameWithoutExtension($m) + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
        $sm.Dispose()
    }
}
# Not installed yet: the app must say so and refuse to apply
$rm = Get-OzRainmeter
if (-not $rm.Installed) {
    $refused = $false
    try { Install-OzTheme (Get-OzThemeDefaults) } catch { $refused = $true }
    if ($refused) { Pass 'without Rainmeter, APPLY THEME refuses with a message' } else { Fail 'APPLY THEME did not refuse without Rainmeter' }
}

# ---------- 3. Rainmeter (official release, test machine only) ----------
$setup = Join-Path $work 'Rainmeter-setup.exe'
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri 'https://github.com/rainmeter/rainmeter/releases/download/v4.5.23.3836/Rainmeter-4.5.23.exe' -OutFile $setup -UseBasicParsing
$rmData = Join-Path $env:APPDATA 'Rainmeter'
New-Item -ItemType Directory -Path $rmData -Force | Out-Null
# Start with logging on and no sample skins
[IO.File]::WriteAllText((Join-Path $rmData 'Rainmeter.ini'), "[Rainmeter]`r`nLogging=1`r`n", [Text.Encoding]::Unicode)
[IO.File]::WriteAllText((Join-Path $rmData 'Rainmeter.log'), '')
Start-Process -FilePath $setup -ArgumentList '/S' -Wait
Start-Sleep -Seconds 2
Get-Process -Name Rainmeter -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$rm = Get-OzRainmeter
if ($rm.Installed) { Pass "Rainmeter $($rm.Version) found at $($rm.Exe), skins in $($rm.SkinPath)" } else { throw 'Rainmeter was not found after installing it' }

Add-Type -Namespace OzTest -Name Wall -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern bool SystemParametersInfo(int a, int b, string c, int d);'
function Set-TestWallpaper([string]$File) { [void][OzTest.Wall]::SystemParametersInfo(20, 0, $File, 3) }
Set-TestWallpaper ($made | Where-Object { $_ -match 'hex-field' } | Select-Object -First 1)

# ---------- 4. apply the theme like APPLY THEME ----------
$cfg = Get-OzThemeDefaults
$cfg.WallFolders = @($art)
$cfg.Style = 'Horizon'
$cfg.Scale = 100
try { Install-OzTheme $cfg }
catch {
    if ($_.Exception.Message -notmatch 'start') { throw }
    # A test machine may have no desktop shell to start Rainmeter as the user: start it directly and retry
    Write-Host "::warning::$($_.Exception.Message) Starting Rainmeter directly for the test."
    Start-Process -FilePath $rm.Exe
    Start-Sleep -Seconds 6
    Install-OzTheme $cfg
}
Start-Sleep -Seconds 6
$rm = Get-OzRainmeter
foreach ($c in 'OZZYHN\Clock', 'OZZYHN\Bar', 'OZZYHN\Dock') { if ($rm.Active.ContainsKey($c)) { Pass "$c is loaded" } else { Fail "$c is not loaded" } }
if ((Get-OzActiveClockStyle $rm) -eq 'Horizon') { Pass 'clock style read back from Rainmeter.ini: Horizon' } else { Fail "clock style read back: $(Get-OzActiveClockStyle $rm)" }
$root = Join-Path $rm.SkinPath 'OZZYHN'
$lnk = @(Get-ChildItem -LiteralPath (Join-Path $root '@Resources\Dock\Apps') -Filter '*.lnk')
if ($lnk.Count -ge 1) { Pass "dock shortcuts: $($lnk.Count)" } else { Fail 'no dock shortcuts were made' }
Save-Screen 'theme-horizon'
foreach ($style in 'Blade', 'Stack', 'Pulse', 'Minimal') {
    Send-OzRainmeterBang $rm '!ActivateConfig' @('OZZYHN\Clock', "$style.ini")
    Start-Sleep -Seconds 3
    Save-Screen ('theme-' + $style.ToLower())
}
Send-OzRainmeterBang $rm '!ActivateConfig' @('OZZYHN\Clock', 'Horizon.ini')

# ---------- 5. wallpaper picker ----------
Send-OzRainmeterBang $rm '!ActivateConfig' @('OZZYHN\Walls', 'Walls.ini')
$index = Join-Path $root '@Resources\Walls\Index.inc'
$count = -1
for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1
    $t = [IO.File]::ReadAllText($index)
    if ($t -match 'NeedIndex=0' -and $t -match 'WallCount=(\d+)') { $count = [int]$Matches[1]; break }
}
if ($count -eq 6) { Pass 'the picker listed the 6 wallpapers' } else { Fail "the picker listed $count wallpapers (expected 6)" }
Start-Sleep -Seconds 3
Save-Screen 'theme-picker'
Send-OzRainmeterBang $rm '!CommandMeasure' @('mWalls', 'Move(1)', 'OZZYHN\Walls')
Send-OzRainmeterBang $rm '!CommandMeasure' @('mWalls', "SetFilter('D')", 'OZZYHN\Walls')
Start-Sleep -Seconds 2
Save-Screen 'theme-picker-dark'
Send-OzRainmeterBang $rm '!DeactivateConfig' @('OZZYHN\Walls')

# ---------- 6. the clock follows the wallpaper ----------
$state = Join-Path $root '@Resources\State.inc'
function Wait-InkSlot([int]$Want) {
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 1
        if ([IO.File]::ReadAllText($state) -match 'InkSlot=(\d)') { if ([int]$Matches[1] -eq $Want) { return $Want } }
    }
    if ([IO.File]::ReadAllText($state) -match 'InkSlot=(\d)') { return [int]$Matches[1] }
    -1
}
Set-TestWallpaper ($made | Where-Object { $_ -match 'dunes-light' } | Select-Object -First 1)
$got = Wait-InkSlot 0
if ($got -eq 0) { Pass 'light wallpaper: the clock switched to the dark text color' } else { Fail "light wallpaper: InkSlot is $got, expected 0" }
Save-Screen 'theme-light-wallpaper'
Set-TestWallpaper ($made | Where-Object { $_ -match 'dunes-night' } | Select-Object -First 1)
$got = Wait-InkSlot 2
if ($got -eq 2) { Pass 'dark wallpaper: the clock switched to the light text color' } else { Fail "dark wallpaper: InkSlot is $got, expected 2" }
Save-Screen 'theme-dark-wallpaper'

# Spanish skins and a second apply over the first (refresh path, no reload warnings)
$Oz.Lang = 'es'
$cfg.Look = 'neon'; $cfg.Pos = 'BR'; $cfg.Style = 'Blade'
Install-OzTheme $cfg
Start-Sleep -Seconds 5
Save-Screen 'theme-es-neon-blade'
$Oz.Lang = 'en'

# This screen picked by its number (the way a second screen is picked): Rainmeter's own variables
# for that screen (#WORKAREAX@1#...) must work and put every skin where "main screen" put it
function Get-RmPos([string]$Config) {
    $sec = ''; $x = $null; $y = $null
    foreach ($l in [IO.File]::ReadAllLines((Join-Path $rmData 'Rainmeter.ini'))) {
        if ($l -match '^\s*\[(.+)\]\s*$') { $sec = $Matches[1]; continue }
        if ($sec -eq $Config -and $l -match '^\s*WindowX\s*=\s*(.*)$') { $x = $Matches[1].Trim() }
        if ($sec -eq $Config -and $l -match '^\s*WindowY\s*=\s*(.*)$') { $y = $Matches[1].Trim() }
    }
    if ($null -ne $x) { "$x / $y" }
}
$before = @{}
foreach ($c in 'OZZYHN\Clock', 'OZZYHN\Bar', 'OZZYHN\Dock') { $before[$c] = Get-RmPos $c }
$here = @(Get-OzScreens)
Pass "screens on this machine: $(@($here | ForEach-Object { '{0} ({1}x{2}{3})' -f $_.N, $_.W, $_.H, $(if ($_.Primary) { ', main' }) }) -join '; ')"
$n1 = [string]($here | Where-Object Primary | Select-Object -First 1).N
$cfg.ScreenClock = $n1; $cfg.ScreenBar = 'all'; $cfg.ScreenDock = $n1
$cfg.BarItems = @('Date', 'Cpu', 'Net'); $cfg.DockSize = 'S'; $cfg.BgStyle = 'Glass'
Install-OzTheme $cfg
Start-Sleep -Seconds 5
Save-Screen 'theme-screen-by-number'
$rm = Get-OzRainmeter
foreach ($c in 'OZZYHN\Clock', 'OZZYHN\Bar', 'OZZYHN\Dock') { if ($rm.Active.ContainsKey($c)) { Pass "screen $n1 by number: $c is loaded" } else { Fail "screen $n1 by number: $c is not loaded" } }
$set = [IO.File]::ReadAllText((Join-Path $root '@Resources\Settings.inc'))
if ($set -match "#WORKAREAX@$n1#") { Pass "screen $n1 by number: the files use #WORKAREAX@$n1#" } else { Fail "screen $n1 by number: Settings.inc does not use #WORKAREAX@$n1#" }
foreach ($c in 'OZZYHN\Clock', 'OZZYHN\Bar', 'OZZYHN\Dock') {
    $after = Get-RmPos $c
    if ($null -eq $before[$c] -or $null -eq $after) { Write-Host "::notice::$c position not in Rainmeter.ini ($($before[$c]) -> $after)"; continue }
    if ($before[$c] -eq $after) { Pass "screen $n1 by number: $c at the same place as on the main screen ($after)" } else { Fail "screen $n1 by number: $c moved from $($before[$c]) to $after" }
}
$cfg.ScreenClock = 'main'; $cfg.ScreenBar = 'main'; $cfg.ScreenDock = 'main'; $cfg.BarItems = @($Oz.ThemeBarItems); $cfg.DockSize = 'M'; $cfg.BgStyle = 'Normal'

# ---------- 7. Rainmeter's log ----------
$log = @(Get-Content -LiteralPath (Join-Path $rmData 'Rainmeter.log') -ErrorAction SilentlyContinue)
$bad = @($log | Where-Object { $_ -match '^(ERRO|WARN)' -and $_ -notmatch 'Status file|update' })
foreach ($l in $bad) { Fail "Rainmeter log: $l" }
if ($log.Count -and -not $bad.Count) { Pass "Rainmeter log has no errors or warnings ($($log.Count) lines)" }
elseif (-not $log.Count) { Fail 'Rainmeter wrote no log' }
Write-Host '--- Rainmeter log (last 40 lines) ---'
$log | Select-Object -Last 40 | ForEach-Object { Write-Host $_ }

# ---------- 8. remove ----------
Remove-OzTheme
Start-Sleep -Seconds 2
$rm = Get-OzRainmeter
if (Test-Path -LiteralPath $root) { Fail 'the OZZYHN skins folder is still there after REMOVE THEME' } else { Pass 'REMOVE THEME deleted the OZZYHN skins folder' }
if (@($rm.Active.Keys).Count) { Fail ('still loaded after REMOVE THEME: ' + (@($rm.Active.Keys) -join ', ')) } else { Pass 'no OZZYHN skin is loaded after REMOVE THEME' }
if (Test-Path -LiteralPath $art) { Pass 'your wallpaper folder was left alone' } else { Fail 'the wallpaper folder was deleted' }
Save-Screen 'theme-removed'
Send-OzRainmeterBang $rm '!Quit'

$errLines = @(Get-Content -LiteralPath $Oz.LogFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '\[ERR ?\]|\[WARN\]' })
foreach ($l in $errLines) { Fail "App logged: $l" }
if ($script:Problems.Count) { Write-Host "$($script:Problems.Count) problem(s)"; exit 1 }
Write-Host 'Theme test passed' -ForegroundColor Green
