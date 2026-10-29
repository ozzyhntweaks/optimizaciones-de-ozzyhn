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
function Save-Screen([string]$Name) {
    if (-not $Shots) { return }
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
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
