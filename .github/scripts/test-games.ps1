<#
    Tests the Games page logic with settings files whose contents are known: reading Apex,
    Fortnite and CS2 files, comparing them with the recommendations, finding Steam and Epic
    games, picking launch options for laptops and desktops, and scanning this PC without errors.
#>
param([string]$Path = 'ozzyhn.ps1')
$ErrorActionPreference = 'Stop'
trap { Write-Host ('::error::Game test stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

$text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
$cut = $text.LastIndexOf('# ---- launch ----')
. ([scriptblock]::Create($text.Substring(0, $cut)))
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Initialize-OzSpanish $Oz.SpanishPairs

$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$work = Join-Path $base ('oz-games-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$script:Failures = 0
function Check([string]$Name, [bool]$Ok) {
    if ($Ok) { Write-Host "PASS  $Name" -ForegroundColor Green } else { Write-Host "::error::FAIL  $Name"; $script:Failures++ }
}
function New-File([string]$Name, [string]$Content) {
    $p = Join-Path $work $Name
    New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
    [IO.File]::WriteAllText($p, $Content.Replace("`n", "`r`n"))
    $p
}
function Get-Review($Game, [string]$File) {
    $m = Read-OzGameConfig $File $Game.Format
    $h = @{}
    foreach ($c in $Game.Checks) { $r = Test-OzGameCheck $c $m; $h[$r.Name] = $r }
    $h
}
function Set-TestPc([string]$Vendor, [bool]$Laptop, [string]$Res) {
    $Oz.Sys = [pscustomobject]@{
        IsLaptop = $Laptop
        GPU = [pscustomobject]@{ Primary = [pscustomobject]@{ Vendor = $Vendor; VramGB = 8; Resolution = $Res } }
    }
}

# ---------- launch options and menus follow the PC ----------
Set-TestPc 'NVIDIA' $true '1920x1080 @ 144 Hz'
$cat = @(Get-OzGameCatalog)
Check 'catalog has 6 games' ($cat.Count -eq 6)
Check 'refresh rate read from the scan' ((Get-OzRefreshRate) -eq 144)
$apex = $cat | Where-Object Id -EQ 'apex'
Check 'laptop: Apex has uncapped and 144 Hz launch options' ($apex.LaunchArgs.Count -eq 2 -and $apex.LaunchArgs[1].Args -eq '-dev +fps_max 144')
Check 'laptop: the capped Apex option is the recommended one' ($apex.LaunchArgs[1].Rec -and -not $apex.LaunchArgs[0].Rec)
Check 'NVIDIA: Apex menu lists Reflex' (@($apex.Menu | Where-Object { $_[0] -eq 'NVIDIA Reflex' }).Count -eq 1)
Check '8 GB VRAM: Apex texture budget High' (@($apex.Menu | Where-Object { $_[0] -eq 'Texture Streaming Budget' -and $_[1] -eq 'High (4GB VRAM)' }).Count -eq 1)
$fn = $cat | Where-Object Id -EQ 'fortnite'
Check 'laptop: Fortnite frame limit 144 FPS' (@($fn.Menu | Where-Object { $_[0] -eq 'Frame Rate Limit' -and $_[1] -eq '144 FPS' }).Count -eq 1)
$cs = $cat | Where-Object Id -EQ 'cs2'
Check 'NVIDIA: CS2 checks Reflex in the file' (@($cs.Checks | Where-Object { $_.Name -eq 'NVIDIA Reflex' }).Count -eq 1)
foreach ($g in $cat) {
    Check "$($g.Id): every menu line has a setting and a value" (-not @($g.Menu | Where-Object { $_.Count -ne 2 -or -not $_[0] -or -not $_[1] }).Count)
    foreach ($l in $g.Launchers) { Check "$($g.Id): knows where $l keeps launch options" ([bool]$g.LaunchWhere[$l]) }
}

Set-TestPc 'AMD' $false ''
$cat = @(Get-OzGameCatalog)
$apex = $cat | Where-Object Id -EQ 'apex'
$cs = $cat | Where-Object Id -EQ 'cs2'
Check 'desktop, unknown Hz: one uncapped Apex option, recommended' ($apex.LaunchArgs.Count -eq 1 -and $apex.LaunchArgs[0].Rec)
Check 'AMD: no NVIDIA lines in any menu' (-not @($cat | ForEach-Object { $_.Menu } | Where-Object { $_[0] -like '*NVIDIA*' }).Count)
Check 'AMD: CS2 does not check Reflex' (-not @($cs.Checks | Where-Object { $_.Name -eq 'NVIDIA Reflex' }).Count)

# ---------- Apex videoconfig.txt ----------
$f = New-File 'apex1\videoconfig.txt' @'
"VideoConfig"
{
	"setting.cl_gib_allow"		"0"
	"setting.mat_vsync_mode"		"1"
	"setting.fullscreen"		"1"
	"setting.nowindowborder"		"0"
	"setting.dvs_enable"		"0"
	"setting.ssao_enabled"		"1"
	"setting.volumetric_lighting"		"0"
	"setting.configversion"		"7"
}
'@
$r = Get-Review $apex $f
Check 'Apex: full screen is OK' ($r['Display mode'].Ok -eq $true -and $r['Display mode'].Current -eq 'Full Screen')
Check 'Apex: V-Sync on is flagged' ($r['V-Sync'].Ok -eq $false -and $r['V-Sync'].Current -eq 'Double Buffered')
Check 'Apex: adaptive resolution off is OK' ($r['Adaptive resolution'].Ok -eq $true)
Check 'Apex: ambient occlusion on is flagged' ($r['Ambient occlusion'].Ok -eq $false)
Check 'Apex: volumetric lighting off is OK' ($r['Volumetric lighting'].Ok -eq $true)
$f = New-File 'apex2\videoconfig.txt' @'
"VideoConfig"
{
	"setting.mat_vsync_mod"		"0"
	"setting.fullscreen"		"0"
	"setting.ssao_quality"		"0"
}
'@
$r = Get-Review $apex $f
Check 'Apex: newer V-Sync key name is read' ($r['V-Sync'].Ok -eq $true)
Check 'Apex: borderless is flagged' ($r['Display mode'].Ok -eq $false -and $r['Display mode'].Current -eq 'Windowed / Borderless')
Check 'Apex: newer ambient occlusion key is read' ($r['Ambient occlusion'].Ok -eq $true)
Check 'Apex: a setting missing from the file is not counted' ($null -eq $r['Volumetric lighting'].Ok)

# ---------- Fortnite GameUserSettings.ini ----------
$f = New-File 'fn1\GameUserSettings.ini' @'
[/Script/FortniteGame.FortGameUserSettings]
bUseVSync=False
FrameRateLimit=0.000000
FullscreenMode=0
PreferredFullscreenMode=0
bMotionBlur=False
bRayTracing=False

[D3DRHIPreference]
PreferredRHI=dx12
PreferredFeatureLevel=es31

[ScalabilityGroups]
sg.ResolutionQuality=100.000000
'@
$fn = $cat | Where-Object Id -EQ 'fortnite'
$r = Get-Review $fn $f
Check 'Fortnite: Performance mode is OK' ($r['Rendering mode'].Ok -eq $true -and $r['Rendering mode'].Current -eq 'Performance')
Check 'Fortnite: every setting OK' (-not @($r.Values | Where-Object { $_.Ok -ne $true }).Count)
$f = New-File 'fn2\GameUserSettings.ini' @'
[/Script/FortniteGame.FortGameUserSettings]
bUseVSync=True
FullscreenMode=1

[D3DRHIPreference]
PreferredRHI=dx12
'@
$r = Get-Review $fn $f
Check 'Fortnite: DirectX mode is flagged' ($r['Rendering mode'].Ok -eq $false -and $r['Rendering mode'].Current -eq 'DirectX 11 / 12')
Check 'Fortnite: windowed fullscreen is flagged' ($r['Window mode'].Ok -eq $false -and $r['Window mode'].Current -eq 'Windowed Fullscreen')
Check 'Fortnite: V-Sync on is flagged' ($r['V-Sync'].Ok -eq $false)
Check 'Fortnite: missing motion blur is not counted' ($null -eq $r['Motion blur'].Ok)

# ---------- CS2 cs2_video.txt ----------
Set-TestPc 'NVIDIA' $false '2560x1440 @ 240 Hz'
$cs = @(Get-OzGameCatalog) | Where-Object Id -EQ 'cs2'
$f = New-File 'cs2\cs2_video.txt' @'
"video.cfg"
{
"setting.defaultres" "1440"
"setting.fullscreen" "1"
"setting.mat_vsync" "1"
"setting.r_low_latency" "2"
"Version" "15"
}
'@
$r = Get-Review $cs $f
Check 'CS2: fullscreen is OK' ($r['Display mode'].Ok -eq $true)
Check 'CS2: vertical sync on is flagged' ($r['Vertical sync'].Ok -eq $false)
Check 'CS2: Reflex + Boost counts as on' ($r['NVIDIA Reflex'].Ok -eq $true -and $r['NVIDIA Reflex'].Current -eq 'Enabled + Boost')

# ---------- finding games ----------
$lib = Join-Path $work 'SteamLibrary'
New-File 'SteamLibrary\steamapps\appmanifest_1172470.acf' "`"AppState`"`n{`n`t`"appid`"`t`t`"1172470`"`n`t`"installdir`"`t`t`"Apex Legends`"`n}" | Out-Null
New-Item -ItemType Directory -Path (Join-Path $lib 'steamapps\common\Apex Legends') -Force | Out-Null
$steam = [pscustomobject]@{ Root = $lib; Libraries = @($lib) }
Check 'Steam: finds a game from its appmanifest' ((Find-OzSteamGame $steam 1172470) -eq (Join-Path $lib 'steamapps\common\Apex Legends'))
Check 'Steam: a game that is not installed is not found' (-not (Find-OzSteamGame $steam 730))
$vdfRoot = Join-Path $work 'Steam'
New-File 'Steam\steamapps\libraryfolders.vdf' ("`"libraryfolders`"`n{`n`t`"0`"`n`t{`n`t`t`"path`"`t`t`"" + $lib.Replace('\', '\\') + "`"`n`t}`n}") | Out-Null
$found = foreach ($line in (Read-OzTextShared (Join-Path $vdfRoot 'steamapps\libraryfolders.vdf') -Lines)) { if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $Matches[1].Replace('\\', '\') } }
Check 'Steam: library path in libraryfolders.vdf is read' (@($found) -contains $lib)
$saved = $env:ProgramData
try {
    $env:ProgramData = Join-Path $work 'PD'
    $fnDir = Join-Path $work 'Epic\Fortnite'
    New-Item -ItemType Directory -Path $fnDir -Force | Out-Null
    New-File 'PD\Epic\EpicGamesLauncher\Data\Manifests\ABC.item' ('{{"DisplayName":"Fortnite","AppName":"Fortnite","InstallLocation":"{0}","LaunchExecutable":"FortniteGame/Binaries/Win64/FortniteLauncher.exe"}}' -f $fnDir.Replace('\', '\\')) | Out-Null
    $epic = @(Get-OzEpicGames)
    Check 'Epic: finds Fortnite from its manifest' ($epic.Count -eq 1 -and $epic[0].Location -eq $fnDir)
    $hit = Find-OzGame ($cat | Where-Object Id -EQ 'fortnite') @() $steam $epic
    Check 'Epic: Fortnite is reported as installed with Epic' ($hit -and $hit.Launcher -eq 'Epic')
} finally { $env:ProgramData = $saved }
$un = @([pscustomobject]@{ Key = 'Riot Game valorant.live'; Name = 'VALORANT'; Location = $work; Icon = ('"{0}",0' -f (Join-Path $env:SystemRoot 'explorer.exe')) })
$hit = Find-OzGame ($cat | Where-Object Id -EQ 'valorant') $un ([pscustomobject]@{ Root = $null; Libraries = @() }) @()
Check 'Riot: VALORANT found from the installed programs list' ($hit -and $hit.Launcher -eq 'Riot Client')
Check 'Icon file taken from DisplayIcon with quotes and index' ($hit.Icon -eq (Join-Path $env:SystemRoot 'explorer.exe'))
Check 'Icon image can be read' ([bool](Get-OzFileIcon $hit.Icon))
Check 'Missing icon file gives no image and no error' (-not (Get-OzFileIcon (Join-Path $work 'missing.exe')))

# ---------- this PC ----------
$Oz.Sys = $null
$scan = @(Get-OzGameScan)
Check 'Scanning this PC returns all 6 games without errors' ($scan.Count -eq 6)
Check 'Installed programs list can be read' (@(Get-OzUninstallEntries).Count -gt 0)

if ($script:Failures) { Write-Host "$($script:Failures) test(s) failed"; exit 1 }
Write-Host 'Game tests passed' -ForegroundColor Green
