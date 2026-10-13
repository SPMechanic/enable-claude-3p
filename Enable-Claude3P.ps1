<#
.SYNOPSIS
    Enable Claude Desktop (and Claude Code CLI) for the LLM-Kita third-party
    gateway ("3P" mode). One idempotent, newbie-safe script.

.DESCRIPTION
    Unified replacement for gateway.py + sync-gateway-key.ps1. One flow:
    failover health probe, write 3P config (deploymentMode + configLibrary +
    _meta), sync the CLI settings.json env block, set a user env var, optionally
    scrub stale keys and reset caches, then verify. Idempotent: re-running with
    the same key is a no-op. Works on a pristine install or an existing 3P setup.

    PowerShell 5.1, ANSI-compliant. No PS Core-only syntax.

    Failover endpoints (tried in order, first healthy one wins):
      1. https://chat-api.llm-kita.com   (default)
      2. https://api.llm-kita.com/api    (fallback)

    "Healthy" means /v1/models returns 200 AND /v1/messages returns a 2xx.
    A key valid for listing but rejected for inference is NOT accepted.

    The Claude Code CLI child (spawned by Desktop for the Code tab) reads
    env.ANTHROPIC_AUTH_TOKEN / env.ANTHROPIC_BASE_URL from settings.json at
    launch, so settings.json is synced by default. Use -NoSyncCli only when the
    CLI is deliberately pointed at another provider (OpenRouter / OpenCode /
    KiloCode).

    Default mode is DRY RUN (no writes). -Apply commits. -Interactive implies
    -Apply and adds a plain-English y/N confirm. Running Claude.exe while
    writing is warned; -Force proceeds anyway.

.PARAMETER NewKey
    Gateway API key. Omit to be prompted (masked), or to audit existing state.
.PARAMETER BaseUrl
    Override the failover probe and probe ONLY this URL. To write a URL without
    probing it at all, also pass -SkipProbe.
.PARAMETER AuthScheme
    Auth scheme written to inferenceGatewayAuthScheme. Default 'bearer'.
.PARAMETER Models
    Optional JSON array of inference model entries. Lets you present a
    gateway-served model under a custom UI label (e.g. name="glm-5.3",
    labelOverride="opus-4.8"). Each entry MUST have non-empty 'name' and
    'labelOverride'; the other fields (supports1m, isFamilyDefault, maxEffort,
    anthropicFamilyTier) are optional and filled with defaults. Full-rebuild
    semantics: the result array has EXACTLY as many entries as -Models. Passing
    -Models on an install with an existing catalog reports the current catalog
    first, then replaces it. Pass -Models '[]' to clear the catalog entirely
    (an empty array is a valid rebuild target, not omitted). anthropicFamilyTier
    defaults by position (0=sonnet, 1=opus, 2=haiku, 3=fable, 4=mythos, else
    sonnet for index 5+) unless you set it per-entry. When omitted: pristine
    installs get the hardcoded 3-model catalog (sonnet/opus/haiku); an existing
    catalog is never touched. 'name' is the wire model id sent in API requests
    (load-bearing -- a wrong value silently breaks inference); 'labelOverride'
    is UI-only. Example:
    -Models '[{"name":"glm-5.3","labelOverride":"opus-4.8"},
    {"name":"claude-haiku-5-5","labelOverride":"Haiku"}]'
    Validation failure (bad JSON or missing name/labelOverride) exits 7.
.PARAMETER Apply
    Commit changes. Without it, the script only reports and probes.
.PARAMETER SkipProbe
    Write without probing the gateway. Implies you accept the key/URL unverified.
    -Interactive will warn before confirming an unverified write.
.PARAMETER NoSyncCli
    Do NOT touch the CLI settings.json. Use when the CLI points at another
    provider (OpenRouter / OpenCode / KiloCode) and you only want the Desktop
    flipped to 3P.
.PARAMETER MachineEnv
    Also write LLM_KITA_API_KEY to HKLM (machine-wide). Requires admin.
.PARAMETER ScrubStale
    Overwrite stale keys found in history/transcripts/backups with the new key.
    Hygiene only -- nothing the app runs reads these.
