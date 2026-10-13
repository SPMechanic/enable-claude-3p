Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$fail = 0
function Expect($label, $got, $exp) {
    if ("$got" -eq "$exp") { Write-Host "PASS: $label ($got)" -ForegroundColor Green }
    else { Write-Host "FAIL: $label -- got [$got] expected [$exp]" -ForegroundColor Red; $script:fail++ }
}
function Backup-File { param([string]$Path) return 'test-bak' }

function Set-ClaudeStateOnboarding {
    param([Parameter(Mandatory)][string]$Path)
    $obj = $null
    if (Test-Path $Path) {
        try { $obj = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }
        catch { throw "Could not parse $Path as JSON: $_" }
    }
    else { $obj = [PSCustomObject]@{} }
    if (-not $obj) { $obj = [PSCustomObject]@{} }
    if (-not ($obj -is [System.Management.Automation.PSCustomObject])) {
        throw "$Path is not a JSON object (type: $($obj.GetType().Name)); refusing to modify"
    }
    $added = $false
    foreach ($f in 'hasCompletedOnboarding','hasTrustDialogAccepted','hasResetAutoModeOptInForDefaultOffer') {
        $prop = $obj.PSObject.Properties[$f]
        if (-not $prop) { $obj | Add-Member -MemberType NoteProperty -Name $f -Value $true; $added = $true }
    }
    if ($added -and -not ($obj.PSObject.Properties['_enableClaude3pSeededOnboarding'])) {
        $obj | Add-Member -MemberType NoteProperty -Name '_enableClaude3pSeededOnboarding' -Value $true
    }
    if (-not $added) { return $false }
    $json = $obj | ConvertTo-Json -Depth 50
    $oldRaw = if (Test-Path $Path) { [System.IO.File]::ReadAllText($Path) } else { '' }
    if ($json -ceq $oldRaw) { return $false }
    $null = Backup-File $Path
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Ensure-DesktopDeploymentMode {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    $obj = $null
    try { $obj = $raw | ConvertFrom-Json } catch { return $false }
    if (-not $obj) { return $false }
    if (-not ($obj.PSObject.Properties['deploymentMode'])) {
        $obj | Add-Member -MemberType NoteProperty -Name 'deploymentMode' -Value '3p'
    }
    elseif ($obj.deploymentMode -ceq '3p') { return $false }
    else { $obj.deploymentMode = '3p' }
    $json = $obj | ConvertTo-Json -Depth 10
    if ($json -ceq $raw) { return $false }
    $null = Backup-File $Path
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Ensure-SettingsEnvFields {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    $obj = $null
    try { $obj = $raw | ConvertFrom-Json } catch { return $false }
    if (-not $obj) { return $false }
    if (-not ($obj.PSObject.Properties['env'])) {
        $obj | Add-Member -MemberType NoteProperty -Name 'env' -Value ([ordered]@{})
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
    }
    foreach ($k in $universal.Keys) {
        if (-not ($envObj.PSObject.Properties[$k])) {
            $envObj | Add-Member -MemberType NoteProperty -Name $k -Value $universal[$k]; $added = $true
        }
    }
    if (-not $added) { return $false }
    $null = Backup-File $Path
    $json = $obj | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Set-JsonStringField {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Field, [Parameter(Mandatory)][string]$Value)
    if (-not (Test-Path $Path)) { return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    $pattern = '("' + [regex]::Escape($Field) + '"\s*:\s*")(?:[^"\\]|\\.)*(")'
    if ($raw -notmatch $pattern) { return $false }
    $new = [regex]::Replace($raw, $pattern, { param($m) $m.Groups[1].Value + $Value + $m.Groups[2].Value }, 1)
    if ($new -ceq $raw) { return $false }
    [System.IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Get-JsonStringField {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Field)
    if (-not (Test-Path $Path)) { return $null }
    $raw = [System.IO.File]::ReadAllText($Path)
    $m = [regex]::Match($raw, '"' + [regex]::Escape($Field) + '"\s*:\s*"((?:[^"\\]|\\.)*)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}
function Remove-JsonField {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Field)
    if (-not (Test-Path $Path)) { return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    $pattern = '(?m)\s*"' + [regex]::Escape($Field) + '"\s*:\s*(?:"(?:[^"\\]|\\.)*"|(?:-?\d+(?:\.\d+)?|true|false|null|\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}|\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\]))\s*,?'
    $new = [regex]::Replace($raw, $pattern, '', 1)
    if ($new -ceq $raw) { return $false }
    # Remove a trailing comma left before the enclosing object's closing brace.
    # Old pattern only matched comma+} at END-OF-STRING, so removing the LAST
    # field in a nested object left a dangling "},}" -> invalid JSON.
    $new = [regex]::Replace($new, ',(\s*\})', '$1', 1)
    [System.IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Write-GatewayConfigEntry {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$BaseUrl, [Parameter(Mandatory)][string]$ApiKey, [Parameter(Mandatory)][string]$AuthScheme, [object[]]$ResolvedModels, [bool]$ModelsSupplied = $false)
    $existing = [ordered]@{}
    if (Test-Path $Path) {
        try {
            $obj = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json
            foreach ($prop in $obj.PSObject.Properties) { $existing[$prop.Name] = $prop.Value }
        }
        catch { }
    }
    $normUrl = if ($BaseUrl) { $BaseUrl.TrimEnd('/') + '/' } else { $BaseUrl }
    $existing['inferenceProvider'] = 'gateway'
    $existing['inferenceCredentialKind'] = 'static'
    $existing['inferenceGatewayApiKey'] = $ApiKey
    $existing['inferenceGatewayAuthScheme'] = $AuthScheme
    $existing['inferenceGatewayBaseUrl'] = $normUrl
    if ($ModelsSupplied) {
        $existing['inferenceModels'] = $ResolvedModels
    }
    elseif (-not $existing.Contains('inferenceModels')) {
        $existing['inferenceModels'] = @(
            @{ name = 'claude-sonnet-5-5'; labelOverride = 'Claude Sonnet 5.5'; supports1m = $false; anthropicFamilyTier = 'sonnet'; isFamilyDefault = $true; maxEffort = 'max' },
            @{ name = 'claude-opus-4.8';   labelOverride = 'Claude Opus 4.8'; supports1m = $false; anthropicFamilyTier = 'opus'; isFamilyDefault = $true; maxEffort = 'max' },
            @{ name = 'claude-haiku-5-5';  labelOverride = 'Claude Haiku 5.5'; supports1m = $false; anthropicFamilyTier = 'haiku'; isFamilyDefault = $true; maxEffort = 'max' }
        )
    }
    $json = $existing | ConvertTo-Json -Depth 50
    $oldRaw = if (Test-Path $Path) { [System.IO.File]::ReadAllText($Path) } else { '' }
    if ($json -ceq $oldRaw) { return $false }
    $null = Backup-File $Path
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Resolve-InferenceModels {
    param([Parameter(Mandatory)][string]$ModelsJson)
    $parsed = $null
    try { $parsed = $ModelsJson | ConvertFrom-Json }
    catch { throw "-Models is not valid JSON: $($_.Exception.Message)" }
    if ($null -eq $parsed -or -not ($parsed -is [System.Array])) {
        throw "-Models must be a JSON array."
    }
    $tiers = @('sonnet', 'opus', 'haiku', 'fable', 'mythos')
    $result = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($entry in $parsed) {
        if ($null -eq $entry -or -not ($entry -is [System.Management.Automation.PSCustomObject])) {
            throw "-Models[$i] must be a JSON object."
        }
        $ht = [ordered]@{}
        foreach ($prop in $entry.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }
        $name = $ht['name']
        $label = $ht['labelOverride']
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($label)) {
            throw "-Models[$i] missing 'name' or 'labelOverride'."
        }
        if (-not $ht.Contains('supports1m'))      { $ht['supports1m'] = $false }
        if (-not $ht.Contains('isFamilyDefault')) { $ht['isFamilyDefault'] = $true }
        if (-not $ht.Contains('maxEffort'))       { $ht['maxEffort'] = 'max' }
        if (-not $ht.Contains('anthropicFamilyTier')) {
            $ht['anthropicFamilyTier'] = if ($i -lt $tiers.Count) { $tiers[$i] } else { 'sonnet' }
        }
        $result.Add($ht)
        $i++
    }
    return ,$result.ToArray()
}
function Resolve-Claude3pDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    if ($dirs -notcontains $Claude3pDir) { $dirs.Add($Claude3pDir) }
    $packagesDir = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $packagesDir) {
        try {
            Get-ChildItem $packagesDir -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue | ForEach-Object {
                foreach ($leaf in @('Claude-3p', 'Claude')) {
                    $cand = Join-Path $_.FullName "LocalCache\Roaming\$leaf"
                    if ((Test-Path $cand) -and ($dirs -notcontains $cand)) { $dirs.Add($cand) }
                }
            }
        }
        catch { }
    }
    return ,$dirs.ToArray()
}
# Invoke-RestoreCore: the testable core of the Restore block (D1/D2/D3 logic)
# without Write-Host noise. Mirrors Enable-Claude3P.ps1 lines 542-617 verbatim
# in logic. Params are the files a single Restore iteration touches. Returns
# $true if anything changed ($any), $false if already stock.
function Invoke-RestoreCore {
    param(
        [Parameter(Mandatory)][string]$MetaPath,
        [Parameter(Mandatory)][string]$SettingsPath,
        [Parameter(Mandatory)][string]$ClaudeStatePath,
        [Parameter(Mandatory)][bool]$SyncCli
    )
    $any = $false
    # D2: _meta.json content-compare before rewriting
    if (Test-Path $MetaPath) {
        $zeroed = '{"appliedId":"","entries":[]}'
        $curMeta = [System.IO.File]::ReadAllText($MetaPath)
        if ($curMeta -cne $zeroed) {
            $null = Backup-File $MetaPath
            [System.IO.File]::WriteAllText($MetaPath, $zeroed, (New-Object System.Text.UTF8Encoding($false)))
            $any = $true
        }
    }
    if ($SyncCli) {
        # D3: settings.json strip must set $any
        if (Test-Path $SettingsPath) {
            $null = Backup-File $SettingsPath
            $stripped = $false
            foreach ($f in @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL')) {
                if (Remove-JsonField -Path $SettingsPath -Field $f) { $stripped = $true }
            }
            if ($stripped) { $any = $true }
        }
        # D1: sentinel-gated onboarding bool removal
        if (Test-Path $ClaudeStatePath) {
            $stateObj = $null
            try { $stateObj = [System.IO.File]::ReadAllText($ClaudeStatePath) | ConvertFrom-Json }
            catch { }
            if ($stateObj -and ($stateObj -is [System.Management.Automation.PSCustomObject]) -and $stateObj.PSObject.Properties['_enableClaude3pSeededOnboarding']) {
                $null = Backup-File $ClaudeStatePath
                $removedBool = $false
                foreach ($f in 'hasCompletedOnboarding', 'hasTrustDialogAccepted', 'hasResetAutoModeOptInForDefaultOffer') {
                    if (Remove-JsonField -Path $ClaudeStatePath -Field $f) { $removedBool = $true }
                }
                if (Remove-JsonField -Path $ClaudeStatePath -Field '_enableClaude3pSeededOnboarding') { $removedBool = $true }
                if ($removedBool) { $any = $true }
            }
        }
    }
    return $any
}
# Resolve-GitBashPath: testable copy. Checks the hardcoded path, then PATH `git`.
function Resolve-GitBashPath {
    $hardcoded = 'C:\Program Files\Git\bin\bash.exe'
    if (Test-Path -LiteralPath $hardcoded) { return $true }
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $gitDir = Split-Path $gitCmd.Source -Parent
        if (Test-Path -LiteralPath (Join-Path $gitDir 'bash.exe')) { return $true }
        if (Test-Path -LiteralPath (Join-Path (Split-Path $gitDir -Parent) 'bin\bash.exe')) { return $true }
        return $true
    }
    return $false
}

$tmp = Join-Path $env:TEMP ('test_state_' + [guid]::NewGuid().ToString('N') + '.json')
'[1,2,3]' | Out-File $tmp -Encoding utf8
$threw = $false; try { Set-ClaudeStateOnboarding -Path $tmp } catch { $threw = $true }
Expect 'array throws' $threw $true
'42' | Out-File $tmp -Encoding utf8
$threw = $false; try { Set-ClaudeStateOnboarding -Path $tmp } catch { $threw = $true }
Expect 'scalar throws' $threw $true
'{bad json' | Out-File $tmp -Encoding utf8
$threw = $false; try { Set-ClaudeStateOnboarding -Path $tmp } catch { $threw = $true }
Expect 'corrupt throws' $threw $true
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
$r = Set-ClaudeStateOnboarding -Path $tmp
Expect 'pristine changed' $r $true
$o = Get-Content $tmp | ConvertFrom-Json
Expect 'hasCompletedOnboarding' $o.hasCompletedOnboarding 'True'
Expect 'hasTrustDialogAccepted' $o.hasTrustDialogAccepted 'True'
Expect 'hasResetAutoMode' $o.hasResetAutoModeOptInForDefaultOffer 'True'
$r2 = Set-ClaudeStateOnboarding -Path $tmp
Expect 'idempotent no-op' $r2 'False'
$existing = '{"machineID":"abc","userID":"xyz","pluginUsage":{"x":5},"projects":{"C:/t":{"hasTrustDialogAccepted":true}}}'
$existing | Out-File $tmp -Encoding utf8
$r3 = Set-ClaudeStateOnboarding -Path $tmp
Expect 'preserve-existing changed' $r3 $true
$o3 = Get-Content $tmp | ConvertFrom-Json
Expect 'machineID preserved' $o3.machineID 'abc'
Expect 'userID preserved' $o3.userID 'xyz'
Expect 'pluginUsage.x preserved' $o3.pluginUsage.x 5
Expect 'projects trust preserved' $o3.projects.'C:/t'.hasTrustDialogAccepted 'True'
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

# --- Sentinel: _enableClaude3pSeededOnboarding ---
# Set when bools are seeded, absent on a no-op re-run, and NOT added when bools
# already exist (user completed stock onboarding before 3P). Restore consumes it
# to remove only script-seeded bools.
$sent = Join-Path $env:TEMP ('test_sentinel_' + [guid]::NewGuid().ToString('N') + '.json')
# Pristine seed -> sentinel added
$r = Set-ClaudeStateOnboarding -Path $sent
Expect 'sentinel seeded on pristine' $r $true
$o = Get-Content $sent | ConvertFrom-Json
Expect 'sentinel present after seed' ($null -ne $o.PSObject.Properties['_enableClaude3pSeededOnboarding']) 'True'
# Idempotent re-run -> bools already present, sentinel NOT re-touched (no-op)
$r2 = Set-ClaudeStateOnboarding -Path $sent
Expect 'sentinel idempotent no-op' $r2 $false
# Pre-existing bools (user did stock onboarding) -> sentinel NOT added
'{"hasCompletedOnboarding":true,"hasTrustDialogAccepted":true,"hasResetAutoModeOptInForDefaultOffer":true,"machineID":"m"}' | Out-File $sent -Encoding utf8
$r3 = Set-ClaudeStateOnboarding -Path $sent
Expect 'sentinel not added when bools exist' $r3 $false
$o2 = Get-Content $sent | ConvertFrom-Json
Expect 'sentinel absent when bools pre-existed' ($null -eq $o2.PSObject.Properties['_enableClaude3pSeededOnboarding']) 'True'
Remove-Item $sent -Force -ErrorAction SilentlyContinue

$tdesk = Join-Path $env:TEMP ('test_desk_' + [guid]::NewGuid().ToString('N') + '.json')
'{"mcpServers":{}}' | Out-File $tdesk -Encoding utf8
$r = Ensure-DesktopDeploymentMode -Path $tdesk
Expect 'desk insert changed' $r $true
$o = Get-Content $tdesk | ConvertFrom-Json
Expect 'deploymentMode set' $o.deploymentMode '3p'
Expect 'mcpServers preserved' ($null -ne $o.mcpServers) 'True'
$r2 = Ensure-DesktopDeploymentMode -Path $tdesk
Expect 'desk already 3p no-op' $r2 'False'
'{"deploymentMode":"prod"}' | Out-File $tdesk -Encoding utf8
$r3 = Ensure-DesktopDeploymentMode -Path $tdesk
Expect 'desk update changed' $r3 $true
$o3 = Get-Content $tdesk | ConvertFrom-Json
Expect 'desk updated to 3p' $o3.deploymentMode '3p'
Remove-Item $tdesk -Force -ErrorAction SilentlyContinue

$tset = Join-Path $env:TEMP ('test_set_' + [guid]::NewGuid().ToString('N') + '.json')
'{"env":{"ANTHROPIC_API_KEY":"oldkey","CUSTOM":"keepme"},"model":"auto"}' | Out-File $tset -Encoding utf8
$r = Ensure-SettingsEnvFields -Path $tset
Expect 'settings inject changed' $r $true
$o = Get-Content $tset | ConvertFrom-Json
Expect 'existing API_KEY preserved' $o.env.ANTHROPIC_API_KEY 'oldkey'
Expect 'CUSTOM preserved' $o.env.CUSTOM 'keepme'
Expect 'AUTH_TOKEN added' ($null -ne $o.env.PSObject.Properties['ANTHROPIC_AUTH_TOKEN']) 'True'
Expect 'BASE_URL added' ($null -ne $o.env.PSObject.Properties['ANTHROPIC_BASE_URL']) 'True'
Expect 'API_TIMEOUT_MS added' $o.env.API_TIMEOUT_MS '3000000'
Expect 'POWERSHELL_TOOL added' $o.env.CLAUDE_CODE_USE_POWERSHELL_TOOL '1'
Expect 'TOOL_SEARCH added' $o.env.ENABLE_TOOL_SEARCH 'true'
Expect 'AUTOCOMPACT added' $o.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE '80'
$r2 = Ensure-SettingsEnvFields -Path $tset
Expect 'settings inject idempotent' $r2 'False'
Remove-Item $tset -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Set-JsonStringField / Get-JsonStringField / Remove-JsonStringField
# Edge cases: missing field, special chars in value, nested quotes, invalid JSON
# ---------------------------------------------------------------------------
$tr = Join-Path $env:TEMP ('test_regex_' + [guid]::NewGuid().ToString('N') + '.json')

# --- Set-JsonStringField ---
# Missing field -> no-op ($false), file untouched
'{"other":"keep"}' | Out-File $tr -Encoding utf8
$r = Set-JsonStringField -Path $tr -Field 'absentField' -Value 'x'
Expect 'set missing field no-op' $r 'False'
Expect 'set missing file untouched' ([System.IO.File]::ReadAllText($tr).Trim()) '{"other":"keep"}'

# Missing file -> no-op ($false)
$gone = Join-Path $env:TEMP ('nope_' + [guid]::NewGuid().ToString('N') + '.json')
$r = Set-JsonStringField -Path $gone -Field 'f' -Value 'v'
Expect 'set missing file no-op' $r 'False'

# Update existing string field -> $true, value replaced
'{"deploymentMode":"prod"}' | Out-File $tr -Encoding utf8
$r = Set-JsonStringField -Path $tr -Field 'deploymentMode' -Value '3p'
Expect 'set existing field changed' $r 'True'
Expect 'set value replaced' (Get-JsonStringField -Path $tr -Field 'deploymentMode') '3p'

# Idempotent: same value -> $false, no write
$r2 = Set-JsonStringField -Path $tr -Field 'deploymentMode' -Value '3p'
Expect 'set idempotent no-op' $r2 'False'

# Set-JsonStringField is regex-only and does NOT JSON-escape: it substitutes
# the raw value verbatim into the capture. Get-JsonStringField likewise does
# NOT unescape -- its capture group ((?:[^"\\]|\\.)*) preserves backslash
# sequences as-is. The callers in the main script pass already-safe values
# ('3p', API keys, URLs -- no raw quotes/control chars). These two tests pin
# that raw contract so a future refactor to proper escaping is detected.
'{"name":"old"}' | Out-File $tr -Encoding utf8
$specVal = 'C:\path\to\dir'
$r = Set-JsonStringField -Path $tr -Field 'name' -Value $specVal
Expect 'set backslash value changed' $r 'True'
$readBack = Get-JsonStringField -Path $tr -Field 'name'
Expect 'set backslash value raw round-trip' $readBack $specVal

# Nested quotes in JSON value (escaped \" in the stored text). Get-JsonStringField's
# capture group preserves the backslash-escape pairs -- it does NOT unescape
# \" to a bare quote. Documents the no-unescape contract.
'{"note":"he said \"hi\" loudly"}' | Out-File $tr -Encoding utf8
$g = Get-JsonStringField -Path $tr -Field 'note'
Expect 'get nested quotes no-unescape' $g 'he said \"hi\" loudly'

# Field with extra whitespace around colon -> matched (regex allows \s*)
'{"k"   :   "v"}' | Out-File $tr -Encoding utf8
$g = Get-JsonStringField -Path $tr -Field 'k'
Expect 'get whitespace-tolerant' $g 'v'
$r = Set-JsonStringField -Path $tr -Field 'k' -Value 'w'
Expect 'set whitespace-tolerant changed' $r 'True'

# Only first occurrence replaced (count=1)
'{"a":"1","a":"2"}' | Out-File $tr -Encoding utf8
$r = Set-JsonStringField -Path $tr -Field 'a' -Value 'X'
Expect 'set first-occurrence only changed' $r 'True'
$g = Get-JsonStringField -Path $tr -Field 'a'
Expect 'set first-occurrence value' $g 'X'

# Invalid JSON with a string field present -> regex still operates on raw text
# (documents that these helpers are NOT parse-based and will mutate even
# structurally-invalid JSON if the field regex matches)
'{bad json, "name":"here"}' | Out-File $tr -Encoding utf8
$r = Set-JsonStringField -Path $tr -Field 'name' -Value 'new'
Expect 'set on invalid-json changed' $r 'True'
$g = Get-JsonStringField -Path $tr -Field 'name'
Expect 'get on invalid-json' $g 'new'

# --- Get-JsonStringField ---
# Missing field -> $null
'{"a":"1"}' | Out-File $tr -Encoding utf8
$g = Get-JsonStringField -Path $tr -Field 'missing'
Expect 'get missing field null' ($null -eq $g) 'True'
# Missing file -> $null
$g = Get-JsonStringField -Path $gone -Field 'f'
Expect 'get missing file null' ($null -eq $g) 'True'
# Non-string field (number) -> regex requires quotes, so $null
'{"count":42}' | Out-File $tr -Encoding utf8
$g = Get-JsonStringField -Path $tr -Field 'count'
Expect 'get non-string null' ($null -eq $g) 'True'

# --- Remove-JsonField ---
# Remove string field -> $true, field gone, other preserved
'{"deploymentMode":"3p","mcpServers":{"x":1},"model":"auto"}' | Out-File $tr -Encoding utf8
$r = Remove-JsonField -Path $tr -Field 'deploymentMode'
Expect 'remove string field changed' $r 'True'
$g = Get-JsonStringField -Path $tr -Field 'deploymentMode'
Expect 'remove string field gone' ($null -eq $g) 'True'
$o = Get-Content $tr | ConvertFrom-Json
Expect 'remove preserves sibling' $o.mcpServers.x 1

# Remove last field -> trailing-comma cleanup runs (regex `,(\s*\}$)`)
'{"only":"x"}' | Out-File $tr -Encoding utf8
$r = Remove-JsonField -Path $tr -Field 'only'
Expect 'remove last field changed' $r 'True'
$txt = ([System.IO.File]::ReadAllText($tr).Trim())
Expect 'remove last field empty obj' $txt '{}'

# Regression: remove LAST field in a NESTED object whose closing brace is NOT at
# end-of-string (followed by a sibling key). Old regex only matched comma+} at
# end-of-string, leaving a dangling "},}" -> invalid JSON. This is the real-world
# Restore path: stripping ANTHROPIC_API_KEY when it sat last in env.
'{"env":{"A":"1","B":"2","ANTHROPIC_API_KEY":"x"},"permissions":{}}' | Out-File $tr -Encoding utf8
$r = Remove-JsonField -Path $tr -Field 'ANTHROPIC_API_KEY'
Expect 'remove nested-last changed' $r 'True'
$okNested = $true
try { ([System.IO.File]::ReadAllText($tr) | ConvertFrom-Json) | Out-Null }
catch { $okNested = $false }
Expect 'remove nested-last valid JSON' $okNested 'True'
# And the real settings.json shape (GATEGUARD_EXEMPT_GLOBS becomes last after strip)
'{"$schema":"x","env":{"ANTHROPIC_AUTH_TOKEN":"x","ANTHROPIC_BASE_URL":"u","API_TIMEOUT_MS":"3","GATEGUARD_EXEMPT_GLOBS":"g","ANTHROPIC_API_KEY":"x"},"permissions":{"defaultMode":"bypassPermissions"}}' | Out-File $tr -Encoding utf8
foreach ($f in 'ANTHROPIC_AUTH_TOKEN','ANTHROPIC_BASE_URL','ANTHROPIC_API_KEY') {
    Remove-JsonField -Path $tr -Field $f | Out-Null
}
$okReal = $true
$realObj = $null
try { $realObj = ([System.IO.File]::ReadAllText($tr) | ConvertFrom-Json) }
catch { $okReal = $false }
Expect 'remove strip-all-three valid JSON' $okReal 'True'
$remain = @($realObj.env.PSObject.Properties.Name) -join ','
Expect 'remove strip-all-three remaining env' $remain 'API_TIMEOUT_MS,GATEGUARD_EXEMPT_GLOBS'

# Missing field -> $false
'{"a":"1"}' | Out-File $tr -Encoding utf8
$r = Remove-JsonField -Path $tr -Field 'absent'
Expect 'remove missing field no-op' $r 'False'

# Remove non-string value (number) -> $true
'{"n":42,"k":"keep"}' | Out-File $tr -Encoding utf8
$r = Remove-JsonField -Path $tr -Field 'n'
Expect 'remove number changed' $r 'True'
$o = Get-Content $tr | ConvertFrom-Json
Expect 'remove number sibling kept' $o.k 'keep'

# Remove bool -> $true
'{"b":true,"k":"keep"}' | Out-File $tr -Encoding utf8
$r = Remove-JsonField -Path $tr -Field 'b'
Expect 'remove bool changed' $r 'True'
$o = Get-Content $tr | ConvertFrom-Json
Expect 'remove bool sibling kept' $o.k 'keep'

# Missing file -> $false
$r = Remove-JsonField -Path $gone -Field 'f'
Expect 'remove missing file no-op' $r 'False'

Remove-Item $tr -Force -ErrorAction SilentlyContinue
Remove-Item $gone -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Write-GatewayConfigEntry: merge, preserve other fields, idempotent
# ---------------------------------------------------------------------------
$tgw = Join-Path $env:TEMP ('test_gw_' + [guid]::NewGuid().ToString('N') + '.json')

# Pristine (no file) -> creates with all gateway fields + model catalog
$r = Write-GatewayConfigEntry -Path $tgw -BaseUrl 'https://gw.example.com' -ApiKey 'k1' -AuthScheme 'Bearer'
Expect 'gw pristine changed' $r $true
$o = Get-Content $tgw | ConvertFrom-Json
Expect 'gw pristine provider' $o.inferenceProvider 'gateway'
Expect 'gw pristine apiKey' $o.inferenceGatewayApiKey 'k1'
Expect 'gw pristine authScheme' $o.inferenceGatewayAuthScheme 'Bearer'
Expect 'gw pristine baseUrl trailing slash' $o.inferenceGatewayBaseUrl 'https://gw.example.com/'
Expect 'gw pristine models seeded' ($null -ne $o.inferenceModels) 'True'
Expect 'gw pristine model count' ($o.inferenceModels.Count) 3

# BaseUrl with trailing slash already -> not doubled
Remove-Item $tgw -Force
$r = Write-GatewayConfigEntry -Path $tgw -BaseUrl 'https://gw.example.com/' -ApiKey 'k2' -AuthScheme 'Bearer'
Expect 'gw trailing slash not doubled' (Get-Content $tgw | ConvertFrom-Json).inferenceGatewayBaseUrl 'https://gw.example.com/'

# Merge into existing entry: preserve other fields, update gateway fields
'{"customField":"keepme","inferenceModels":["existing-model"],"extra":7}' | Out-File $tgw -Encoding utf8
$r = Write-GatewayConfigEntry -Path $tgw -BaseUrl 'https://gw2' -ApiKey 'k3' -AuthScheme 'Anonymous'
Expect 'gw merge changed' $r $true
$o = Get-Content $tgw | ConvertFrom-Json
Expect 'gw merge custom preserved' $o.customField 'keepme'
Expect 'gw merge extra preserved' $o.extra 7
Expect 'gw merge apiKey updated' $o.inferenceGatewayApiKey 'k3'
Expect 'gw merge baseUrl updated' $o.inferenceGatewayBaseUrl 'https://gw2/'
# Existing non-empty inferenceModels must NOT be overwritten (user's UI config)
Expect 'gw merge models preserved' ($o.inferenceModels.Count) 1
Expect 'gw merge model name kept' $o.inferenceModels[0] 'existing-model'

# Idempotent: re-run with same args -> $false (content identical)
$r2 = Write-GatewayConfigEntry -Path $tgw -BaseUrl 'https://gw2' -ApiKey 'k3' -AuthScheme 'Anonymous'
Expect 'gw idempotent no-op' $r2 $false

# Corrupt existing file -> catch swallows, treated as pristine (gateway fields written)
'{bad json' | Out-File $tgw -Encoding utf8
$r = Write-GatewayConfigEntry -Path $tgw -BaseUrl 'https://gw3' -ApiKey 'k4' -AuthScheme 'Bearer'
Expect 'gw corrupt treated as pristine' $r $true
$o = Get-Content $tgw | ConvertFrom-Json
Expect 'gw corrupt apiKey written' $o.inferenceGatewayApiKey 'k4'

Remove-Item $tgw -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Resolve-Claude3pDirs: MSIX Packages\Claude_* enumeration, comma-wrapper,
# StrictMode safety across 0/1/N element counts.
# Builds a synthetic %LOCALAPPDATA% tree under temp and overrides $env:LOCALAPPDATA
# so the real Packages dir is not touched.
# ---------------------------------------------------------------------------
$synLocal = Join-Path $env:TEMP ('synlocal_' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $synLocal
# Resolve to the long-name form: $env:TEMP often yields an 8.3 short path
# (e.g. CONSUL~1), but Get-ChildItem .FullName returns the long name
# (Consultant). String -contains comparisons would otherwise fail spuriously.
$synLocal = (Get-Item $synLocal).FullName
# No Packages dir at all -> only the legacy Claude-3p dir is returned
$prevLA = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $synLocal
$Claude3pDir = Join-Path $synLocal 'Claude-3p'

Set-StrictMode -Version Latest
$dirs = Resolve-Claude3pDirs
Expect 'dirs legacy only count' ($dirs.Count) 1
Expect 'dirs legacy only content' $dirs[0] $Claude3pDir
# Comma-wrapper: result must be an array even with 1 element (not unwrapped to scalar)
Expect 'dirs 1-elem is array' ($dirs -is [array]) 'True'

# Packages dir exists but has no Claude_* child -> still only legacy dir
$null = New-Item -ItemType Directory -Force -Path (Join-Path $synLocal 'Packages')
$dirs = Resolve-Claude3pDirs
Expect 'dirs empty packages count' ($dirs.Count) 1

# Add an MSIX-style Claude_* package with LocalCache\Roaming\Claude-3p
$pkgRoot = Join-Path $synLocal 'Packages\Claude_somehash'
$cacheDir = Join-Path $pkgRoot 'LocalCache\Roaming\Claude-3p'
$null = New-Item -ItemType Directory -Force -Path $cacheDir
$dirs = Resolve-Claude3pDirs
Expect 'dirs with msix count' ($dirs.Count) 2
Expect 'dirs msix legacy present' ($dirs -contains $Claude3pDir) 'True'
Expect 'dirs msix cache present' ($dirs -contains $cacheDir) 'True'

# A second Claude_* package, plus a Claude (not Claude-3p) leaf -> both leaves enumerated
$pkgRoot2 = Join-Path $synLocal 'Packages\Claude_otherhash'
$cache2 = Join-Path $pkgRoot2 'LocalCache\Roaming\Claude'
$null = New-Item -ItemType Directory -Force -Path $cache2
$dirs = Resolve-Claude3pDirs
Expect 'dirs two msix count' ($dirs.Count) 3
Expect 'dirs two msix claude leaf' ($dirs -contains $cache2) 'True'

# Non-Claude_* package (e.g. Microsoft.Win32UEV_*) must be ignored
$null = New-Item -ItemType Directory -Force -Path (Join-Path $synLocal 'Packages\Microsoft.Whatever_1.0')
$dirs = Resolve-Claude3pDirs
Expect 'dirs non-claude pkg ignored' ($dirs.Count) 3

# Comma-wrapper under StrictMode: a 0-element array is impossible here (legacy
# dir is always added), but verify the wrapper survives re-assignment and .Count
# access under Set-StrictMode -Version Latest without throwing.
$dirs2 = Resolve-Claude3pDirs
$cnt = $dirs2.Count
Expect 'dirs strictmode count access' ($cnt -ge 1) 'True'

$env:LOCALAPPDATA = $prevLa
Remove-Item -Recurse -Force $synLocal -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Restore core (D1/D2/D3): Invoke-RestoreCore mirrors the Restore block logic.
# D1 = sentinel-gated onboarding bool removal.
# D2 = content-compare before rewriting _meta.json (no .bak stacking).
# D3 = settings.json strip sets $any (fixes misleading "Already stock").
# ---------------------------------------------------------------------------
$trm = Join-Path $env:TEMP ('test_restore_' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $trm
$metaPath = Join-Path $trm '_meta.json'
$setPath   = Join-Path $trm 'settings.json'
$statePath = Join-Path $trm '.claude.json'

# --- D2: _meta.json content-compare ---
# Non-zero content -> rewritten, $any true
'{"appliedId":"abc","entries":[1]}' | Out-File $metaPath -Encoding utf8
$r = Invoke-RestoreCore -MetaPath $metaPath -SettingsPath $setPath -ClaudeStatePath $statePath -SyncCli $false
Expect 'D2 rewrite changed' $r $true
Expect 'D2 zeroed content' ([System.IO.File]::ReadAllText($metaPath).Trim()) '{"appliedId":"","entries":[]}'
# Already zeroed -> NOT rewritten, $any false (no .bak stacking)
$r2 = Invoke-RestoreCore -MetaPath $metaPath -SettingsPath $setPath -ClaudeStatePath $statePath -SyncCli $false
Expect 'D2 already-zeroed no-op' $r2 $false

# --- D3: settings.json strip sets $any ---
'{"env":{"ANTHROPIC_AUTH_TOKEN":"k","ANTHROPIC_API_KEY":"k2","ANTHROPIC_BASE_URL":"u","OTHER":"keep"}}' | Out-File $setPath -Encoding utf8
# Only settings.json has gateway fields; meta is absent, state is absent.
# Without the D3 fix this would return $false ("Already stock").
Remove-Item $metaPath -Force -ErrorAction SilentlyContinue
$r = Invoke-RestoreCore -MetaPath $metaPath -SettingsPath $setPath -ClaudeStatePath $statePath -SyncCli $true
Expect 'D3 settings-only sets any' $r $true
$o = Get-Content $setPath | ConvertFrom-Json
Expect 'D3 AUTH_TOKEN stripped' ($null -eq $o.env.PSObject.Properties['ANTHROPIC_AUTH_TOKEN']) 'True'
Expect 'D3 API_KEY stripped' ($null -eq $o.env.PSObject.Properties['ANTHROPIC_API_KEY']) 'True'
Expect 'D3 BASE_URL stripped' ($null -eq $o.env.PSObject.Properties['ANTHROPIC_BASE_URL']) 'True'
Expect 'D3 OTHER preserved' $o.env.OTHER 'keep'
# Re-run: nothing left to strip -> $any false
$r2 = Invoke-RestoreCore -MetaPath $metaPath -SettingsPath $setPath -ClaudeStatePath $statePath -SyncCli $true
Expect 'D3 second-run no-op' $r2 $false

# --- D1: sentinel-gated onboarding bool removal ---
# With sentinel (script seeded) -> bools + sentinel removed, $any true
'{"hasCompletedOnboarding":true,"hasTrustDialogAccepted":true,"hasResetAutoModeOptInForDefaultOffer":true,"_enableClaude3pSeededOnboarding":true,"machineID":"m"}' | Out-File $statePath -Encoding utf8
$r = Invoke-RestoreCore -MetaPath $metaPath -SettingsPath $setPath -ClaudeStatePath $statePath -SyncCli $true
Expect 'D1 sentinel-present sets any' $r $true
$o = Get-Content $statePath | ConvertFrom-Json
Expect 'D1 bools removed' ($null -eq $o.PSObject.Properties['hasCompletedOnboarding']) 'True'
Expect 'D1 sentinel removed' ($null -eq $o.PSObject.Properties['_enableClaude3pSeededOnboarding']) 'True'
Expect 'D1 machineID preserved' $o.machineID 'm'
# Without sentinel (user did stock onboarding) -> bools LEFT INTACT, $any false
'{"hasCompletedOnboarding":true,"hasTrustDialogAccepted":true,"hasResetAutoModeOptInForDefaultOffer":true,"machineID":"user-set"}' | Out-File $statePath -Encoding utf8
$r = Invoke-RestoreCore -MetaPath $metaPath -SettingsPath $setPath -ClaudeStatePath $statePath -SyncCli $true
Expect 'D1 no-sentinel no-op' $r $false
$o = Get-Content $statePath | ConvertFrom-Json
Expect 'D1 user bools preserved' $o.hasCompletedOnboarding 'True'
Expect 'D1 user machineID preserved' $o.machineID 'user-set'
# Corrupt .claude.json -> skipped (no throw, no mutation), $any false
'{bad json' | Out-File $statePath -Encoding utf8
$threw = $false
try { $r = Invoke-RestoreCore -MetaPath $metaPath -SettingsPath $setPath -ClaudeStatePath $statePath -SyncCli $true } catch { $threw = $true }
Expect 'D1 corrupt no-throw' $threw $false
Expect 'D1 corrupt content unchanged' ([System.IO.File]::ReadAllText($statePath).Trim()) '{bad json'

Remove-Item -Recurse -Force $trm -ErrorAction SilentlyContinue

# ---------------------------------------------------------------------------
# Resolve-GitBashPath (q3): detects Git for Windows at the hardcoded path or
# via PATH `git`. This machine has Git at the standard location, so we assert
# the positive case. The negative case (no Git) can't be tested without
# sandboxing PATH, but the function logic is a simple two-step fallback.
# ---------------------------------------------------------------------------
$gb = Resolve-GitBashPath
Expect 'GitBash detected on this machine' $gb $true

# ---------------------------------------------------------------------------
# Resolve-InferenceModels: parse -Models JSON into a catalog array. Pure
# helper -- mandatory name+labelOverride, optional fields filled by position.
# ---------------------------------------------------------------------------
# Valid 2-entry array: user fields verbatim + missing fields filled by position.
$r = Resolve-InferenceModels -ModelsJson '[{"name":"glm-5.3","labelOverride":"opus-4.8"},{"name":"claude-haiku-5-5","labelOverride":"Haiku"}]'
Expect 'rim 2-entry count' ($r.Count) '2'
Expect 'rim entry0 name verbatim' ($r[0]['name']) 'glm-5.3'
Expect 'rim entry0 label verbatim' ($r[0]['labelOverride']) 'opus-4.8'
Expect 'rim entry0 tier by-position sonnet' ($r[0]['anthropicFamilyTier']) 'sonnet'
Expect 'rim entry0 supports1m defaulted' ($r[0]['supports1m']) 'False'
Expect 'rim entry0 isFamilyDefault defaulted' ($r[0]['isFamilyDefault']) 'True'
Expect 'rim entry0 maxEffort defaulted' ($r[0]['maxEffort']) 'max'
Expect 'rim entry1 name verbatim' ($r[1]['name']) 'claude-haiku-5-5'
Expect 'rim entry1 label verbatim' ($r[1]['labelOverride']) 'Haiku'
Expect 'rim entry1 tier by-position opus' ($r[1]['anthropicFamilyTier']) 'opus'

# Single entry, only mandatory fields -> all 4 non-mandatory defaulted.
$r = Resolve-InferenceModels -ModelsJson '[{"name":"glm-5.3","labelOverride":"opus-4.8"}]'
Expect 'rim 1-entry count' ($r.Count) '1'
Expect 'rim single tier sonnet' ($r[0]['anthropicFamilyTier']) 'sonnet'
Expect 'rim single supports1m false' ($r[0]['supports1m']) 'False'

# Explicit anthropicFamilyTier is used verbatim, NOT overwritten by position.
$r = Resolve-InferenceModels -ModelsJson '[{"name":"x","labelOverride":"y","anthropicFamilyTier":"opus"}]'
Expect 'rim explicit tier respected' ($r[0]['anthropicFamilyTier']) 'opus'

# Extra unknown field preserved verbatim.
$r = Resolve-InferenceModels -ModelsJson '[{"name":"x","labelOverride":"y","foo":"bar"}]'
Expect 'rim extra field preserved' ($r[0]['foo']) 'bar'

# Index within the 5-tier list maps by position (0=sonnet,1=opus,2=haiku,3=fable,4=mythos).
$r = Resolve-InferenceModels -ModelsJson '[{"name":"a","labelOverride":"A"},{"name":"b","labelOverride":"B"},{"name":"c","labelOverride":"C"},{"name":"d","labelOverride":"D"}]'
Expect 'rim 4-entry count' ($r.Count) '4'
Expect 'rim entry3 tier default fable' ($r[3]['anthropicFamilyTier']) 'fable'
# Index >= 5 (beyond the tier list) -> falls back to sonnet.
$r = Resolve-InferenceModels -ModelsJson '[{"name":"a","labelOverride":"A"},{"name":"b","labelOverride":"B"},{"name":"c","labelOverride":"C"},{"name":"d","labelOverride":"D"},{"name":"e","labelOverride":"E"},{"name":"f","labelOverride":"F"}]'
Expect 'rim entry5 tier fallback sonnet' ($r[5]['anthropicFamilyTier']) 'sonnet'

# Not an array (bare object) -> throws.
$threw = $false
try { Resolve-InferenceModels -ModelsJson '{"name":"x","labelOverride":"y"}' } catch { $threw = $true }
Expect 'rim object-not-array throws' $threw 'True'

# Element missing name -> throws.
$threw = $false
try { Resolve-InferenceModels -ModelsJson '[{"labelOverride":"y"}]' } catch { $threw = $true }
Expect 'rim missing name throws' $threw 'True'

# Element missing labelOverride -> throws.
$threw = $false
try { Resolve-InferenceModels -ModelsJson '[{"name":"x"}]' } catch { $threw = $true }
Expect 'rim missing label throws' $threw 'True'

# Non-object element (bare string) -> throws.
$threw = $false
try { Resolve-InferenceModels -ModelsJson '["bare-string"]' } catch { $threw = $true }
Expect 'rim bare-string element throws' $threw 'True'

# Invalid JSON -> throws.
$threw = $false
try { Resolve-InferenceModels -ModelsJson 'not-json' } catch { $threw = $true }
Expect 'rim invalid json throws' $threw 'True'

# Write-GatewayConfigEntry with -ResolvedModels: full rebuild replaces existing.
$trm = Join-Path $env:TEMP ('test_models_' + [guid]::NewGuid().ToString('N') + '.json')
'{"inferenceModels":[{"name":"old-model","labelOverride":"Old"}]}' | Out-File $trm -Encoding utf8
$custom = Resolve-InferenceModels -ModelsJson '[{"name":"glm-5.3","labelOverride":"opus-4.8"}]'
$null = Write-GatewayConfigEntry -Path $trm -BaseUrl 'https://gw.example/' -ApiKey 'k' -AuthScheme 'bearer' -ResolvedModels $custom -ModelsSupplied $true
$written = [System.IO.File]::ReadAllText($trm) | ConvertFrom-Json
Expect 'wge -Models rebuilds count' (@($written.inferenceModels).Count) '1'
Expect 'wge -Models rebuilds name' ($written.inferenceModels[0].name) 'glm-5.3'
Expect 'wge -Models rebuilds label' ($written.inferenceModels[0].labelOverride) 'opus-4.8'
Expect 'wge -Models rebuilds tier filled' ($written.inferenceModels[0].anthropicFamilyTier) 'sonnet'
Expect 'wge -Models old catalog gone' ($written.inferenceModels[0].name -eq 'old-model') 'False'
Remove-Item -Force $trm -ErrorAction SilentlyContinue

# Write-GatewayConfigEntry without -ResolvedModels: pristine injects default 3.
$trm2 = Join-Path $env:TEMP ('test_pristine_' + [guid]::NewGuid().ToString('N') + '.json')
$null = Write-GatewayConfigEntry -Path $trm2 -BaseUrl 'https://gw.example/' -ApiKey 'k' -AuthScheme 'bearer'
$written2 = [System.IO.File]::ReadAllText($trm2) | ConvertFrom-Json
Expect 'wge pristine default catalog count' (@($written2.inferenceModels).Count) '3'
Expect 'wge pristine entry0 sonnet' ($written2.inferenceModels[0].name) 'claude-sonnet-5-5'
Remove-Item -Force $trm2 -ErrorAction SilentlyContinue

# Write-GatewayConfigEntry without -ResolvedModels: existing catalog untouched.
$trm3 = Join-Path $env:TEMP ('test_existing_' + [guid]::NewGuid().ToString('N') + '.json')
'{"inferenceModels":[{"name":"user-model","labelOverride":"User"}]}' | Out-File $trm3 -Encoding utf8
$null = Write-GatewayConfigEntry -Path $trm3 -BaseUrl 'https://gw.example/' -ApiKey 'k' -AuthScheme 'bearer'
$written3 = [System.IO.File]::ReadAllText($trm3) | ConvertFrom-Json
Expect 'wge existing catalog preserved count' (@($written3.inferenceModels).Count) '1'
Expect 'wge existing catalog preserved name' ($written3.inferenceModels[0].name) 'user-model'
Remove-Item -Force $trm3 -ErrorAction SilentlyContinue

# Write-GatewayConfigEntry with -ModelsSupplied + empty array: clears catalog.
$trm4 = Join-Path $env:TEMP ('test_empty_' + [guid]::NewGuid().ToString('N') + '.json')
'{"inferenceModels":[{"name":"old-model","labelOverride":"Old"}]}' | Out-File $trm4 -Encoding utf8
$empty = Resolve-InferenceModels -ModelsJson '[]'
$null = Write-GatewayConfigEntry -Path $trm4 -BaseUrl 'https://gw.example/' -ApiKey 'k' -AuthScheme 'bearer' -ResolvedModels $empty -ModelsSupplied $true
$written4 = [System.IO.File]::ReadAllText($trm4) | ConvertFrom-Json
Expect 'wge -Models [] clears catalog (count 0)' (@($written4.inferenceModels).Count) '0'
Expect 'wge -Models [] inferenceModels is an array' ($written4.inferenceModels -is [System.Array]) 'True'
Remove-Item -Force $trm4 -ErrorAction SilentlyContinue

# Write-GatewayConfigEntry without -ModelsSupplied: existing EMPTY array [] preserved.
$trm5 = Join-Path $env:TEMP ('test_existing_empty_' + [guid]::NewGuid().ToString('N') + '.json')
'{"inferenceModels":[]}' | Out-File $trm5 -Encoding utf8
$null = Write-GatewayConfigEntry -Path $trm5 -BaseUrl 'https://gw.example/' -ApiKey 'k' -AuthScheme 'bearer'
$written5 = [System.IO.File]::ReadAllText($trm5) | ConvertFrom-Json
Expect 'wge existing [] preserved (count 0, not seeded with 3)' (@($written5.inferenceModels).Count) '0'
Remove-Item -Force $trm5 -ErrorAction SilentlyContinue

# Merge isolation WITH -ResolvedModels: custom field survives, old models gone.
$trm6 = Join-Path $env:TEMP ('test_merge_rebuild_' + [guid]::NewGuid().ToString('N') + '.json')
'{"customField":"keep-me","inferenceModels":[{"name":"old","labelOverride":"Old"}]}' | Out-File $trm6 -Encoding utf8
$rb = Resolve-InferenceModels -ModelsJson '[{"name":"new","labelOverride":"New"}]'
$null = Write-GatewayConfigEntry -Path $trm6 -BaseUrl 'https://gw.example/' -ApiKey 'k' -AuthScheme 'bearer' -ResolvedModels $rb -ModelsSupplied $true
$written6 = [System.IO.File]::ReadAllText($trm6) | ConvertFrom-Json
Expect 'wge rebuild preserves customField' ($written6.customField) 'keep-me'
Expect 'wge rebuild old model gone' ($written6.inferenceModels[0].name) 'new'
Expect 'wge rebuild count 1' (@($written6.inferenceModels).Count) '1'
Remove-Item -Force $trm6 -ErrorAction SilentlyContinue

# Single-object (non-array) existing inferenceModels + no -Models: untouched, no crash.
$trm7 = Join-Path $env:TEMP ('test_single_obj_' + [guid]::NewGuid().ToString('N') + '.json')
'{"inferenceModels":{"name":"weird","labelOverride":"Weird"}}' | Out-File $trm7 -Encoding utf8
$null = Write-GatewayConfigEntry -Path $trm7 -BaseUrl 'https://gw.example/' -ApiKey 'k' -AuthScheme 'bearer'
$written7 = [System.IO.File]::ReadAllText($trm7) | ConvertFrom-Json
Expect 'wge single-object existing untouched' ($written7.inferenceModels.name) 'weird'
Remove-Item -Force $trm7 -ErrorAction SilentlyContinue

# Resolve-InferenceModels: 5-tier default by position (idx 3=fable, idx 4=mythos).
$big = Resolve-InferenceModels -ModelsJson '[{"name":"a","labelOverride":"A"},{"name":"b","labelOverride":"B"},{"name":"c","labelOverride":"C"},{"name":"d","labelOverride":"D"},{"name":"e","labelOverride":"E"}]'
Expect 'rim idx3 tier fable' ($big[3].anthropicFamilyTier) 'fable'
Expect 'rim idx4 tier mythos' ($big[4].anthropicFamilyTier) 'mythos'

if ($fail -eq 0) { Write-Host ''; Write-Host 'ALL TESTS PASSED' -ForegroundColor Green }
else { Write-Host ''; Write-Host "$fail FAILURES" -ForegroundColor Red }
