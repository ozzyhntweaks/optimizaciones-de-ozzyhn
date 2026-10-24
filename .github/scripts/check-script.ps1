<#
    Checks ozzyhn.ps1 before it can be released. Runs on Windows PowerShell 5.1, the same
    PowerShell users run the app in (see .github/workflows/ci.yml).

      1. Plain ASCII, which keeps "irm ... | iex" working on Windows PowerShell 5.1
      2. No syntax errors, and the embedded XAML is well-formed
      3. Nothing that downloads or runs code from the internet, no Invoke-Expression and no
         Defender exclusions. The README promises "no downloads of other tools"; the app
         relaunching its own released file as administrator is a string handed to a new
         PowerShell, not a call in this script, so it does not trip this check.
      4. PSScriptAnalyzer: no errors and no findings from its security rules
#>
param([string]$Path = 'ozzyhn.ps1')
$ErrorActionPreference = 'Stop'
$Path = (Resolve-Path -LiteralPath $Path).Path
$fail = New-Object System.Collections.Generic.List[string]
$text = [IO.File]::ReadAllText($Path)

# 1. ASCII
$bad = [regex]::Matches($text, '[^\x09\x0A\x0D\x20-\x7E]')
foreach ($m in @($bad | Select-Object -First 5)) {
    $line = ($text.Substring(0, $m.Index) -split "`n").Count
    $fail.Add(('Non-ASCII character U+{0:X4} at line {1}' -f [int][char]$m.Value, $line))
}

# 2. Syntax and XAML
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
foreach ($e in $errors) { $fail.Add(('Syntax error at line {0}: {1}' -f $e.Extent.StartLineNumber, $e.Message)) }
$xaml = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Oz.Xaml' }, $true))
if (-not $xaml.Count) { $fail.Add('No $Oz.Xaml assignment found') }
foreach ($x in $xaml) {
    $s = $x.Right.Find({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
    try { [void]([xml]$s.Value) } catch { $fail.Add("The XAML is not well-formed: $($_.Exception.Message)") }
}

# 3. Downloads, Invoke-Expression, Defender exclusions
$blocked = 'Invoke-WebRequest', 'iwr', 'Invoke-RestMethod', 'irm', 'curl', 'wget', 'Start-BitsTransfer',
           'bitsadmin', 'certutil', 'mshta', 'Invoke-Expression', 'iex', 'Add-MpPreference'
foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    $name = [string]$c.GetCommandName()
    $short = $name -replace '\.exe$', ''
    $line = $c.Extent.StartLineNumber
    if ($short -in $blocked) { $fail.Add("Line ${line}: '$name' is not allowed (downloads or runs code, or adds an antivirus exclusion)") }
    if ($short -like '*-MpPreference' -and $c.Extent.Text -match '-Exclusion') { $fail.Add("Line ${line}: Defender exclusions are not allowed") }
    if ($short -eq 'New-Object' -and $c.Extent.Text -match 'WebClient|HttpClient|WebRequest|XMLHTTP|WinHttp') { $fail.Add("Line ${line}: web client objects are not allowed") }
}
foreach ($t in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst] -or $n -is [System.Management.Automation.Language.TypeConstraintAst] }, $true)) {
    if ($t.TypeName.FullName -match 'WebClient|HttpClient|WebRequest') { $fail.Add(('Line {0}: [{1}] is not allowed' -f $t.Extent.StartLineNumber, $t.TypeName.FullName)) }
}
foreach ($m in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)) {
    if ($m.Member.Extent.Text -match '^(Download\w*|OpenRead|GetStringAsync|GetByteArrayAsync|GetStreamAsync)$') {
        $fail.Add(('Line {0}: .{1}() is not allowed' -f $m.Extent.StartLineNumber, $m.Member.Extent.Text))
    }
}

