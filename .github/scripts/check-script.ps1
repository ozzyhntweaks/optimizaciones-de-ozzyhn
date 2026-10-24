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

# 4. PSScriptAnalyzer
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
