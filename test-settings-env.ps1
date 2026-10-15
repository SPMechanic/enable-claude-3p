# Dedicated harness for Ensure-SettingsEnvFields: the function that rewrites an
# EXISTING settings.json to inject the model-mapping trio (ANTHROPIC_DEFAULT_*
# _MODEL) + the default `model` field + universal env defaults, WITHOUT corrupting
# whatever nested structures (plugins, marketplaces, permissions) the file carries.
#
# Matrix of shapes exercised (each in isolation, fresh temp file per case):
#   1. No file at all
#   2. Empty object  {}
#   3. Minimal working universal (env with the 5 defaults already present)
#   4. Complex -- nested enabledPlugins + extraKnownMarketplaces (real user shape)
#   5. Legacy "model":"auto" (the broken old template value)
#   6. Custom user model id (must be preserved)
#   7. Custom user tier var (must be preserved; only-if-absent for the rest)
#   8. Corrupt JSON (must return $false, file untouched)
#   9. env block absent entirely
#  10. env present but empty {}
#  11. Non-object root (a bare array) -- must refuse, return $false
#
# Run:  pwsh -NoProfile -File ./test-settings-env.ps1
#       powershell -NoProfile -File ./test-settings-env.ps1   (Windows PowerShell 5.1)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0
function Check($label, $got, $exp) {
    if ("$got" -eq "$exp") { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label -- got [$got] expected [$exp]" -ForegroundColor Red; $script:fail++ }
}
function Check-True($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label -- condition was false" -ForegroundColor Red; $script:fail++ }
}
# Null-safe property read: Set-StrictMode -Version Latest throws on dot-access of
# a missing property. The production code uses PSObject.Properties[$name] (returns
# $null when absent); mirror that here so assertions don't throw on missing keys.
function Prop($obj, $name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($p) { return $p.Value }
    return $null
}

# --- Production copy of Ensure-SettingsEnvFields (mirror of Enable-Claude3P.ps1) ---
# Single source of truth is Enable-Claude3P.ps1; this is a verbatim copy so the
# harness is self-contained and does not depend on test-helpers.ps1 load state.
function Backup-File { param([string]$Path) return 'test-bak' }
function Ensure-SettingsEnvFields {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    $obj = $null
    try { $obj = $raw | ConvertFrom-Json } catch { return $false }
    if (-not $obj) { return $false }
    if (-not ($obj -is [System.Management.Automation.PSCustomObject])) { return $false }
    if (-not ($obj.PSObject.Properties['env'])) {
        $obj | Add-Member -MemberType NoteProperty -Name 'env' -Value ([PSCustomObject]@{})
    }
    $envObj = $obj.env
    $added = $false
    foreach ($f in @('ANTHROPIC_AUTH_TOKEN','ANTHROPIC_API_KEY','ANTHROPIC_BASE_URL')) {
        if (-not ($envObj.PSObject.Properties[$f])) {
            $envObj | Add-Member -MemberType NoteProperty -Name $f -Value ''; $added = $true
        }
    }
    $universal = [ordered]@{
        'API_TIMEOUT_MS' = '3000000'
        'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' = '80'
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' = '1'
        'CLAUDE_CODE_USE_POWERSHELL_TOOL' = '1'
        'ENABLE_TOOL_SEARCH' = 'true'
        'ANTHROPIC_DEFAULT_SONNET_MODEL' = 'claude-sonnet-5-5'
        'ANTHROPIC_DEFAULT_HAIKU_MODEL' = 'claude-haiku-5-5'
        'ANTHROPIC_DEFAULT_OPUS_MODEL' = 'claude-opus-4.8'
    }
    foreach ($k in $universal.Keys) {
        if (-not ($envObj.PSObject.Properties[$k])) {
            $envObj | Add-Member -MemberType NoteProperty -Name $k -Value $universal[$k]; $added = $true
        }
    }
    $modelProp = $obj.PSObject.Properties['model']
    if (-not $modelProp) {
        $obj | Add-Member -MemberType NoteProperty -Name 'model' -Value 'claude-sonnet-5-5'; $added = $true
    }
    elseif ($modelProp.Value -ceq 'auto') {
        $obj.model = 'claude-sonnet-5-5'; $added = $true
    }
    if (-not $added) { return $false }
    $null = Backup-File $Path
    $json = $obj | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Write-TempJson($content) {
    $p = Join-Path $env:TEMP ('tse_' + [guid]::NewGuid().ToString('N') + '.json')
    [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding($false)))
    return $p
}

# ---- Case 1: no file at all ----
$absent = Join-Path $env:TEMP ('tse_absent_' + [guid]::NewGuid().ToString('N') + '.json')
$r = Ensure-SettingsEnvFields -Path $absent
Check 'case1 no-file returns false' $r 'False'
Check-True 'case1 no-file not created' (-not (Test-Path $absent))

# ---- Case 2: empty object {} ----
$t = Write-TempJson '{}'
$r = Ensure-SettingsEnvFields -Path $t
Check 'case2 empty-obj changed' $r 'True'
$o = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json
Check 'case2 env created' ($null -ne $o.env) 'True'
Check 'case2 model inserted' (Prop $o 'model') 'claude-sonnet-5-5'
$e2 = Prop $o 'env'
Check 'case2 SONNET tier' (Prop $e2 'ANTHROPIC_DEFAULT_SONNET_MODEL') 'claude-sonnet-5-5'
Check 'case2 HAIKU tier' (Prop $e2 'ANTHROPIC_DEFAULT_HAIKU_MODEL') 'claude-haiku-5-5'
Check 'case2 OPUS tier' (Prop $e2 'ANTHROPIC_DEFAULT_OPUS_MODEL') 'claude-opus-4.8'
Check 'case2 AUTH_TOKEN placeholder' (Prop $e2 'ANTHROPIC_AUTH_TOKEN') ''
Check 'case2 POWERSHELL_TOOL' (Prop $e2 'CLAUDE_CODE_USE_POWERSHELL_TOOL') '1'
Remove-Item $t -Force

# ---- Case 3: minimal working universal already present (idempotent no-op) ----
$min = @'
{"env":{"ANTHROPIC_AUTH_TOKEN":"k","ANTHROPIC_API_KEY":"k","ANTHROPIC_BASE_URL":"https://gw.example/","API_TIMEOUT_MS":"3000000","CLAUDE_AUTOCOMPACT_PCT_OVERRIDE":"80","CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1","CLAUDE_CODE_USE_POWERSHELL_TOOL":"1","ENABLE_TOOL_SEARCH":"true","ANTHROPIC_DEFAULT_SONNET_MODEL":"claude-sonnet-5-5","ANTHROPIC_DEFAULT_HAIKU_MODEL":"claude-haiku-5-5","ANTHROPIC_DEFAULT_OPUS_MODEL":"claude-opus-4.8"},"model":"claude-sonnet-5-5"}
'@
$t = Write-TempJson $min
$snapBefore = [System.IO.File]::ReadAllText($t)
$r = Ensure-SettingsEnvFields -Path $t
Check 'case3 minimal-universal no-op' $r 'False'
$snapAfter = [System.IO.File]::ReadAllText($t)
Check-True 'case3 minimal-universal byte-identical' ($snapBefore -ceq $snapAfter)
Remove-Item $t -Force

# ---- Case 4: complex -- nested plugins + marketplaces (real user shape) ----
$complex = @'
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "nr-iots-realkeyvalue",
    "ANTHROPIC_API_KEY": "nr-iots-realkeyvalue",
    "ANTHROPIC_BASE_URL": "https://chat-api.llm-kita.com/",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1",
    "ENABLE_TOOL_SEARCH": "true"
  },
  "enabledPlugins": {
    "ecc@ecc": true,
    "security-guidance@claude-plugins-official": true,
    "claude-security@claude-plugins-official": true,
    "athena@athena": true
  },
  "extraKnownMarketplaces": {
    "ecc": { "source": { "source": "git", "url": "https://github.com/affaan-m/ECC.git" } },
    "athena": { "source": { "source": "git", "url": "https://github.com/SPMechanic/athena-dev.git" } }
  }
}
'@
$t = Write-TempJson $complex
$beforeObj = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json
$beforePlugins = ($beforeObj.enabledPlugins.PSObject.Properties.Name | Sort-Object) -join ','
$beforeEccUrl = $beforeObj.extraKnownMarketplaces.ecc.source.url
$r = Ensure-SettingsEnvFields -Path $t
Check 'case4 complex changed (tier+model added)' $r 'True'
$afterObj = $null; $ok = $true
try { $afterObj = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json } catch { $ok = $false }
Check-True 'case4 complex re-parse valid JSON' $ok
$afterPlugins = ($afterObj.enabledPlugins.PSObject.Properties.Name | Sort-Object) -join ','
Check 'case4 plugins preserved' $afterPlugins $beforePlugins
Check 'case4 plugin count preserved' (@($afterObj.enabledPlugins.PSObject.Properties).Count) '4'
$ap4 = $afterObj.enabledPlugins
Check 'case4 ecc bool preserved' (Prop $ap4 'ecc@ecc') 'True'
Check 'case4 athena bool preserved' (Prop $ap4 'athena@athena') 'True'
$mk4 = $afterObj.extraKnownMarketplaces
Check 'case4 market count preserved' (@($mk4.PSObject.Properties).Count) '2'
$ecc4 = Prop $mk4 'ecc'; $eccSrc4 = Prop $ecc4 'source'
Check 'case4 ecc nested url preserved' (Prop $eccSrc4 'url') $beforeEccUrl
Check 'case4 ecc source.source preserved' (Prop $eccSrc4 'source') 'git'
$ath4 = Prop $mk4 'athena'; $athSrc4 = Prop $ath4 'source'
Check 'case4 athena nested url preserved' (Prop $athSrc4 'url') 'https://github.com/SPMechanic/athena-dev.git'
$e4 = Prop $afterObj 'env'
Check 'case4 SONNET injected' (Prop $e4 'ANTHROPIC_DEFAULT_SONNET_MODEL') 'claude-sonnet-5-5'
Check 'case4 HAIKU injected' (Prop $e4 'ANTHROPIC_DEFAULT_HAIKU_MODEL') 'claude-haiku-5-5'
Check 'case4 OPUS injected' (Prop $e4 'ANTHROPIC_DEFAULT_OPUS_MODEL') 'claude-opus-4.8'
Check 'case4 model inserted' (Prop $afterObj 'model') 'claude-sonnet-5-5'
Check 'case4 AUTH_TOKEN preserved' (Prop $e4 'ANTHROPIC_AUTH_TOKEN') 'nr-iots-realkeyvalue'
Check 'case4 BASE_URL preserved' (Prop $e4 'ANTHROPIC_BASE_URL') 'https://chat-api.llm-kita.com/'
# Idempotent second run
$r2 = Ensure-SettingsEnvFields -Path $t
Check 'case4 second-run no-op' $r2 'False'
Remove-Item $t -Force

