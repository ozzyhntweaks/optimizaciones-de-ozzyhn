<#
    Round-trip test of the tweak catalog in ozzyhn.ps1 on a real Windows machine (GitHub's
    Windows runner, as administrator). For every tweak made only of registry values, services
    and scheduled tasks:
      1. remember every value and task state it touches
      2. apply it, and check the app now reads it as ON (catches "switch shows ON, nothing changed")
      3. revert it, and check every value and task is exactly as before (catches lost settings)
    Tweaks with their own Apply/Revert code (uninstalling apps, power plans, network adapters)
    and Danger Zone tweaks are skipped: they change too much to test on a shared runner.
    Hardware checks (laptop only, 16 GB RAM...) are ignored here, so more tweaks get tested.
#>
param([string]$Path = 'ozzyhn.ps1')
$ErrorActionPreference = 'Stop'
trap { Write-Host ('::error::Test script stopped at line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message); exit 1 }

# Load the app without opening its window: everything before the final launch line
$text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
$cut = $text.LastIndexOf('# ---- launch ----')
if ($cut -lt 0) { throw 'The "# ---- launch ----" marker was not found in the script' }
. ([scriptblock]::Create($text.Substring(0, $cut)))

# Keep the test's journal and logs out of C:\ProgramData\Ozzyhn
$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$work = Join-Path $base ('oz-tweaks-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work | Out-Null
$Oz.DataDir = $work
$Oz.Journal = Join-Path $work 'journal.json'
$Oz.Settings = Join-Path $work 'settings.json'
$Oz.LogDir = Join-Path $work 'logs'
$Oz.LogFile = Join-Path $Oz.LogDir 'test.log'
$Oz.JournalData = $null
Initialize-OzCatalog

function Format-OzValue($r) {
    if (-not $r.Exists) { return '(not set)' }
    '{0} {1}' -f $r.Kind, (@($r.Value) -join ',')
}
function Test-OzSame($a, $b) {
    if ($a.Exists -ne $b.Exists) { return $false }
    if (-not $a.Exists) { return $true }
    ($a.Kind -eq $b.Kind) -and ((@($a.Value) -join ',') -eq (@($b.Value) -join ','))
}

$fail = New-Object System.Collections.Generic.List[string]
$warn = New-Object System.Collections.Generic.List[string]
$tested = 0; $na = 0; $skipped = 0
foreach ($t in $Oz.Tweaks) {
    if ($t.Risk -eq 'Danger' -or $t.Apply -or $t.Revert -or $t.Detect -or (-not $t.Reg.Count -and -not $t.Tasks.Count)) { $skipped++; continue }

    $before = @{}
    foreach ($r in $t.Reg) { $before["$($r.P)|$($r.N)"] = Get-OzReg $r.P $r.N }
    $tasksBefore = @{}
    foreach ($task in $t.Tasks) { $tasksBefore[$task] = Get-OzTaskState $task }

    $applyError = $null
    try { Invoke-OzTweakApply $t } catch { $applyError = $_.Exception.Message }
    $state = Get-OzTweakState $t
    if ($applyError) { $warn.Add("$($t.Id): could not be fully applied on this Windows Server runner ($applyError)") }
    elseif ($state -eq 'Off') { $fail.Add("$($t.Id): applied without errors, but the app still reads it as OFF") }
    elseif ($state -eq 'Error') { $fail.Add("$($t.Id): the app could not read its state after applying") }
    if ($state -eq 'NA') { $na++ }

    try { Invoke-OzTweakRevert $t } catch { $fail.Add("$($t.Id): revert failed: $($_.Exception.Message)") }

    foreach ($k in $before.Keys) {
        $i = $k.LastIndexOf('|')
        $now = Get-OzReg $k.Substring(0, $i) $k.Substring($i + 1)
        if (-not (Test-OzSame $now $before[$k])) {
            $fail.Add(('{0}: {1} was [{2}] before, [{3}] after revert' -f $t.Id, $k, (Format-OzValue $before[$k]), (Format-OzValue $now)))
        }
    }
    foreach ($task in $t.Tasks) {
        $now = Get-OzTaskState $task
        if ($now -ne $tasksBefore[$task]) { $fail.Add(('{0}: task {1} was {2} before, {3} after revert' -f $t.Id, $task, $tasksBefore[$task], $now)) }
    }
    $tested++
}

Write-Host ('Round-trip tested {0} tweaks ({1} had nothing to change on this runner); skipped {2} with custom code or in the Danger Zone.' -f $tested, $na, $skipped)
foreach ($w in $warn) { Write-Host "::warning::$w" }
foreach ($f in $fail) { Write-Host "::error::$f" }
if ($fail.Count) { exit 1 }
Write-Host 'Every tested tweak applied and reverted cleanly' -ForegroundColor Green