# 4. Every English text shown in the app has a Spanish line (the EN | ES switch)
$pairsAst = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Oz.SpanishPairs' }, $true)) | Select-Object -First 1
if (-not $pairsAst) { $fail.Add('No $Oz.SpanishPairs block found') }
else {
    $es = @{}
    $pairsText = $pairsAst.Right.Find({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value
    $block = New-Object System.Collections.Generic.List[string]
    foreach ($raw in (($pairsText -replace "`r", '') -split "`n") + @('')) {
        $line = $raw.TrimEnd()
        if ($line) { $block.Add($line); continue }
        if ($block.Count -ge 2) { $es[$block[0].Replace('\n', "`n")] = $true }
        elseif ($block.Count -eq 1) { $fail.Add("Spanish block has an English line without a Spanish line: $($block[0])") }
        $block.Clear()
    }
    $needs = New-Object System.Collections.Generic.List[object]
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = [string]$c.GetCommandName()
        if ($name -cne 'T' -and $name -ne 'Invoke-OzSafe') { continue }
        if ($c.CommandElements.Count -lt 2) { continue }
        $arg = $c.CommandElements[1]
        if ($arg -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $needs.Add(@($arg.Value, $arg.Extent.StartLineNumber)) }
        elseif ($arg -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and -not $arg.NestedExpressions.Count) { $needs.Add(@($arg.Value, $arg.Extent.StartLineNumber)) }
    }
    # Fixed texts in the window that are swapped by Register-OzXamlTexts / Set-OzLanguage
    $keep = @('@ozzyhntweaks', 'github.com/ozzyhntweaks', 'EN', 'ES', 'English', ('Espa' + [char]0xF1 + 'ol'), 'CPU', 'GPU', 'RAM', 'DNS', 'OZ SCORE', 'OZZYHN TWEAKS', 'OZZYHN TWEAKS  //', '//  OZZYHN TWEAKS')
    $xns = 'http://schemas.microsoft.com/winfx/2006/xaml'
    foreach ($x in $xaml) {
        $doc = [xml]($x.Right.Find({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value)
        foreach ($node in $doc.SelectNodes('//*')) {
            $dyn = $false
            for ($p = $node; $p -is [System.Xml.XmlElement]; $p = $p.ParentNode) { if ($p.GetAttribute('Tag') -eq 'dyn') { $dyn = $true; break } }
            if ($dyn) { continue }
            $texts = @()
            if ($node.LocalName -eq 'TextBlock' -and -not $node.GetAttribute('Name', $xns) -and -not $node.SelectNodes('*').Count) { $texts += $node.GetAttribute('Text') }
            if ($node.LocalName -in 'Button', 'CheckBox', 'RadioButton', 'ToggleButton', 'Label') { $texts += $node.GetAttribute('Content') }
            $texts += $node.GetAttribute('ToolTip')
            foreach ($t in $texts) { if ($t -and -not $t.StartsWith('{')) { $needs.Add(@($t, 0)) } }
        }
    }
    foreach ($n in $needs) {
        $t = [string]$n[0]
        if ($t -notmatch '[A-Za-z]{2}' -or $keep -contains $t -or $es.ContainsKey($t)) { continue }
        $where = if ($n[1]) { "line $($n[1])" } else { 'XAML' }
        $fail.Add(("No Spanish line for '{0}' ({1}). Add it to the SPANISH block." -f $t, $where))
    }
}

# 5. PSScriptAnalyzer
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
    Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
}
Import-Module PSScriptAnalyzer
$securityRules = 'PSAvoidUsingInvokeExpression', 'PSAvoidUsingPlainTextForPassword', 'PSAvoidUsingConvertToSecureStringWithPlainText',
                 'PSAvoidUsingUsernameAndPasswordParams', 'PSAvoidUsingComputerNameHardcoded', 'PSAvoidUsingAllowUnencryptedAuthentication',
                 'PSAvoidUsingBrokenHashAlgorithms'
$findings = @(Invoke-ScriptAnalyzer -Path $Path)
foreach ($f in $findings) {
    if ([string]$f.Severity -in 'Error', 'ParseError' -or $f.RuleName -in $securityRules) {
        $fail.Add(('PSScriptAnalyzer {0} at line {1}: {2}' -f $f.RuleName, $f.Line, $f.Message))
    }
}
Write-Host ('PSScriptAnalyzer: {0} style notes (not blocking)' -f ($findings.Count - @($findings | Where-Object { [string]$_.Severity -in 'Error', 'ParseError' -or $_.RuleName -in $securityRules }).Count))

if ($fail.Count) {
    $fail | ForEach-Object { Write-Host "::error::FAIL  $_" }
    exit 1
}
Write-Host "All checks passed for $Path" -ForegroundColor Green
