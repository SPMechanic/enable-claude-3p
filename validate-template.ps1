# Validator: extracts the $pristine template from Enable-Claude3P.ps1 via AST
# and confirms it parses as valid JSON with the expected universal fields --
# including the three ANTHROPIC_DEFAULT_*_MODEL tier vars and the top-level
# `model` field (and that model is NOT the legacy "auto" alias).
#
# Run:  pwsh -NoProfile -File ./validate-template.ps1
#       powershell -NoProfile -File ./validate-template.ps1   (Windows PowerShell 5.1)
$ErrorActionPreference = 'Stop'
# Resolve the script path relative to this validator so it works from any CWD
# (the old hardcoded C:\CLAUDE\plugins\enable-claude-3p\... path no longer exists).
$scriptPath = Join-Path $PSScriptRoot 'Enable-Claude3P.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Host "SCRIPT NOT FOUND: $scriptPath"; exit 1
}
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errs)
if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host "PARSE ERR: $_" }; exit 1 }
$assign = $ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left.Extent.Text -eq '$pristine'
}, $true) | Select-Object -First 1
if (-not $assign) { Write-Host 'ASSIGN NOT FOUND'; exit 1 }
$val = & ([scriptblock]::Create($assign.Right.Extent.Text))

$pass = 0; $fail = 0
function Check($label, $got, $exp) {
    if ("$got" -eq "$exp") { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label -- got [$got] expected [$exp]" -ForegroundColor Red; $script:fail++ }
}

try {
    $o = $val | ConvertFrom-Json
    Write-Host 'JSON: VALID'
    Check 'env key count' (@($o.env.PSObject.Properties).Count) '12'
    Check 'GIT_BASH_PATH' ($o.env.CLAUDE_CODE_GIT_BASH_PATH) 'C:\Program Files\Git\bin\bash.exe'
    Check 'allow count' (@($o.permissions.allow).Count) '32'
    Check 'defaultMode' ($o.permissions.defaultMode) 'bypassPermissions'
    Check 'defaultShell' ($o.defaultShell) 'powershell'
    Check 'outputStyle' ($o.outputStyle) 'Concise'
    # Tier-mapping trio -- the actual gap that motivated this validator. If any
    # of these three are dropped from the pristine template, no other test
    # catches it (Ensure-SettingsEnvFields only runs on EXISTING files).
    Check 'SONNET tier var' ($o.env.ANTHROPIC_DEFAULT_SONNET_MODEL) 'claude-sonnet-5-5'
    Check 'HAIKU tier var' ($o.env.ANTHROPIC_DEFAULT_HAIKU_MODEL) 'claude-haiku-5-5'
    Check 'OPUS tier var' ($o.env.ANTHROPIC_DEFAULT_OPUS_MODEL) 'claude-opus-4.8'
    # Top-level model field: must be present, must be a real wire id, must NOT
    # be the legacy "auto" alias (auto is not a documented model value).
    $modelProp = $o.PSObject.Properties['model']
    Check 'model field present' ($null -ne $modelProp) 'True'
    Check 'model is not auto' ($o.model) 'claude-sonnet-5-5'
    Check 'enableWorkflows' ($o.enableWorkflows) 'True'
}
catch {
    Write-Host "JSON: INVALID -> $_"
    Write-Host '---RAW---'
    Write-Host $val
    exit 1
}
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Yellow'})
if ($fail -gt 0) { exit 1 } else { Write-Host 'TEMPLATE VALID' -ForegroundColor Green }
