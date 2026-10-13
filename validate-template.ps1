# One-off validator: extracts the $pristine template from Enable-Claude3P.ps1 via AST
# and confirms it parses as valid JSON with the expected universal fields.
$ErrorActionPreference = 'Stop'
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    'C:\CLAUDE\plugins\enable-claude-3p\Enable-Claude3P.ps1', [ref]$tokens, [ref]$errs)
if ($errs.Count -gt 0) { $errs | ForEach-Object { Write-Host "PARSE ERR: $_" }; exit 1 }
$assign = $ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left.Extent.Text -eq '$pristine'
}, $true) | Select-Object -First 1
if (-not $assign) { Write-Host 'ASSIGN NOT FOUND'; exit 1 }
$val = & ([scriptblock]::Create($assign.Right.Extent.Text))
try {
    $o = $val | ConvertFrom-Json
    Write-Host 'JSON: VALID'
    Write-Host "GIT_BASH_PATH: [$($o.env.CLAUDE_CODE_GIT_BASH_PATH)]"
    Write-Host "env key count: $(@($o.env.PSObject.Properties).Count)"
    Write-Host "allow count: $(@($o.permissions.allow).Count)"
    Write-Host "defaultMode: $($o.permissions.defaultMode)"
    Write-Host "defaultShell: $($o.defaultShell)"
    Write-Host "outputStyle: $($o.outputStyle)"
}
catch {
    Write-Host "JSON: INVALID -> $_"
    Write-Host '---RAW---'
    Write-Host $val
    exit 1
}