.PARAMETER ScrubEnv
    Scrub HKCU\Environment (and HKLM with -MachineEnv) for stale ANTHROPIC_* /
    LLM_KITA_API_KEY values. Multi-provider SAFE: a value is removed ONLY if its
    BASE_URL host is an LLM-Kita host, or it is an empty ANTHROPIC_* value.
    Non-empty ANTHROPIC_* keys are NEVER deleted (could be another provider's).
    Audit first by omitting -Apply.
.PARAMETER ResetCaches
    Delete Electron caches (Cache, Code Cache, GPUCache, etc.). Safe; they
    regenerate on next launch.
.PARAMETER Restore
    Undo 3P: remove deploymentMode, delete the configLibrary gateway entry, zero
    _meta.json, strip CLI gateway fields from settings.json. Use with -Apply.
    -NewKey is ignored in restore mode.
.PARAMETER Interactive
    Like -Apply but prints a plain-English summary (redirect target, files
    overwritten, unverified-URL warning) and asks a y/N confirm before writing.
    Implies -Apply. The safe default for humans.
.PARAMETER Force
    Proceed with writes even while Claude.exe is running (skip the y/N prompt).

.EXAMPLE
    .\Enable-Claude3pGateway.ps1 -Interactive -NewKey "<KEY>"
    DESCRIPTION: First-time setup on a fresh install (pristine). Probes the
    gateway, creates claude_desktop_config.json with deploymentMode=3p, creates
    the configLibrary entry with the 3-model catalog (sonnet/opus/haiku),
    writes _meta.json, creates settings.json with the gateway env block, sets
    the LLM_KITA_API_KEY user env var, then asks a y/N confirm before writing.
    RECOMMENDED for non-experts.

.EXAMPLE
    .\Enable-Claude3pGateway.ps1
    DESCRIPTION: Audit only (dry run). Reports current 3P state, probes both
    failover endpoints, lists every credential location with match/no-match,
    and prints stale keys found on disk. NOTHING IS WRITTEN. Run this first if
    unsure.

.EXAMPLE
    .\Enable-Claude3pGateway.ps1 -Apply -NewKey "<KEY>" -Force
    DESCRIPTION: Non-interactive apply (CI/automation). Commits without
    prompting, forces past running Claude.exe. Same writes as -Interactive.

.EXAMPLE
    .\Enable-Claude3pGateway.ps1 -Interactive
    DESCRIPTION: Rotate the key interactively. Prompts for the new key (masked),
    probes it, shows what will change, asks y/N. Omits -NewKey so the script
    reads the key from the masked prompt.

.EXAMPLE
    .\Enable-Claude3pGateway.ps1 -Apply -NewKey "<KEY>"
    DESCRIPTION: Recover from a bad base URL. Omit -BaseUrl; both failover
    endpoints are probed, the first healthy one wins and is written.

.EXAMPLE
    .\Enable-Claude3pGateway.ps1 -Apply -NewKey "<KEY>" -ScrubStale -ScrubEnv -ResetCaches -Force
    DESCRIPTION: Full hygiene pass. Syncs the key, overwrites stale keys in
    history/transcripts, scrubs stale registry env vars (multi-provider safe),
    and clears Electron caches. Use after a key compromise or rotation.

.EXAMPLE
    .\Enable-Claude3pGateway.ps1 -Restore -Apply -Force
    DESCRIPTION: Revert to stock Anthropic mode. Removes deploymentMode, deletes
    the configLibrary gateway entry, zeros _meta.json, and strips the CLI
    gateway fields from settings.json.

.EXAMPLE
    .\Enable-Claude3pGateway.ps1 -Apply -NewKey "<KEY>" -NoSyncCli
    DESCRIPTION: Flip Desktop to 3P but leave the CLI settings.json alone (the
    CLI points at OpenRouter / OpenCode / KiloCode). Writes only the Desktop
    configLibrary + deploymentMode + user env var.

.NOTES
    PREREQUISITES:
      - PowerShell 5.1+ (Windows). Run from any cwd.
      - Git for Windows STRONGLY RECOMMENDED. The pristine settings.json template
        hardcodes CLAUDE_CODE_GIT_BASH_PATH and ships Bash(git ...) allow entries.
        Without Git, those allow entries are non-functional (the CLI still works
        via the PowerShell tool). The script warns at apply time if Git is absent.
      - Claude Desktop and/or Claude Code CLI installed (winget or MSIX).

    IDEAL PARAMS -- pick the row that matches your situation:

      Pristine, first-time, non-expert   : -Interactive -NewKey "<KEY>"
      Pristine, CI/automation            : -Apply -NewKey "<KEY>" -Force
      Dirty, key rotation, interactive   : -Interactive   (prompts for key)
      Dirty, bad URL recovery            : -Apply -NewKey "<KEY>"   (no -BaseUrl)
      Dirty, full hygiene                : -Apply -NewKey "<KEY>" -ScrubStale -ScrubEnv -ResetCaches -Force
      Restore to stock Anthropic         : -Restore -Apply -Force
      CLI on another provider            : -Apply -NewKey "<KEY>" -NoSyncCli

    EXIT CODES:
      0 success/no-op
      1 no key sourced
      2 probe failed under -Apply
      3 settings.json invalid after write
      4 configLibrary re-parse invalid
      5 non-interactive without -Force while Claude.exe running
      6 .claude.json invalid after write
      7 -Models validation failed (bad JSON or missing name/labelOverride)

    NEWBIE NOTE: -Interactive is the safe default for humans. It prints what
    will change and asks y/N. If unsure, run with NO flags first to audit
    (nothing is written). The script NEVER deletes a non-empty ANTHROPIC_*
    registry value, so a parallel OpenRouter/OpenCode/KiloCode subscription is
    preserved.

.LINK
    https://chat-api.llm-kita.com
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$NewKey,
    [string]$BaseUrl,
    [string]$AuthScheme = 'bearer',
    [string]$Models,
    [switch]$Apply,
    [switch]$SkipProbe,
    [switch]$NoSyncCli,
    [switch]$MachineEnv,
    [switch]$ScrubStale,
    [switch]$ScrubEnv,
    [switch]$ResetCaches,
    [switch]$Restore,
    [switch]$Interactive,
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$SyncCli = -not $NoSyncCli
$ConfigId     = '00000000-0000-4000-8000-000000000114'
$DefaultName  = 'Claude-LLM-Kita'
$FailoverUrls = @('https://chat-api.llm-kita.com', 'https://api.llm-kita.com/api')
$DefaultBaseUrl = $FailoverUrls[0]
$Claude3pDir   = Join-Path $env:LOCALAPPDATA 'Claude-3p'
$CfgLibDir     = Join-Path $Claude3pDir 'configLibrary'
$CfgLibMeta    = Join-Path $CfgLibDir '_meta.json'
$DesktopCfg    = Join-Path $Claude3pDir 'claude_desktop_config.json'
$SettingsPath  = Join-Path $env:USERPROFILE '.claude\settings.json'
$ClaudeStatePath = Join-Path $env:USERPROFILE '.claude.json'
$TranscriptsDir = Join-Path $env:USERPROFILE '.claude\projects'
$LogPath       = Join-Path $Claude3pDir 'logs\main.log'
$KeyPattern = 'sk-kita-[A-Za-z0-9]{8,}|[a-z]{2}-[a-z]{4}-[A-Za-z0-9]{25,}'
function Get-Fingerprint {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return '<empty>' }
    $k = $Key.Trim()
    if ($k.Length -le 8) { return "$($k.Length)chars" }
    return "$($k.Substring(0, 4))...$($k.Substring($k.Length - 4)) [$($k.Length)chars]"
}
function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '<no file>' }
    $leaf = Split-Path $Path -Leaf
    if ($leaf -match '\.bak(\.|$)') { return '<already a backup>' }
    $base = "$Path.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $bak = $base
    $n = 1
    while (Test-Path $bak) { $bak = "$base.$n"; $n++ }
    if ($bak.Length -ge 245) { return '<path too long>' }
    Copy-Item -LiteralPath $Path -Destination $bak -Force
    return (Split-Path $bak -Leaf)
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
    # The old pattern only matched comma+} at END-OF-STRING, so removing the LAST
    # field in a nested object (e.g. env.ANTHROPIC_API_KEY when it sat last in env)
    # left a dangling "},}" -> invalid JSON. Match comma + optional whitespace +
    # } anywhere (non-greedy across the whole file, first occurrence).
    $new = [regex]::Replace($new, ',(\s*\})', '$1', 1)
    [System.IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Set-ClaudeStateOnboarding {
    <#
        Check-and-fill the CLI first-run onboarding bools in ~/.claude.json.
        Only ADDS a field when it is absent -- never overwrites. Preserves every
        other field the app owns (machineID, userID, firstStartTime, migrationVersion,
        pluginUsage, skillUsage, projects, etc.). Returns $true if the file changed,
        $false if no-op, and throws on a parse error (so the caller can report it
        rather than printing a misleading "already current").
        StrictMode-safe: uses PSObject.Properties indexer (null on missing), not dot-access.
        Type-safe: rejects non-object JSON (array/scalar) which would corrupt the file.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $obj = $null
    if (Test-Path $Path) {
        try { $obj = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json }
        catch { throw "Could not parse $Path as JSON: $_" }
    }
    else { $obj = [PSCustomObject]@{} }
    if (-not $obj) { $obj = [PSCustomObject]@{} }
    # Guard against non-object JSON (array/scalar) -- Add-Member on those silently
    # corrupts the structure. The app always writes an object; anything else is damage.
    if (-not ($obj -is [System.Management.Automation.PSCustomObject])) {
        throw "$Path is not a JSON object (type: $($obj.GetType().Name)); refusing to modify"
    }
    $added = $false
    foreach ($f in 'hasCompletedOnboarding', 'hasTrustDialogAccepted', 'hasResetAutoModeOptInForDefaultOffer') {
        $prop = $obj.PSObject.Properties[$f]
        if (-not $prop) {
            $obj | Add-Member -MemberType NoteProperty -Name $f -Value $true
            $added = $true
        }
    }
    # Sentinel: records that THIS script seeded the onboarding bools so Restore
    # can remove only those (not bools the user set via stock onboarding). Added
    # only when we actually seeded, and only if the sentinel is itself absent.
    if ($added -and -not ($obj.PSObject.Properties['_enableClaude3pSeededOnboarding'])) {
        $obj | Add-Member -MemberType NoteProperty -Name '_enableClaude3pSeededOnboarding' -Value $true
    }
    if (-not $added) { return $false }
    # Depth 50: .claude.json can carry deeply-nested projects/pluginUsage/skillUsage.
    # ConvertTo-Json truncates beyond -Depth by substituting type-name strings, which
    # is valid JSON (passes re-parse) but destroys data. 50 is well beyond anything
    # the app writes while still bounded.
    $json = $obj | ConvertTo-Json -Depth 50
    $oldRaw = if (Test-Path $Path) { [System.IO.File]::ReadAllText($Path) } else { '' }
    if ($json -ceq $oldRaw) { return $false }
    $null = Backup-File $Path
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Ensure-DesktopDeploymentMode {
    <#
        Ensure claude_desktop_config.json has deploymentMode="3p". Set-JsonStringField
        can only UPDATE an existing field via regex -- it cannot INSERT one. If the
        stock app created the file (e.g. for MCP-server config) without deploymentMode,
        a regex-only path silently never adds it and the Desktop never enters 3P mode.
        Parse/merge/serialize so an absent field is inserted; preserve every other key.
        Returns $true if the file was rewritten.
    #>
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
    $json = $obj | ConvertTo-Json -Depth 50
    if ($json -ceq $raw) { return $false }
    $null = Backup-File $Path
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Get-GatewayModelId {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Base)
    try {
        $r = Invoke-WebRequest -Uri "$Base/v1/models" -Headers @{ 'x-api-key' = $Key } -UseBasicParsing -TimeoutSec 20
        $ids = @(($r.Content | ConvertFrom-Json).data | ForEach-Object { $_.id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($ids -contains 'auto') { return 'auto' }
        if ($ids.Count -gt 0) { return $ids[0] }
    }
    catch { }
    return $null
}
function Test-GatewayKey {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Base)
    $out = @{ Models = 'not tested'; Messages = 'not tested' }
    try {
        $r = Invoke-WebRequest -Uri "$Base/v1/models" -Headers @{ 'x-api-key' = $Key } -UseBasicParsing -TimeoutSec 20
        $out.Models = [string]$r.StatusCode
    }
    catch {
        $resp = $null
        try { $resp = $_.Exception.Response } catch { }
        if ($resp -and $resp.StatusCode) { $out.Models = "HTTP $([int]$resp.StatusCode)" }
        else { $out.Models = 'unreachable/timeout' }
    }
    if ($out.Models -eq '200') {
        $modelId = Get-GatewayModelId -Key $Key -Base $Base
        if (-not $modelId) { $out.Messages = 'skipped (no model id)'; return $out }
        $body = @{ model = $modelId; max_tokens = 8; messages = @(@{ role = 'user'; content = 'ping' }) } | ConvertTo-Json -Depth 5
        try {
            $r = Invoke-WebRequest -Uri "$Base/v1/messages" -Method Post -Headers @{ 'x-api-key' = $Key; 'anthropic-version' = '2023-06-01'; 'content-type' = 'application/json' } -Body $body -UseBasicParsing -TimeoutSec 25
            $out.Messages = "$([string]$r.StatusCode) (model=$modelId)"
        }
        catch {
            $resp = $null
            try { $resp = $_.Exception.Response } catch { }
            if ($resp -and $resp.StatusCode) { $out.Messages = "HTTP $([int]$resp.StatusCode) (model=$modelId)" }
            else { $out.Messages = 'unreachable/timeout' }
        }
    }
    return $out
}
function Resolve-Claude3pDirs {
    $dirs = New-Object System.Collections.Generic.List[string]
    # Always include $Claude3pDir as a write target. On a pristine winget
    # install this dir does not exist yet -- the app creates %LOCALAPPDATA%
    # \Claude-3p on first 3P launch. The Apply loop below mkdir's it before
    # writing, mirroring gateway.py's get_claude_3p_dir() + apply_patch()
    # (which returns the legacy path unconditionally then mkdir's it). The
    # previous `if (Test-Path $Claude3pDir)` gate made the list empty on a
    # fresh machine, which under Set-StrictMode -Version Latest surfaced as
    # "The property 'Count' cannot be found on this object" at the caller.
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
    # Prevent PowerShell from unwrapping an empty (or single-element) array to
    # $null at the return boundary. Under Set-StrictMode -Version Latest the
    # caller's `$dirs.Count` then throws "The property 'Count' cannot be found
    # on this object" -- the crash on a pristine install. The unary-comma
    # wrapper defeats the pipeline unwrap for all element counts (0, 1, and N).
    return ,$dirs.ToArray()
}
function Get-RunningClaudeProcs {
    $out = @{ Desktop = @(); Cli = @() }
    $procs = $null
    try { $procs = Get-Process -Name Claude -ErrorAction SilentlyContinue }
    catch { }
    if (-not $procs) { return $out }
    foreach ($p in $procs) {
        $path = $null
        try { $path = $p.Path } catch { }
        if (-not $path) { continue }
        if ($path -like '*\WindowsApps\*\app\Claude.exe') { $out.Desktop += $p.Id }
        elseif ($path -like '*\Claude-3p\claude-code\*\claude.exe') { $out.Cli += $p.Id }
    }
    return $out
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

    # Model catalog injection:
    #   - -Models passed ($ModelsSupplied): full rebuild. Replaces whatever is
    #     there with exactly the resolved entries (an empty '[]' clears it).
    #     Branch on $ModelsSupplied, NOT $ResolvedModels truthiness -- an empty
    #     array is a valid rebuild target but is falsy in PowerShell.
    #   - Pristine install (no existing inferenceModels) + no -Models: inject the
    #     default 3-model catalog (sonnet/opus/haiku).
    #   - Existing catalog + no -Models: untouched (user's UI config).
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
    # Back up the PRE-WRITE content before overwriting. Doing this here (not in
    # the caller) guarantees the backup captures the original, not the new write.
    $null = Backup-File $Path
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
function Resolve-InferenceModels {
    <#
        Pure helper: parse the -Models JSON string into a ready-to-assign array
        of hashtables (same shape as the default 3-model catalog). Each entry
        must have non-empty 'name' and 'labelOverride'; the other known fields
        are filled with defaults if absent. Throws on validation failure; the
        caller catches and exits 7. Returns [object[]] (may be empty array).
        No file I/O -- directly testable.
    #>
    param([Parameter(Mandatory)][string]$ModelsJson)

    $parsed = $null
    try { $parsed = $ModelsJson | ConvertFrom-Json }
    catch { throw "-Models is not valid JSON: $($_.Exception.Message)" }

    # ConvertFrom-Json unwraps a single-object input to a PSCustomObject (not
    # an array). Require an array.
    if ($null -eq $parsed -or -not ($parsed -is [System.Array])) {
        throw "-Models must be a JSON array."
    }

    # Position-based tier default (matches the inference config dropdown order:
    # sonnet/opus/haiku/fable/mythos). Index >= count falls back to 'sonnet'.
    $tiers = @('sonnet', 'opus', 'haiku', 'fable', 'mythos')
    $result = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($entry in $parsed) {
        if ($null -eq $entry -or -not ($entry -is [System.Management.Automation.PSCustomObject])) {
            throw "-Models[$i] must be a JSON object."
        }
        # Copy the user's properties verbatim into the hashtable first.
        $ht = [ordered]@{}
        foreach ($prop in $entry.PSObject.Properties) { $ht[$prop.Name] = $prop.Value }

        # Mandatory fields -- validate non-empty.
        $name = $ht['name']
        $label = $ht['labelOverride']
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($label)) {
            throw "-Models[$i] missing 'name' or 'labelOverride'."
        }

        # Fill defaults for the known non-mandatory fields if absent.
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
function Get-AppliedConfigPath {
    if (Test-Path $CfgLibMeta) {
        try {
            $meta = [System.IO.File]::ReadAllText($CfgLibMeta) | ConvertFrom-Json
            $prop = $meta.PSObject.Properties['appliedId']
            if ($prop -and $prop.Value) {
                $p = Join-Path $CfgLibDir "$($prop.Value).json"
                if (Test-Path $p) { return $p }
            }
        }
        catch { }
    }
    $cand = Get-ChildItem $CfgLibDir -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '_meta.json' } | Sort-Object LastWriteTime -Descending
    if ($cand) { return $cand[0].FullName }
    return $null
}
function Resolve-GitBashPath {
    <#
        Validate the CLAUDE_CODE_GIT_BASH_PATH the pristine template hardcodes.
        Returns $true if Git Bash is reachable at the standard location OR via
        the PATH `git` shim (which implies Git for Windows is installed). Returns
        $false and emits a warning otherwise -- the apply proceeds (the PowerShell
        tool + git allowlist mitigate it), but the user should know the Bash(git ...)
        allow entries are non-functional on a machine without Git.
    #>
    $hardcoded = 'C:\Program Files\Git\bin\bash.exe'
    if (Test-Path -LiteralPath $hardcoded) { return $true }
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        # `git` on PATH usually lives under Git for Windows; derive bash from it.
        $gitDir = Split-Path $gitCmd.Source -Parent
        $cand = Join-Path $gitDir 'bash.exe'
        if (Test-Path -LiteralPath $cand) { return $true }
        $cand2 = Join-Path (Split-Path $gitDir -Parent) 'bin\bash.exe'
        if (Test-Path -LiteralPath $cand2) { return $true }
        return $true   # git exists somewhere; bash is almost certainly present
    }
    return $false
}
function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host ("=" * 74) -ForegroundColor DarkGray
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host ("=" * 74) -ForegroundColor DarkGray
}
function Ensure-SettingsEnvFields {
    <#
        Set-JsonStringField can only UPDATE an existing field, not INSERT one.
        If settings.json exists but lacks env.ANTHROPIC_AUTH_TOKEN /
        ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL (or has no env block at all),
        rewrite it via parse/merge/serialize so the regex edit later can hit.
        Also seeds the universal 3P env vars (API_TIMEOUT_MS, autocompact,
        nonessential-traffic disable, PowerShell tool, tool search) that the
        pristine template carries -- so an existing install upgrading to this
        script version gets the same defaults without a full template overwrite.
        Only ADDS absent keys; never overwrites a value the user already set.
        Returns $true if the file was rewritten. Preserves every other field.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $raw = [System.IO.File]::ReadAllText($Path)
    $obj = $null
    try { $obj = $raw | ConvertFrom-Json } catch { return $false }
    if (-not $obj) { return $false }

    # Ensure an env object exists.
    if (-not ($obj.PSObject.Properties['env'])) {
        $obj | Add-Member -MemberType NoteProperty -Name 'env' -Value ([ordered]@{})
    }
    $envObj = $obj.env
    $added = $false
    # Gateway placeholders -- the caller fills these via Set-JsonStringField next.
    foreach ($f in @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL')) {
        if (-not ($envObj.PSObject.Properties[$f])) {
            $envObj | Add-Member -MemberType NoteProperty -Name $f -Value ''
            $added = $true
        }
    }
    # Universal 3P defaults (only if absent -- never clobber an existing value).
    $universal = [ordered]@{
        'API_TIMEOUT_MS'                       = '3000000'
        'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'      = '80'
        'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC' = '1'
        'CLAUDE_CODE_USE_POWERSHELL_TOOL'      = '1'
        'ENABLE_TOOL_SEARCH'                   = 'true'
    }
    foreach ($k in $universal.Keys) {
        if (-not ($envObj.PSObject.Properties[$k])) {
            $envObj | Add-Member -MemberType NoteProperty -Name $k -Value $universal[$k]
            $added = $true
        }
    }
    if (-not $added) { return $false }
    # Back up the PRE-WRITE content before overwriting. Doing this here (not in
    # the caller) guarantees the backup captures the original, not the new write.
    $null = Backup-File $Path
    $json = $obj | ConvertTo-Json -Depth 50
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}
Write-Head 'Claude-3P gateway enablement'
# Validate -Models (after all helpers are defined, before any mode branch) so a
# bad value fails fast in dry run, apply, restore, and interactive alike.
# Exit 7 = bad user input (distinct from 3/6 on-disk parse failures).
# $ModelsSupplied tracks whether the user passed -Models at all (distinct from
# $ResolvedModels truthiness, because an empty array '[]' is a valid rebuild
# target that is falsy in PowerShell).
$ResolvedModels = $null
$ModelsSupplied = $false
if ($Models) {
    try { $ResolvedModels = Resolve-InferenceModels -ModelsJson $Models }
    catch {
        Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ' -Models validation failed. See the .PARAMETER Models docs.' -ForegroundColor Yellow
        exit 7
    }
    $ModelsSupplied = $true
}
$Mode = if ($Restore) { 'RESTORE' } elseif ($Interactive) { 'INTERACTIVE' } elseif ($Apply) { 'APPLY' } else { 'DRY RUN (nothing will be written)' }
Write-Host " Mode: $Mode" -ForegroundColor Yellow
$dirs = Resolve-Claude3pDirs
if ($dirs.Count -eq 0) { Write-Host ' No Claude-3p install found. Nothing to configure.' -ForegroundColor Red; exit 1 }
Write-Host " Install(s):"
foreach ($d in $dirs) { Write-Host "   - $d" -ForegroundColor DarkGray }
if ($Restore) {
    if ($NewKey) { Write-Host ' WARNING: -NewKey is ignored in -Restore mode (restore removes the gateway config, it does not rotate the key).' -ForegroundColor Yellow }
    if (-not $Apply) {
        Write-Host ''
        Write-Host ' Dry run: would remove deploymentMode, delete the configLibrary' -ForegroundColor Yellow
        Write-Host " entry ($ConfigId), and zero _meta.json. Re-run with -Apply." -ForegroundColor Yellow
        exit 0
    }
    $procs = Get-RunningClaudeProcs
    $runningCount = $procs.Desktop.Count + $procs.Cli.Count
    if ($runningCount -gt 0 -and -not $Force) {
        Write-Host ''
        Write-Host " WARNING: $runningCount Claude.exe process(es) running." -ForegroundColor Yellow
        if ($procs.Desktop.Count) { Write-Host "   Desktop PIDs: $($procs.Desktop -join ', ')" -ForegroundColor Yellow }
        if ($procs.Cli.Count)     { Write-Host "   CLI PIDs:     $($procs.Cli -join ', ')" -ForegroundColor Yellow }
        Write-Host '   Config is read at launch. Restart required to pick up changes.' -ForegroundColor Yellow
        if (-not [Console]::IsInputRedirected) {
            $ans = Read-Host ' Proceed? (y/N)'
            if ($ans -ne 'y' -and $ans -ne 'Y') { exit 5 }
        }
        else { exit 5 }
    }
    $any = $false
    foreach ($d in $dirs) {
        $desk = Join-Path $d 'claude_desktop_config.json'
        $libDir = Join-Path $d 'configLibrary'
        $entry = Join-Path $libDir "$ConfigId.json"
        $meta = Join-Path $libDir '_meta.json'
        if (Test-Path $desk) {
            $bak = Backup-File $desk
            if (Remove-JsonField -Path $desk -Field 'deploymentMode') {
                $any = $true
                Write-Host "   $desk :: deploymentMode removed  (backup: $bak)" -ForegroundColor Green
            }
        }
        if (Test-Path $entry) {
            $bak = Backup-File $entry
            Remove-Item -LiteralPath $entry -Force
            $any = $true
            Write-Host "   $entry :: deleted  (backup: $bak)" -ForegroundColor Green
        }
        if (Test-Path $meta) {
            # D2: content-compare before rewriting. The previous code backed up and
            # rewrote _meta.json on every Restore, stacking a .bak even when the
            # file was already zeroed. Compare first; only write (and back up) if
            # the content actually differs.
            $zeroed = '{"appliedId":"","entries":[]}'
            $curMeta = [System.IO.File]::ReadAllText($meta)
            if ($curMeta -cne $zeroed) {
                $bak = Backup-File $meta
                [System.IO.File]::WriteAllText($meta, $zeroed, (New-Object System.Text.UTF8Encoding($false)))
                $any = $true
                Write-Host "   $meta :: zeroed  (backup: $bak)" -ForegroundColor Green
            }
        }
    }
    if ($SyncCli) {
        $cur = [Environment]::GetEnvironmentVariable('LLM_KITA_API_KEY', 'User')
        if ($cur) {
            [Environment]::SetEnvironmentVariable('LLM_KITA_API_KEY', $null, 'User')
            Write-Host '   User env :: LLM_KITA_API_KEY cleared' -ForegroundColor Green
        }
        # Strip the CLI env fields so a standalone CLI launch no longer hits the
        # gateway. Without this, restore leaves settings.json pointing at the
        # 3P endpoint -- defeating "restore to stock".
        if (Test-Path $SettingsPath) {
            $bak = Backup-File $SettingsPath
            $stripped = $false
            foreach ($f in @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL')) {
                if (Remove-JsonField -Path $SettingsPath -Field $f) { $stripped = $true }
            }
            if ($stripped) {
                $any = $true   # D3: settings.json strip must count as "something restored"
                Write-Host "   settings.json :: ANTHROPIC_* gateway fields removed  (backup: $bak)" -ForegroundColor Green
            }
        }
        # D1: remove the onboarding bools ONLY if our sentinel proves this script
        # seeded them. A user who completed stock onboarding before applying 3P
        # never gets the sentinel, so their bools (and wizard-suppression state)
        # are left intact -- Restore undoes exactly what this script did.
        if (Test-Path $ClaudeStatePath) {
            $stateObj = $null
            try { $stateObj = [System.IO.File]::ReadAllText($ClaudeStatePath) | ConvertFrom-Json }
            catch { }   # corrupt .claude.json: skip sentinel check, don't touch it
            if ($stateObj -and ($stateObj -is [System.Management.Automation.PSCustomObject]) -and $stateObj.PSObject.Properties['_enableClaude3pSeededOnboarding']) {
                $bak = Backup-File $ClaudeStatePath
                $removedBool = $false
                foreach ($f in 'hasCompletedOnboarding', 'hasTrustDialogAccepted', 'hasResetAutoModeOptInForDefaultOffer') {
                    if (Remove-JsonField -Path $ClaudeStatePath -Field $f) { $removedBool = $true }
                }
                if (Remove-JsonField -Path $ClaudeStatePath -Field '_enableClaude3pSeededOnboarding') { $removedBool = $true }
                if ($removedBool) {
                    $any = $true
                    Write-Host "   .claude.json :: onboarding bools + sentinel removed  (backup: $bak)" -ForegroundColor Green
                }
            }
        }
    }
    if ($any) { Write-Host ''; Write-Host ' RESTORE COMPLETE. Fully quit and relaunch Claude.' -ForegroundColor Green }
    else { Write-Host ' Already stock. Nothing to restore.' -ForegroundColor DarkGray }
    exit 0
}
Write-Head 'Key sourcing'
$cfgPath = Get-AppliedConfigPath
if (-not $NewKey -and -not [Console]::IsInputRedirected) {
    $secure = Read-Host -Prompt ' New gateway key (leave blank to audit current state)' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try   { $NewKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if ($NewKey) { $NewKey = $NewKey.Trim() }
$Sourcing = 'none'
if (-not $NewKey) {
    $NewKey = Get-JsonStringField -Path $SettingsPath -Field 'ANTHROPIC_AUTH_TOKEN'
    if (-not $NewKey -and $cfgPath) { $NewKey = Get-JsonStringField -Path $cfgPath -Field 'inferenceGatewayApiKey' }
    $Sourcing = if ($NewKey) { 'existing config' } else { 'none' }
}
else { $Sourcing = 'supplied' }
if ([string]::IsNullOrWhiteSpace($NewKey)) { Write-Host ' No key supplied and none found. Nothing to do.' -ForegroundColor Red; exit 1 }
Write-Host " Key:  $(Get-Fingerprint $NewKey)   [source: $Sourcing]"
Write-Head 'Gateway probe (failover)'
$probe = $null
$ChosenBaseUrl = $null
if ($SkipProbe) {
    $ChosenBaseUrl = if ($BaseUrl) { $BaseUrl } else { $DefaultBaseUrl }
    Write-Host " Skipped (-SkipProbe). Using $ChosenBaseUrl" -ForegroundColor Yellow
}
elseif ($BaseUrl) {
    $probe = Test-GatewayKey -Key $NewKey -Base $BaseUrl
    if ($probe.Models -eq '200') { $ChosenBaseUrl = $BaseUrl }
    $colour = if ($probe.Models -eq '200') { 'Green' } else { 'Red' }
    Write-Host " /v1/models   : $($probe.Models)   ($BaseUrl)" -ForegroundColor $colour
    Write-Host " /v1/messages : $($probe.Messages)" -ForegroundColor $colour
}
else {
    foreach ($u in $FailoverUrls) {
        $p = Test-GatewayKey -Key $NewKey -Base $u
        $colour = if ($p.Models -eq '200') { 'Green' } else { 'DarkYellow' }
        Write-Host " /v1/models   : $($p.Models)   ($u)" -ForegroundColor $colour
        # Require BOTH models AND messages to be healthy -- a key valid for listing
        # but rejected for inference must not be accepted as "configured".
        if ($p.Models -eq '200' -and $p.Messages -like '2*') {
            Write-Host " /v1/messages : $($p.Messages)" -ForegroundColor Green
            $ChosenBaseUrl = $u
            $probe = $p
            break
        }
        elseif ($p.Models -eq '200') {
            Write-Host " /v1/messages : $($p.Messages)  (partial health -- skipping this endpoint)" -ForegroundColor DarkYellow
        }
    }
    if (-not $ChosenBaseUrl) {
        $probe = Test-GatewayKey -Key $NewKey -Base $FailoverUrls[0]
        Write-Host ' All failover endpoints unreachable.' -ForegroundColor Red
    }
}
if ($Interactive) { $Apply = $true }
$confirmed = $false
if (-not $ChosenBaseUrl -and $Apply -and -not $SkipProbe) {
    Write-Host ''
    Write-Host ' REFUSING TO WRITE: no gateway endpoint accepted this key.' -ForegroundColor Red
    Write-Host ' Re-run with -SkipProbe to override.' -ForegroundColor Red
    exit 2
}
if (-not $ChosenBaseUrl -and -not $Apply) {
    $ChosenBaseUrl = if ($BaseUrl) { $BaseUrl } else { $DefaultBaseUrl }
    Write-Host " (dry run continues with $ChosenBaseUrl for reporting)" -ForegroundColor Yellow
}
$WriteBaseUrl = $ChosenBaseUrl.TrimEnd('/') + '/'
if ($Interactive) {
    Write-Host ''
    Write-Host ' This redirects Claude Desktop from the official Anthropic API' -ForegroundColor Yellow
    Write-Host " to the LLM-Kita gateway at: $WriteBaseUrl" -ForegroundColor Yellow
    if ($Restore) { Write-Host ' Mode: RESTORE -- 3P config will be removed, returning to stock Anthropic.' -ForegroundColor Yellow }
    else {
        if ($SyncCli) { Write-Host ' settings.json (CLI env block) will be overwritten.' -ForegroundColor Yellow }
        else { Write-Host ' settings.json left alone (-NoSyncCli).' -ForegroundColor DarkGray }
    }
    if ($SkipProbe) { Write-Host ' WARNING: gateway NOT probed (-SkipProbe). URL written UNVERIFIED.' -ForegroundColor Red }
    if ($ModelsSupplied) {
        Write-Host " Model catalog will be rebuilt with $($ResolvedModels.Count) entry/entries (-Models)." -ForegroundColor Yellow
        Write-Host ' Existing inferenceModels (if any) is reported above then replaced.' -ForegroundColor Yellow
        # Non-blocking warning if any model name doesn't look like a Claude id.
        $claudeIdPattern = '^claude-(sonnet|opus|haiku|fable|mythos|3-5|3-7|3|2-1|2|instant)[\w.-]*$'
        foreach ($m in $ResolvedModels) {
            if ($m['name'] -notmatch $claudeIdPattern) {
                Write-Host " WARNING: model name '$($m['name'])' is not a recognized Claude id." -ForegroundColor Yellow
                Write-Host '          name is the wire model id sent in API requests -- confirm the gateway serves it.' -ForegroundColor Yellow
            }
        }
    }
}
if ($Apply) {
    $procs = Get-RunningClaudeProcs
    $runningCount = $procs.Desktop.Count + $procs.Cli.Count
    if ($runningCount -gt 0 -and -not $Force) {
        Write-Head 'Running process warning'
        Write-Host " WARNING: $runningCount Claude.exe process(es) running." -ForegroundColor Yellow
        if ($procs.Desktop.Count) {
            Write-Host "   Desktop PIDs: $($procs.Desktop -join ', ')" -ForegroundColor Yellow
            Write-Host '     -> restart Claude Desktop to pick up the new config' -ForegroundColor Yellow
        }
        if ($procs.Cli.Count) {
            Write-Host "   CLI PIDs:     $($procs.Cli -join ', ')" -ForegroundColor Yellow
            Write-Host '     -> restart the CLI to pick up the new env block' -ForegroundColor Yellow
        }
        Write-Host ''
        Write-Host '   Impact: config is read at launch, not on the fly;' -ForegroundColor Yellow
        Write-Host '           host-creds regenerated at launch; running processes' -ForegroundColor Yellow
        Write-Host '           will NOT pick up these writes until restarted.' -ForegroundColor Yellow
        Write-Host ''
        if (-not [Console]::IsInputRedirected) {
            $ans = Read-Host ' Proceed anyway? (y/N)'
            if ($ans -ne 'y' -and $ans -ne 'Y') { Write-Host ' Aborted. No changes made.' -ForegroundColor Yellow; exit 5 }
            $confirmed = $true
        }
        else { Write-Host ' Non-interactive session; refusing without -Force.' -ForegroundColor Red; exit 5 }
    }
}
Write-Head 'Credential locations'
$rows = New-Object System.Collections.Generic.List[object]
function Add-Row {
    param($Name, $Path, $Current, $Role)
    $match = 'NO'
    if ([string]::IsNullOrWhiteSpace($Current)) { $match = 'empty -> set' }
    elseif ($Current -eq $NewKey) { $match = 'yes' }
    $rows.Add([pscustomobject]@{ Location = $Name; Role = $Role; Current = Get-Fingerprint $Current; Match = $match; Path = $Path })
}
$sToken = Get-JsonStringField -Path $SettingsPath -Field 'ANTHROPIC_AUTH_TOKEN'
$sKey   = Get-JsonStringField -Path $SettingsPath -Field 'ANTHROPIC_API_KEY'
$sUrl   = Get-JsonStringField -Path $SettingsPath -Field 'ANTHROPIC_BASE_URL'
Add-Row 'settings.json :: env.ANTHROPIC_AUTH_TOKEN' $SettingsPath $sToken $(if ($SyncCli) { 'written' } else { 'skipped (-NoSyncCli)' })
Add-Row 'settings.json :: env.ANTHROPIC_API_KEY'   $SettingsPath $sKey   $(if ($SyncCli) { 'written' } else { 'skipped (-NoSyncCli)' })
Add-Row 'settings.json :: env.ANTHROPIC_BASE_URL'  $SettingsPath $sUrl   $(if ($SyncCli) { 'written' } else { 'skipped (-NoSyncCli)' })
$cfgKey = if ($cfgPath) { Get-JsonStringField -Path $cfgPath -Field 'inferenceGatewayApiKey' } else { $null }
$cfgUrl = if ($cfgPath) { Get-JsonStringField -Path $cfgPath -Field 'inferenceGatewayBaseUrl' } else { $null }
Add-Row 'configLibrary :: inferenceGatewayApiKey'  $cfgPath $cfgKey 'written'
Add-Row 'configLibrary :: inferenceGatewayBaseUrl' $cfgPath $cfgUrl 'written'
$envKey = [Environment]::GetEnvironmentVariable('LLM_KITA_API_KEY', 'User')
Add-Row 'User env :: LLM_KITA_API_KEY' '(HKCU\Environment)' $envKey 'written'
$mKey = [Environment]::GetEnvironmentVariable('LLM_KITA_API_KEY', 'Machine')
$mRole = if ($MachineEnv) { 'written (-MachineEnv)' } else { 'reported' }
Add-Row 'Machine env :: LLM_KITA_API_KEY' '(HKLM\...\Environment)' $mKey $mRole
Add-Row 'desktop_cfg :: deploymentMode' $DesktopCfg $(Get-JsonStringField -Path $DesktopCfg -Field 'deploymentMode') 'written'
$rows | Format-Table -AutoSize -Property Location, Role, Current, Match
# Model catalog report: current inferenceModels vs. what would be written.
# Shows in every mode (dry run, interactive, apply) so the user sees the merge
# before it happens. Read current from the applied configLibrary entry.
if ($cfgPath -and (Test-Path $cfgPath)) {
    $curModels = $null
    try {
        $cfgObj = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json
        # Null-safe: Properties[] indexer returns $null when the key is absent
        # (do not rely on a thrown exception for the normal missing-key case).
        $prop = $cfgObj.PSObject.Properties['inferenceModels']
        if ($prop) { $curModels = $prop.Value }
    } catch { }
} else { $curModels = $null }
Write-Host ' Model catalog (inferenceModels):' -ForegroundColor Cyan
if ($curModels -and @($curModels).Count -gt 0) {
    foreach ($m in @($curModels)) {
        $mName = if ($m.PSObject.Properties['name']) { $m.name } else { '<no name>' }
        $mLabel = if ($m.PSObject.Properties['labelOverride']) { $m.labelOverride } else { '<no label>' }
        Write-Host ("   current: name={0,-28} labelOverride={1}" -f $mName, $mLabel) -ForegroundColor DarkGray
    }
} else { Write-Host '   current: (none -- pristine)' -ForegroundColor DarkGray }
if ($ModelsSupplied) {
    if ($ResolvedModels.Count -gt 0) {
        foreach ($m in $ResolvedModels) {
            Write-Host ("   would-write: name={0,-28} labelOverride={1}" -f $m['name'], $m['labelOverride']) -ForegroundColor Yellow
        }
    } else {
        Write-Host '   would-write: (empty -- -Models passed an empty array, catalog will be cleared)' -ForegroundColor Yellow
    }
    Write-Host '   (-Models passed: full rebuild replaces current)' -ForegroundColor Yellow
} else {
    Write-Host '   would-write: unchanged (default 3-model catalog on pristine; existing left as-is)' -ForegroundColor DarkGray
}
Write-Host ' Reported only (not modified):' -ForegroundColor DarkGray
$hostCreds = Get-ChildItem $Claude3pDir -Filter 'host-creds-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($hostCreds) {
    $hcTok = Get-JsonStringField -Path $hostCreds.FullName -Field 'ANTHROPIC_AUTH_TOKEN'
    $hcExp = Get-JsonStringField -Path $hostCreds.FullName -Field 'expiresAt'
    $expTxt = ''
    if ($hcExp) { try { $expTxt = ' expires ' + [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$hcExp).LocalDateTime } catch { } }
    Write-Host "   host-creds (runtime artifact, regenerated at launch): $(Get-Fingerprint $hcTok)$expTxt" -ForegroundColor DarkGray
}
$knownRaw = @{}
foreach ($v in @($sToken, $sKey, $cfgKey, $envKey, $NewKey)) { if (-not [string]::IsNullOrWhiteSpace($v)) { $knownRaw[$v] = $true } }
$stale = @{}
$staleScanRoots = @($TranscriptsDir, $Claude3pDir, (Join-Path $env:USERPROFILE '.claude'))
foreach ($root in $staleScanRoots) {
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.jsonl', '.json', '.py' -or $_.Name -match '\.bak' } | ForEach-Object {
        $t = $null
        try { $t = [System.IO.File]::ReadAllText($_.FullName) } catch { return }
        foreach ($m in [regex]::Matches($t, $KeyPattern)) { if (-not $knownRaw.ContainsKey($m.Value)) { $stale[$m.Value] = $true } }
    }
}
if ($stale.Count -gt 0) {
    Write-Host ''
    Write-Host " Stale keys on disk (history -- the app does not read these):" -ForegroundColor Yellow
    foreach ($k in ($stale.Keys | Sort-Object)) { Write-Host "   $(Get-Fingerprint $k)" -ForegroundColor Yellow }
    Write-Host ' REVOKE at the gateway, or overwrite locally with -ScrubStale.' -ForegroundColor Yellow
}
if (-not $Apply) {
    Write-Head 'Apply'
    Write-Host ' Dry run: no changes made. Re-run with -Apply to write.' -ForegroundColor Yellow
        exit 0
}
if ($Interactive -and -not $confirmed -and -not $Force) {
    if (-not [Console]::IsInputRedirected) {
        Write-Head 'Confirm'
        $ans = Read-Host ' Apply these changes? (y/N)'
        if ($ans -ne 'y' -and $ans -ne 'Y') { Write-Host ' Aborted. No changes made.' -ForegroundColor Yellow; exit 5 }
    }
    else { Write-Host ' Non-interactive session; refusing without -Force.' -ForegroundColor Red; exit 5 }
}
Write-Head 'Apply'
$changed = New-Object System.Collections.Generic.List[string]
foreach ($d in $dirs) {
    Write-Host " -> $d" -ForegroundColor Cyan
    # On a pristine install $Claude3pDir may not exist yet -- create it before
    # writing claude_desktop_config.json / configLibrary into it, otherwise
    # [IO.File]::WriteAllText throws "Could not find a part of the path".
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { try { New-Item -ItemType Directory -Path $d -Force | Out-Null } catch { } }
    $desk = Join-Path $d 'claude_desktop_config.json'
    $libDir = Join-Path $d 'configLibrary'
    $entry = Join-Path $libDir "$ConfigId.json"
    $meta = Join-Path $libDir '_meta.json'
    if (Test-Path $desk) {
        $mode = Get-JsonStringField -Path $desk -Field 'deploymentMode'
        if ($mode -ne '3p') {
            # Parse/merge/serialize (not regex-only) so a missing deploymentMode
            # field is INSERTED, not silently skipped. Backup is taken inside the
            # helper only when a write actually happens -- no orphaned .bak.
            if (Ensure-DesktopDeploymentMode -Path $desk) {
                $changed.Add("$d :: deploymentMode '$mode' -> '3p'")
                Write-Host "   deploymentMode '$mode' -> '3p'  (backup captured)" -ForegroundColor Green
            }
            else { Write-Host "   deploymentMode :: could not set (check file)" -ForegroundColor Red }
        }
        else { Write-Host "   deploymentMode already 3p" -ForegroundColor DarkGray }
    }
    else {
        [System.IO.File]::WriteAllText($desk, "{`n  `"deploymentMode`": `"3p`"`n}`n", (New-Object System.Text.UTF8Encoding($false)))
        $changed.Add("$d :: claude_desktop_config.json created")
        Write-Host "   claude_desktop_config.json created (deploymentMode=3p)" -ForegroundColor Green
    }
    if (-not (Test-Path -LiteralPath $libDir -PathType Container)) { try { New-Item -ItemType Directory -Path $libDir -Force | Out-Null } catch { } }
    # Write-GatewayConfigEntry backs up the pre-write file internally only when
    # it actually changes -- so a no-op re-run does not stack a .bak.
    if (Write-GatewayConfigEntry -Path $entry -BaseUrl $ChosenBaseUrl -ApiKey $NewKey -AuthScheme $AuthScheme -ResolvedModels $ResolvedModels -ModelsSupplied $ModelsSupplied) {
        $changed.Add("$d :: configLibrary entry")
        Write-Host "   configLibrary :: merged gateway fields  (backup captured)" -ForegroundColor Green
    }
    else { Write-Host "   configLibrary :: already current" -ForegroundColor DarkGray }
    try { $null = [System.IO.File]::ReadAllText($entry) | ConvertFrom-Json }
    catch { Write-Host "   configLibrary re-parse: INVALID -> $_" -ForegroundColor Red; exit 4 }
    $entryName = $DefaultName
    $metaObj = [ordered]@{ appliedId = $ConfigId; entries = @(@{ id = $ConfigId; name = $entryName }) }
    if (Test-Path $meta) {
        try {
            $m = [System.IO.File]::ReadAllText($meta) | ConvertFrom-Json
            if ($m.entries -and $m.entries.Count -gt 0 -and $m.entries[0].name) { $entryName = $m.entries[0].name }
            # Preserve the existing entry object's extra fields (enabled, source,
            # modifiedAt, etc.) -- only set id/name, don't flatten.
            $existingEntry = [ordered]@{}
            foreach ($ep in $m.entries[0].PSObject.Properties) { $existingEntry[$ep.Name] = $ep.Value }
            $existingEntry['id'] = $ConfigId
            if (-not ($existingEntry.Contains('name'))) { $existingEntry['name'] = $entryName }
            # Preserve any other top-level meta fields beyond appliedId/entries.
            $metaObj = [ordered]@{}
            foreach ($tp in $m.PSObject.Properties) { $metaObj[$tp.Name] = $tp.Value }
            $metaObj['appliedId'] = $ConfigId
            $metaObj['entries'] = @($existingEntry)
        }
        catch { }
    }
    $metaJson = $metaObj | ConvertTo-Json -Depth 50
    $oldMetaRaw = if (Test-Path $meta) { [System.IO.File]::ReadAllText($meta) } else { '' }
    if ($metaJson -cne $oldMetaRaw) {
        $bak = Backup-File $meta
        [System.IO.File]::WriteAllText($meta, $metaJson, (New-Object System.Text.UTF8Encoding($false)))
        $changed.Add("$d :: _meta.json")
        Write-Host "   _meta.json :: appliedId=$ConfigId  (backup: $bak)" -ForegroundColor Green
    }
    else { Write-Host "   _meta.json :: already current" -ForegroundColor DarkGray }
}
if ($SyncCli) {
    Write-Host ' CLI sync (settings.json):' -ForegroundColor Cyan
    $cliFields = @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY')
    $cliNeedsBackup = $false
    foreach ($f in $cliFields) { if ((Get-JsonStringField -Path $SettingsPath -Field $f) -ne $NewKey) { $cliNeedsBackup = $true } }
    if ((Get-JsonStringField -Path $SettingsPath -Field 'ANTHROPIC_BASE_URL') -ne $WriteBaseUrl) { $cliNeedsBackup = $true }
    # Seed CLI first-run onboarding state in ~/.claude.json. Runs whenever the CLI
    # is synced (not just on a pristine settings.json), so an existing install
    # where the app already launched (settings.json present) but the CLI onboarding
    # bools are missing still gets them filled. Check-and-fill only -- never
    # overwrites app-owned state. Suppresses the CLI first-run wizard, project trust
    # prompt, and auto-mode opt-in.
    $stateChanged = $false
    try {
        $stateChanged = Set-ClaudeStateOnboarding -Path $ClaudeStatePath
    }
    catch {
        # Parse error or non-object JSON -- distinguish from a clean no-op so the
        # user isn't told "already current" on a corrupt file.
        Write-Host "   .claude.json :: PARSE ERROR (skipped, not modified): $_" -ForegroundColor Red
        Write-Host "   Inspect or restore $ClaudeStatePath before continuing." -ForegroundColor Red
        exit 6
    }
    if ($stateChanged) {
        Write-Host "   .claude.json :: seeded onboarding flags (hasCompletedOnboarding/hasTrustDialogAccepted/hasResetAutoModeOptInForDefaultOffer)" -ForegroundColor Green
        $changed.Add(".claude.json :: onboarding flags")
    }
    elseif (Test-Path $ClaudeStatePath) {
        Write-Host "   .claude.json :: onboarding flags already current" -ForegroundColor DarkGray
    }
    else {
        Write-Host "   .claude.json :: absent (app has not launched yet; will seed on first sync)" -ForegroundColor DarkGray
    }
    # Validate ~/.claude.json still parses if it exists -- a silent JSON break
    # here would break the CLI at launch. On a pristine install where the app has
    # not launched yet, the file may not exist; skip the guard in that case.
    if (Test-Path $ClaudeStatePath) {
        try {
            $null = [System.IO.File]::ReadAllText($ClaudeStatePath) | ConvertFrom-Json
        }
        catch {
            Write-Host "   .claude.json re-parse: INVALID -> $_" -ForegroundColor Red
            Write-Host '   RESTORE FROM BACKUP BEFORE CONTINUING.' -ForegroundColor Red
            exit 6
        }
    }
    # Git prerequisite check: the pristine template hardcodes a Git Bash path and
    # ships Bash(git ...) allow entries. On a machine without Git for Windows,
    # those allow entries are non-functional. The PowerShell tool + git allowlist
    # mitigate this (PowerShell tool works without Git), but warn so the user
    # knows to install Git if they want Bash-based git operations to work.
    if (-not (Resolve-GitBashPath)) {
        Write-Host '   CLAUDE_CODE_GIT_BASH_PATH :: Git for Windows NOT found' -ForegroundColor Yellow
        Write-Host '     Bash(git ...) allow entries will be non-functional until Git is installed.' -ForegroundColor Yellow
        Write-Host '     PowerShell tool is enabled (CLAUDE_CODE_USE_POWERSHELL_TOOL=1) so CLI still works.' -ForegroundColor DarkGray
    }
    if (-not (Test-Path $SettingsPath)) {
        # Ensure the parent ~/.claude exists -- WriteAllText throws if it doesn't.
        # On a pristine machine with only Claude Desktop (winget) and no Claude
        # Code CLI run yet, ~/.claude does not exist (Desktop creates
        # %LOCALAPPDATA%\Claude, not ~/.claude). This mkdir lets the script run
        # correctly from any working directory, regardless of CWD.
        $parent = Split-Path $SettingsPath -Parent
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { try { New-Item -ItemType Directory -Path $parent -Force | Out-Null } catch { } }
        # Pristine template: universal 3P defaults + team SoP (Git installed first,
        # PowerShell tool, bypassPermissions with a git command allowlist). The
        # gateway key/URL are written just below via Set-JsonStringField from -NewKey.
        $pristine = '{' + "`n" +
            '  "$schema": "https://json.schemastore.org/claude-code-settings.json",' + "`n" +
            '  "env": {' + "`n" +
            '    "ANTHROPIC_AUTH_TOKEN": "",' + "`n" +
            '    "ANTHROPIC_API_KEY": "",' + "`n" +
            '    "ANTHROPIC_BASE_URL": "",' + "`n" +
            '    "API_TIMEOUT_MS": "3000000",' + "`n" +
            '    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80",' + "`n" +
            '    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",' + "`n" +
            '    "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe",' + "`n" +
            '    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1",' + "`n" +
            '    "ENABLE_TOOL_SEARCH": "true"' + "`n" +
            '  },' + "`n" +
            '  "permissions": {' + "`n" +
            '    "defaultMode": "bypassPermissions",' + "`n" +
            '    "allow": [' + "`n" +
            '      "PowerShell(git add *)", "PowerShell(git commit *)", "PowerShell(git status *)", "PowerShell(git log *)", "PowerShell(git diff *)", "PowerShell(git rm *)", "PowerShell(git mv *)", "PowerShell(git stash *)", "PowerShell(git branch *)", "PowerShell(git checkout *)", "PowerShell(git restore *)", "PowerShell(git fetch *)", "PowerShell(git pull *)", "PowerShell(git merge *)", "PowerShell(git ls-files *)", "PowerShell(git show *)",' + "`n" +
            '      "Bash(git add *)", "Bash(git commit *)", "Bash(git status *)", "Bash(git log *)", "Bash(git diff *)", "Bash(git rm *)", "Bash(git mv *)", "Bash(git stash *)", "Bash(git branch *)", "Bash(git checkout *)", "Bash(git restore *)", "Bash(git fetch *)", "Bash(git pull *)", "Bash(git merge *)", "Bash(git ls-files *)", "Bash(git show *)"' + "`n" +
            '    ]' + "`n" +
            '  },' + "`n" +
            '  "model": "auto",' + "`n" +
            '  "enableWorkflows": true,' + "`n" +
            '  "defaultShell": "powershell",' + "`n" +
            '  "outputStyle": "Concise"' + "`n" +
            '}'
        [System.IO.File]::WriteAllText($SettingsPath, $pristine, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "   settings.json :: created (pristine 3P defaults + SoP)" -ForegroundColor Green
        $cliNeedsBackup = $true
    }
    elseif (Ensure-SettingsEnvFields -Path $SettingsPath) {
        Write-Host "   settings.json :: injected missing env placeholders + universal defaults" -ForegroundColor Green
        $cliNeedsBackup = $true
    }
    # Pre-edit parse guard: if settings.json exists but is invalid JSON, bail BEFORE
    # Set-JsonStringField runs. Set-JsonStringField uses regex (not JSON parsing), so
    # it would silently substitute into corrupted content and worsen the damage before
    # the post-write re-parse guard catches it. Ensure-SettingsEnvFields returns $false
    # on a parse failure (no rewrite), so the file is still in its original corrupt
    # state here -- safe to abort without a backup-restore need.
    if ((Test-Path $SettingsPath) -and $cliNeedsBackup) {
        try { $null = [System.IO.File]::ReadAllText($SettingsPath) | ConvertFrom-Json }
        catch {
            Write-Host "   settings.json :: PARSE ERROR (pre-edit): $_" -ForegroundColor Red
            Write-Host "   File is corrupt; refusing to apply regex edits. Restore from backup or fix manually." -ForegroundColor Red
            exit 3
        }
    }
    if ($cliNeedsBackup -or -not (Test-Path $SettingsPath)) {
        $bak = Backup-File $SettingsPath
        foreach ($f in $cliFields) {
            if (Set-JsonStringField -Path $SettingsPath -Field $f -Value $NewKey) {
                $changed.Add("settings.json::$f")
                Write-Host "   settings.json :: $f -> $(Get-Fingerprint $NewKey)  (backup: $bak)" -ForegroundColor Green
            }
        }
        if (Set-JsonStringField -Path $SettingsPath -Field 'ANTHROPIC_BASE_URL' -Value $WriteBaseUrl) {
            $changed.Add('settings.json::ANTHROPIC_BASE_URL')
            Write-Host "   settings.json :: ANTHROPIC_BASE_URL -> $WriteBaseUrl" -ForegroundColor Green
        }
    }
    else { Write-Host '   settings.json env block already current' -ForegroundColor DarkGray }
    try {
        $null = [System.IO.File]::ReadAllText($SettingsPath) | ConvertFrom-Json
        Write-Host '   settings.json re-parse: VALID' -ForegroundColor Green
    }
    catch {
        Write-Host "   settings.json re-parse: INVALID -> $_" -ForegroundColor Red
        Write-Host '   RESTORE FROM BACKUP BEFORE CONTINUING.' -ForegroundColor Red
        exit 3
    }
}
else {
    Write-Host ' CLI settings.json: skipped (-NoSyncCli)' -ForegroundColor DarkGray
    Write-Host "   current ANTHROPIC_BASE_URL: $sUrl" -ForegroundColor DarkGray
}
$curEnv = [Environment]::GetEnvironmentVariable('LLM_KITA_API_KEY', 'User')
if ($curEnv -ne $NewKey) {
    [Environment]::SetEnvironmentVariable('LLM_KITA_API_KEY', $NewKey, 'User')
    $changed.Add('User env::LLM_KITA_API_KEY')
    Write-Host "   User env :: LLM_KITA_API_KEY -> $(Get-Fingerprint $NewKey)" -ForegroundColor Green
    Write-Host '   (does not affect already-running processes)' -ForegroundColor DarkGray
}
if ($MachineEnv) {
    $isAdmin = $false
    try {
        $princip = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        $isAdmin = $princip.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { }
    if (-not $isAdmin) { Write-Host '   Machine env: SKIPPED (-MachineEnv requires admin elevation)' -ForegroundColor Yellow }
    else {
        $curMachine = [Environment]::GetEnvironmentVariable('LLM_KITA_API_KEY', 'Machine')
        if ($curMachine -ne $NewKey) {
            [Environment]::SetEnvironmentVariable('LLM_KITA_API_KEY', $NewKey, 'Machine')
            $changed.Add('Machine env::LLM_KITA_API_KEY')
            Write-Host "   Machine env :: LLM_KITA_API_KEY -> $(Get-Fingerprint $NewKey)" -ForegroundColor Green
        }
    }
}
if ($ScrubStale -and $stale.Count -gt 0) {
    Write-Host ' Scrubbing stale keys:' -ForegroundColor Cyan
    $scrubTargets = New-Object System.Collections.Generic.List[string]
    Get-ChildItem $Claude3pDir, (Join-Path $env:USERPROFILE '.claude') -Filter '*.bak*' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $scrubTargets.Add($_.FullName) }
    if (Test-Path $TranscriptsDir) {
        Get-ChildItem $TranscriptsDir -Recurse -File -Filter '*.jsonl' -ErrorAction SilentlyContinue | ForEach-Object { $scrubTargets.Add($_.FullName) }
    }
    $scrubbedFiles = 0
    $scrubbedHits = 0
    foreach ($t in ($scrubTargets | Sort-Object -Unique)) {
        $raw = $null
        try { $raw = [System.IO.File]::ReadAllText($t) } catch { continue }
        $orig = $raw
        foreach ($sv in $stale.Keys) {
            $n = ([regex]::Matches($raw, [regex]::Escape($sv))).Count
            if ($n -gt 0) { $raw = $raw.Replace($sv, $NewKey); $scrubbedHits += $n }
        }
        if ($raw -cne $orig) {
            $null = Backup-File $t
            [System.IO.File]::WriteAllText($t, $raw, (New-Object System.Text.UTF8Encoding($false)))
            $scrubbedFiles++
        }
    }
    Write-Host "   scrubbed $scrubbedHits stale key occurrence(s) across $scrubbedFiles file(s)" -ForegroundColor Green
    Write-Host '   NOTE: old keys may still be valid at the gateway -- revoke them there.' -ForegroundColor Yellow
}
if ($ScrubEnv) {
    Write-Host ' Scrubbing stale env vars (multi-provider safe):' -ForegroundColor Cyan
    # Only these hosts count as LLM-Kita. Any other host = another provider's
    # subscription (OpenRouter / OpenCode / KiloCode / Chinese gateways) and is
    # NEVER touched, even if the var name collides with ANTHROPIC_*.
    $kitaHosts = @('chat-api.llm-kita.com', 'api.llm-kita.com')
    $envTargets = @('HKCU:\Environment')
    if ($MachineEnv) { $envTargets += 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment' }
    $scrubbedEnv = 0
    foreach ($hive in $envTargets) {
        $props = $null
        try { $props = Get-ItemProperty -Path $hive -ErrorAction SilentlyContinue } catch { continue }
        if (-not $props) { continue }
        foreach ($name in @('ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_API_KEY', 'ANTHROPIC_BASE_URL', 'LLM_KITA_API_KEY')) {
            # StrictMode-safe: dot-access on a missing PSCustomObject property throws.
            # The PSObject.Properties indexer is null-safe.
            $prop = $props.PSObject.Properties[$name]
            if (-not $prop) { continue }
            $val = $prop.Value
            if ($null -eq $val) { continue }
            # Keep the current LLM-Kita key/url we just wrote.
            if ($val -ceq $NewKey) { continue }
            if ($name -eq 'ANTHROPIC_BASE_URL') {
                # Remove only if it points at an LLM-Kita host. Other providers stay.
                $hostMatches = $false
                foreach ($h in $kitaHosts) { if ($val -like "*$h*") { $hostMatches = $true; break } }
                if (-not $hostMatches) {
                    Write-Host "   KEEP $hive :: $name = <non-LLM-Kita host> (untouched)" -ForegroundColor DarkGray
                    continue
                }
            }
            elseif ($name -ne 'LLM_KITA_API_KEY') {
                # ANTHROPIC_AUTH_TOKEN / ANTHROPIC_API_KEY: a bare key string carries
                # no host. Only remove if empty/blank -- a non-empty stale key here
                # is ambiguous (could be another provider's key). Report, don't delete.
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    Write-Host "   KEEP $hive :: $name = <non-empty, host unknown> (untouched -- could be another provider)" -ForegroundColor DarkGray
                    continue
                }
            }
            # LLM_KITA_API_KEY is always safe to rotate (name is provider-specific).
            try {
                Remove-ItemProperty -Path $hive -Name $name -ErrorAction Stop
                $scrubbedEnv++
                Write-Host "   removed $hive :: $name (was stale)" -ForegroundColor Green
            }
            catch { Write-Host "   could not remove $hive :: $name : $_" -ForegroundColor Yellow }
        }
    }
    Write-Host "   scrubbed $scrubbedEnv stale env value(s)" -ForegroundColor Green
    Write-Host '   NOTE: ANTHROPIC_* values pointing at other providers were preserved.' -ForegroundColor Yellow
}
if ($ResetCaches) {
    Write-Host ' Resetting caches:' -ForegroundColor Cyan
    $cacheDirs = @('Cache', 'Code Cache', 'GPUCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'Session Storage', 'blob_storage')
    $freed = 0
    foreach ($cd in $cacheDirs) {
        $p = Join-Path $Claude3pDir $cd
        if (-not (Test-Path $p)) { continue }
        $sz = 0
        $files = Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue
        if ($files) {
            $m = $files | Measure-Object -Property Length -Sum
            if ($null -ne $m -and $null -ne $m.Sum) { $sz = [int64]$m.Sum }
        }
        try {
            Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
            $freed += $sz
            Write-Host "   cleared cache: $cd" -ForegroundColor Green
        }
        catch { Write-Host "   could not clear ${cd}: app may be running" -ForegroundColor Yellow }
    }
    Write-Host ("   freed {0:N0} MB (caches regenerate on next launch)" -f ($freed / 1MB)) -ForegroundColor Green
}
Write-Head 'Result'
if ($changed.Count -eq 0) { Write-Host ' Nothing needed changing.' -ForegroundColor Green }
else {
    Write-Host ' Changed:' -ForegroundColor Green
    foreach ($cc in $changed) { Write-Host "   - $cc" -ForegroundColor Green }
}
$post = Test-GatewayKey -Key $NewKey -Base $ChosenBaseUrl
Write-Host ''
$colour = if ($post.Models -eq '200') { 'Green' } else { 'Yellow' }
Write-Host " Post-write probe  /v1/models: $($post.Models)   /v1/messages: $($post.Messages)" -ForegroundColor $colour
if ($changed.Count -gt 0) {
    Write-Host ''
    Write-Host ' Next: fully quit and restart Claude Desktop' -ForegroundColor Cyan
    if ($SyncCli) { Write-Host ' and the CLI.' -ForegroundColor Cyan }
    Write-Host ' Env vars and the credential file are read at launch, not on the fly.'
    Write-Host ' Then confirm the newest log shows no setup window:'
    Write-Host "   Get-Content '$LogPath' -Tail 200 | Select-String 'Opening 3P setup window|credential rejected'"
}