# ---- Case 5: legacy "model":"auto" must be fixed to claude-sonnet-5-5 ----
$t = Write-TempJson '{"env":{"ANTHROPIC_API_KEY":"k"},"model":"auto"}'
$r = Ensure-SettingsEnvFields -Path $t
Check 'case5 auto rewrite changed' $r 'True'
$o = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json
Check 'case5 auto fixed to sonnet-5-5' (Prop $o 'model') 'claude-sonnet-5-5'
Remove-Item $t -Force

# ---- Case 6: custom user model id must be PRESERVED ----
$t = Write-TempJson '{"env":{"ANTHROPIC_API_KEY":"k"},"model":"claude-opus-4.8"}'
$null = Ensure-SettingsEnvFields -Path $t
$o = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json
Check 'case6 custom model preserved' (Prop $o 'model') 'claude-opus-4.8'
Remove-Item $t -Force

# ---- Case 7: custom user tier var must be PRESERVED (only-if-absent) ----
$t = Write-TempJson '{"env":{"ANTHROPIC_API_KEY":"k","ANTHROPIC_DEFAULT_OPUS_MODEL":"claude-opus-4-custom"}}'
$null = Ensure-SettingsEnvFields -Path $t
$o = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json
$e7 = Prop $o 'env'
Check 'case7 custom OPUS preserved' (Prop $e7 'ANTHROPIC_DEFAULT_OPUS_MODEL') 'claude-opus-4-custom'
Check 'case7 SONNET added (absent)' (Prop $e7 'ANTHROPIC_DEFAULT_SONNET_MODEL') 'claude-sonnet-5-5'
Check 'case7 HAIKU added (absent)' (Prop $e7 'ANTHROPIC_DEFAULT_HAIKU_MODEL') 'claude-haiku-5-5'
Remove-Item $t -Force

# ---- Case 8: corrupt JSON -- return $false, file untouched ----
$t = Write-TempJson '{bad json, "env":'
$snap = [System.IO.File]::ReadAllText($t)
$r = Ensure-SettingsEnvFields -Path $t
Check 'case8 corrupt returns false' $r 'False'
Check-True 'case8 corrupt file untouched' ($snap -ceq [System.IO.File]::ReadAllText($t))
Remove-Item $t -Force

# ---- Case 9: env block absent entirely ----
$t = Write-TempJson '{"permissions":{"defaultMode":"bypassPermissions"}}'
$r = Ensure-SettingsEnvFields -Path $t
Check 'case9 no-env changed' $r 'True'
$o = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json
Check-True 'case9 env created' ($null -ne (Prop $o 'env'))
$perm9 = Prop $o 'permissions'
Check 'case9 permissions preserved' (Prop $perm9 'defaultMode') 'bypassPermissions'
Check 'case9 model inserted' (Prop $o 'model') 'claude-sonnet-5-5'
Remove-Item $t -Force

# ---- Case 10: env present but empty {} ----
$t = Write-TempJson '{"env":{}}'
$r = Ensure-SettingsEnvFields -Path $t
Check 'case10 empty-env changed' $r 'True'
$o = [System.IO.File]::ReadAllText($t) | ConvertFrom-Json
$e10 = Prop $o 'env'
Check 'case10 SONNET added' (Prop $e10 'ANTHROPIC_DEFAULT_SONNET_MODEL') 'claude-sonnet-5-5'
Check 'case10 model inserted' (Prop $o 'model') 'claude-sonnet-5-5'
Remove-Item $t -Force

# ---- Case 11: non-object root (bare array) -- refuse, return $false ----
$t = Write-TempJson '[1,2,3]'
$snap = [System.IO.File]::ReadAllText($t)
$r = Ensure-SettingsEnvFields -Path $t
Check 'case11 array-root returns false' $r 'False'
Check-True 'case11 array-root untouched' ($snap -ceq [System.IO.File]::ReadAllText($t))
Remove-Item $t -Force

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Yellow'})
if ($fail -gt 0) { exit 1 } else { Write-Host 'ALL SETTINGS-ENV TESTS PASSED' -ForegroundColor Green }
