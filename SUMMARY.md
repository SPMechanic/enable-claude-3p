# Enable-Claude3P.ps1  -  Maintainer & Audit Summary

**Last updated:** 2026-10-12
**Status:** Audit complete. All 14 findings + all 7 open questions are CLOSED.

This is the maintainer/audit record for `Enable-Claude3P.ps1`. It replaced
`HANDOFF.md` (retired). For **user-facing usage**  -  LLM-Kita intro, quick start,
parameter reference, recipes, what-to-avoid, troubleshooting, the pristine
`settings.json` template  -  read **`README.md`** in the same folder. This
document covers architecture, helper internals, audit findings, test coverage,
and known gotchas that a maintainer needs but an end user does not.

---

## 1. What the script does

`Enable-Claude3P.ps1` (1329 lines) configures a Windows machine to run Claude
Desktop + Claude Code CLI in "3P" (third-party gateway) mode against an LLM-Kita
gateway instead of the default Anthropic endpoint. It is idempotent,
check-and-fill (non-destructive), and supports `-Apply` / `-Interactive` /
`-Restore` / dry-run modes (dry-run is the default when none of those is
passed).

### File inventory  -  `C:\CLAUDE\plugins\enable-claude-3p\`

| Path | Role |
|---|---|
| `README.md` | **User guide.** Read first for usage. |
| `Enable-Claude3P.ps1` | The main script. Self-executes on dot-source (has a `param()` block + top-level logic, not a pure library). |
| `SUMMARY.md` | This file. Maintainer/audit record. |
| `CHANGELOG.md` | Dated, grouped change log for the script + test harness (no semver). Records the `-Models` parameter, `Remove-JsonField` trailing-comma fix, and audit-driven hardening releases. |
| `validate-template.ps1` | AST-extracts the `$pristine` template string from the main script and validates it parses as JSON. |
| `test-helpers.ps1` | Behavioral test harness  -  156 assertions covering all helper functions + Restore logic. Inlines copies of the helpers (see §6 gotcha #1 for why). |
| `docs/` | The LLM-Kita Hands-On Guide (`.md` + `.pdf`) and `docs/images/` (19 screenshots). A 20-step MOC-style walkthrough. |
| `_archive/` | **SUPERSEDED / DEAD  -  do NOT run.** See below. |

### `_archive/` contents

| File | Why it's here |
|---|---|
| `Initialize-ClaudeConfig.ps1` | Destructive v1 (wholesale overwrite, BOM, placeholder URL). Superseded by `Enable-Claude3P.ps1`. |
| `gateway.py` + `sync-gateway-key.ps1` | The two scripts `Enable-Claude3P.ps1` replaced (its `.SYNOPSIS` says "Unified replacement for gateway.py + sync-gateway-key.ps1"). |
| `gateway-auth-bearer_test.ps1` | One-off probe with a hardcoded key. |
| `claude_3p_inference_config_connection_with_llm-kita.json` | Old credential-bearing copy the script never reads. |
| `settings.json` + `.claude.json` | Old credential-bearing copies. **SECURITY:** these contain LIVE API keys + a real machineID in plaintext. The live ones are at `~/.claude/`. |
| `Marketplaces_Plugins_Skills_Connectors.txt` | Stale reference list. |

---

## 2. Architecture  -  the three write targets

The script writes to up to three locations, discovered by `Resolve-Claude3pDirs`
(line 360):

1. **`claude_desktop_config.json`** (per Claude-3p dir)  -  sets
   `deploymentMode: "3p"` so the Desktop app uses the gateway. May already exist
   if the stock app created it for MCP-server config.
2. **`configLibrary/<id>.json` + `_meta.json`** (per Claude-3p lib dir)  -  the
   gateway config entry (baseUrl, apiKey, authScheme). Written by
   `Write-GatewayConfigEntry` (parse/merge/serialize).
3. **`~/.claude/settings.json`** + **`~/.claude.json`** (CLI sync)  -  only when
   `-NoSyncCli` is NOT passed. `settings.json` gets `env.ANTHROPIC_*` (key/URL)
   + universal defaults; `.claude.json` gets CLI onboarding bools.

`Resolve-Claude3pDirs` always includes the legacy `%LOCALAPPDATA%\Claude-3p` dir
and scans `Packages\Claude_*\LocalCache\Roaming\Claude-3p` for MSIX/Store
installs. Returns `,$dirs.ToArray()` (comma-wrapper) so a 1-element array
doesn't unwrap to a scalar under `Set-StrictMode -Version Latest`.

Every write is backed up first (a `.bak` copy sits next to the original), and the
script only writes what's missing or wrong  -  it never overwrites a value you
already set. All JSON writes are no-BOM UTF-8 via
`[System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))`.

---

## 3. Helper functions

The parse/merge/serialize layer exists because `Set-JsonStringField` (regex
replacement) can only **update** an existing field, never **insert** one.
Anywhere a field might be absent, the ensure-helpers handle it instead.

| Function | Line | Purpose | Backup? | Depth |
|---|---|---|---|---|
| `Backup-File` | 221 | Copy to `.bak` next to original. |  -  |  -  |
| `Set-JsonStringField` | 234 | Regex-only UPDATE of an existing string field. Used after ensure-helpers guarantee the field exists. **No JSON-encode/decode** (raw value in, raw value out)  -  see §6 gotcha #2. | caller |  -  |
| `Get-JsonStringField` | 245 | Regex read of a string field. **No unescape**  -  preserves `\"` as-is. |  -  |  -  |
| `Remove-JsonField` | 253 | Regex removal of a field (used in Restore). | caller |  -  |
| `Set-ClaudeStateOnboarding` | 269 | Check-and-fill 3 onboarding bools in `~/.claude.json` (`hasCompletedOnboarding`, `hasTrustDialogAccepted`, `hasResetAutoModeOptInForDefaultOffer`). Writes a sentinel `_enableClaude3pSeededOnboarding` only when it seeds bools (consumed by Restore for safe removal). Type-guards against non-object JSON; throws on parse error. | yes (internal) | 50 |
| `Ensure-DesktopDeploymentMode` | 319 | Ensure `claude_desktop_config.json` has `deploymentMode="3p"`  -  inserts if absent, updates if different, no-op if already 3p. Preserves MCP config. | yes (internal) | 50 |
| `Resolve-Claude3pDirs` | 386 | Discover all Claude-3p install dirs (legacy + MSIX enumeration). Comma-wrapped array return for StrictMode safety. |  -  |  -  |
| `Write-GatewayConfigEntry` | 431 | Merge gateway fields into configLibrary entry. Now takes optional `-ResolvedModels`: when passed, full-rebuilds `inferenceModels` (replaces existing); otherwise pristine-seeds the default 3-model catalog and leaves an existing catalog untouched. | yes (internal) | 50 |
| `Resolve-InferenceModels` | 478 | **Pure** (no file I/O). Parse the `-Models` JSON string into a catalog array. Each entry must have non-empty `name` + `labelOverride`; the 4 other known fields fill with defaults if absent. `anthropicFamilyTier` defaults by position (0=sonnet, 1=opus, 2=haiku, 3=fable, 4=mythos, else sonnet). Throws on validation failure; caller exits 7. |  -  |  -  |
| `Get-AppliedConfigPath` | 532 | Small helper: resolve the applied-config path. |  -  |  -  |
| `Resolve-GitBashPath` | 548 | Validate Git for Windows is present (hardcoded path or PATH `git`). Returns `$true`/`$false`. Used for the apply-time Git warning. |  -  |  -  |
| `Ensure-SettingsEnvFields` | 578 | Ensure `settings.json` has `env.ANTHROPIC_*` placeholders + 5 universal env vars. Only adds absent keys. Short-circuits (no rewrite) when nothing's missing. | yes (internal) | 50 |

### Restore  -  inline (NOT a function)

The Restore orchestration is **inline top-level code at lines 657-756**, not a
function. It strips `deploymentMode` + the configLibrary entry + zeroes
`_meta.json`, removes sentinel-gated onboarding bools, and strips
`ANTHROPIC_*` from `settings.json`. Sets `$any` so a settings-only restore
reports completion.

> `Invoke-RestoreCore` appears only in `test-helpers.ps1` as a testable mirror
> of this inline block. It is **not** a function in the main script. If the main
> script is ever refactored into a pure library (gated top-level execution),
> `test-helpers.ps1` should switch to dot-sourcing the real helpers instead of
> inlining copies.

### Apply block

The Apply orchestration runs **lines ~759-1329** (script end), calling all the
helpers above: key sourcing → `-Models` validation (via `Resolve-InferenceModels`,
exit 7 on failure) → probe → summary/confirm → write
`deploymentMode` (via `Ensure-DesktopDeploymentMode`) → write gateway entry
(via `Write-GatewayConfigEntry`, passing `-ResolvedModels` if `-Models` was set)
→ sync CLI `settings.json` (via
`Ensure-SettingsEnvFields` + `Set-JsonStringField`) → seed onboarding bools
(via `Set-ClaudeStateOnboarding`) → set `LLM_KITA_API_KEY` env var →
optional `-MachineEnv` / `-ScrubStale` / `-ScrubEnv` / `-ResetCaches`.

---

## 4. Audit results

Three parallel audit agents ran: (A) pristine scenarios, (B) dirty/existing
scenarios, (C) new-code-path sequencing. All findings are resolved.

### 4.1 Findings (all FIXED)

| # | Sev | Finding | Fix |
|---|---|---|---|
| 1 | CRITICAL | `deploymentMode` never INSERTED if `claude_desktop_config.json` exists (e.g. MCP config) but lacks the field  -  regex-only `Set-JsonStringField` can't insert; Desktop silently never enters 3P mode. | New `Ensure-DesktopDeploymentMode` helper (parse/merge/serialize); wired into Apply path replacing the regex-only call. |
| 2 | MAJOR | Restore stripped `ANTHROPIC_AUTH_TOKEN` + `ANTHROPIC_BASE_URL` but NOT `ANTHROPIC_API_KEY`  -  gateway key persisted after "restore to stock". | Added `ANTHROPIC_API_KEY` to the Restore strip list. |
| 3 | MAJOR | Universal env vars (`CLAUDE_CODE_USE_POWERSHELL_TOOL`, `ENABLE_TOOL_SEARCH`, `API_TIMEOUT_MS`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`) only in the pristine template  -  existing installs upgrading never got them. | `Ensure-SettingsEnvFields` now seeds all 5 universal vars (only if absent). |
| 4 | MAJOR | Corrupted `settings.json`: `Set-JsonStringField` regex edits ran before the post-write re-parse guard, worsening corruption. | Pre-edit parse guard: validates JSON before any `Set-JsonStringField` call; exits 3 on failure. |
| 5 | MAJOR | `Ensure-SettingsEnvFields` wrote without a backup; caller's backup captured the already-modified file  -  original lost. | Helper calls `Backup-File` internally before `WriteAllText`. |
| 6 | MAJOR | `ConvertTo-Json -Depth 10` risked truncating deeply-nested app-owned data (`projects`, `pluginUsage`, `skillUsage`)  -  truncation produces valid JSON so the re-parse guard can't catch it. | Bumped to `-Depth 50` in `Set-ClaudeStateOnboarding` and `Ensure-SettingsEnvFields`. |
| 7 | MAJOR | `Set-ClaudeStateOnboarding` pristine path used `[ordered]@{}` → `OrderedDictionary`, which failed the `PSCustomObject` type guard → onboarding bools never seeded on a pristine install. | Changed to `[PSCustomObject]@{}` (matches `ConvertFrom-Json` on `{}`). Caught by the test harness. |
| 8 | MINOR | `GATEGUARD_BASH_ROUTINE_DISABLED` in the universal pristine template  -  plugin-specific (GateGuard hook), not universal. | Removed from template. Template now has 9 env keys (was 10). |
| 9 | MINOR | `mkdir` guards used `Test-Path` without `-PathType Container`  -  a file at a directory path would skip mkdir and crash `WriteAllText`. | Added `-PathType Container` to all 3 mkdir guards. |
| 10 | MINOR | No type guard in `Set-ClaudeStateOnboarding` for non-object JSON (array/scalar)  -  `Add-Member` silently corrupts. Also: misleading "already current" message on a corrupt `.claude.json`. | Type guard throws on non-`PSCustomObject`; caller wraps in try/catch, reports "PARSE ERROR" distinctly from the no-op. Re-parse guard skipped when file doesn't exist (pristine). |
| 11 | MINOR | Restore didn't remove `.claude.json` onboarding bools  -  wizard stayed suppressed in stock mode. | Sentinel-gated removal: `_enableClaude3pSeededOnboarding` written only when bools are seeded; Restore removes bools + sentinel only when the sentinel proves the script added them. A user who completed stock onboarding before 3P (no sentinel) is left intact. |
| 12 | MINOR | Restore unconditionally wrote `_meta.json` (no content comparison)  -  stacked a `.bak` on re-runs. | Content-compare (`-cne`) against `{"appliedId":"","entries":[]}` before rewriting; backup + write only when content differs. |
| 13 | MINOR | Restore printed "Already stock. Nothing to restore." when only `settings.json` was modified  -  `$any` not set by the settings strip path. | `$any = $true` added to the settings strip branch. A settings-only restore now correctly reports "RESTORE COMPLETE." |
| 14 | INFO | Exit code 3 reused for both `.claude.json` and `settings.json` re-parse failures  -  automation can't distinguish which file failed. | Split: exit 3 = `settings.json` (unchanged), exit 6 = `.claude.json` (both pre-write PARSE ERROR and post-write re-parse). |

### 4.2 Closed by design

| # | Finding | Why closed |
|---|---|---|
| D4 | `Backup-File` called before `Set-JsonStringField` in the deploymentMode Apply path  -  orphaned `.bak` if the field is missing. | Apply path rewritten to use `Ensure-DesktopDeploymentMode`, which takes its backup *inside* the helper only when a write actually happens. The `if ($mode -ne '3p')` gate means the helper is only called when the value isn't exactly `'3p'`. |
| D6 | Indentation: the onboarding-seed block was moved out of the `if (-not (Test-Path $SettingsPath))` nest but kept 8-space indent. | Fixed in the original audit session (caller rewrite normalized the indent). Listed so it's not mistaken for open. |
| D7 | `Initialize-ClaudeConfig.ps1` header says "absorbed into `-Interactive`" but the onboarding seed runs on any Apply/SyncCli. Also omits the third bool. | The superseded file was moved to `_archive/` so it can't be mistaken for active code. Its header inaccuracy is now irrelevant. |

### 4.3 Open items

**None.** The deferred table and the open-questions list are both empty. No
open work remains.

### 4.4 Scenarios verified PASS (no bugs)

- Truly pristine winget install (no dirs, no files) with `-Interactive -Force -NewKey`.
- Pristine MSIX/Store install (`Packages\Claude_*` enumeration).
- Pristine "app launched once then quit" (`.claude.json` has machineID/userID, no settings.json).
- Pristine `-NoSyncCli` (skips settings.json + .claude.json entirely).
- Pristine `-SkipProbe` (writes without probing).
- Pristine `-Restore` (exits clean with "Already stock").
- Idempotent re-run (same key)  -  no `.bak` stacking in the ideal case.
- Key rotation  -  every location updated; `.claude.json` not touched unnecessarily.
- Existing stock Claude applying 3P  -  `.claude.json` state preserved.
- App already running  -  process check runs before any writes.
- `-NoSyncCli` with existing 3P  -  `.claude.json` and settings.json untouched.
- `-ScrubEnv` with non-LLM-Kita values  -  host-matching preserves them.
- Empty `.claude.json` `{}`  -  bools added correctly.
- The `,$dirs.ToArray()` wrapper under StrictMode (0/1/2+ elements).
- `permissions.allow` array survives ConvertTo-Json round-trip.

---

## 5. Test coverage

### `test-helpers.ps1`  -  156 assertions, all PASS (2026-10-12)

Inlines copies of the helpers (because the main script self-executes on
dot-source  -  see §6 gotcha #1) and tests:

- **`Set-ClaudeStateOnboarding`:** array throws, scalar throws, corrupt throws,
  pristine creates 3 bools, idempotent no-op, preserve-existing
  (machineID/userID/pluginUsage/projects trust all kept). **+ sentinel**
  `_enableClaude3pSeededOnboarding`: set on seed, absent on no-op, not added
  when bools pre-exist.
- **`Ensure-DesktopDeploymentMode`:** insert when absent (MCP config preserved),
  no-op when already 3p, update from other value.
- **`Ensure-SettingsEnvFields`:** injects placeholders + universal vars,
  preserves existing `ANTHROPIC_API_KEY` + custom keys, idempotent.
- **`Set-JsonStringField`:** missing field no-op, missing file no-op, update
  existing, idempotent, **raw (no-escape) contract** for backslash values,
  whitespace-tolerant, first-occurrence only, operates on invalid JSON
  (regex-based, not parse-based).
- **`Get-JsonStringField`:** missing field/file → null, non-string field →
  null, **no-unescape contract** (`\"` preserved in capture),
  whitespace-tolerant.
- **`Remove-JsonField`:** string field removal + sibling preservation,
  last-field → empty `{}`, missing field no-op, number/bool removal, missing
  file no-op.
- **`Write-GatewayConfigEntry`:** pristine seed (all gateway fields + 3-model
  catalog), trailing-slash normalization (no doubling), merge preserves custom
  fields + existing non-empty `inferenceModels` (user's UI config not
  overwritten), idempotent, corrupt-existing treated as pristine. **+ `-Models`
  full-rebuild:** passing `-ResolvedModels` replaces an existing catalog with
  exactly the resolved entries (old catalog gone, tier filled); no-`-Models`
  pristine still seeds the default 3; no-`-Models` existing left untouched.
- **`Resolve-InferenceModels`** (pure): 2-entry array (user fields verbatim +
  by-position tier fill at idx 0=sonnet, 1=opus, 2=haiku, 3=fable, 4=mythos),
  idx ≥ 5 falls back to sonnet, single-entry defaults all 4 optional fields,
  explicit `anthropicFamilyTier` respected (not overwritten), extra unknown
  field preserved, object-not-array throws, missing `name` throws, missing
  `labelOverride` throws, bare-string element throws, invalid JSON throws.
- **`Write-GatewayConfigEntry` `-Models` edge cases:** empty-array `-Models '[]'`
  clears the catalog (count 0, array type preserved  -  verifies the
  `$ModelsSupplied` boolean fix, not `$ResolvedModels` truthiness); existing
  empty `[]` preserved when `-Models` omitted (existence-only check, not
  falsy-empty suppression); merge isolation WITH rebuild (custom field
  survives, old models gone); single-object (non-array) existing untouched
  without crash.
- **`Resolve-Claude3pDirs`:** legacy-only (no Packages dir), empty Packages,
  single MSIX `Claude_*` enumeration (both `Claude-3p` + `Claude` leaves), two
  MSIX packages, non-`Claude_*` package ignored, comma-wrapper survives
  StrictMode `.Count` access. Uses a synthetic `%LOCALAPPDATA%` tree under temp
  so the real Packages dir is untouched.
- **`Invoke-RestoreCore` (test-harness mirror of the inline Restore block):**
  D2 `_meta.json` content-compare (rewrite + idempotent no-op), D3
  settings-only-restore sets `$any` + strips `ANTHROPIC_*` + preserves siblings
  + second-run no-op, D1 sentinel-present removes bools+sentinel (preserves
  machineID), D1 no-sentinel leaves user bools intact, D1 corrupt `.claude.json`
  skipped without throw.
- **`Resolve-GitBashPath`:** detects Git for Windows at the hardcoded path or
  via PATH `git`. Positive case asserted on this machine (Git at standard
  location).

### `validate-template.ps1`  -  AST-based, PASS (2026-10-12)

Extracts the `$pristine` template string from the actual script via the
PowerShell AST (`Parser::ParseFile` + `FindAll` for the `$pristine` assignment,
then `scriptblock::Create` + invoke), and validates it parses as JSON with the
expected fields. More robust than reconstructing the template by hand (an
earlier attempt failed due to bash→powershell backtick escaping).

Verified output: JSON VALID; 9 env keys; 32 allow entries;
`defaultMode: bypassPermissions`; `defaultShell: powershell`;
`outputStyle: Concise`.

### Run both

```bash
powershell -ExecutionPolicy Bypass -File .\validate-template.ps1
powershell -ExecutionPolicy Bypass -File .\test-helpers.ps1
```

### Coverage gap (the only untested layer)

The full Apply/Restore end-to-end flow on a synthetic dir tree. The harness
tests the functions in isolation, not the top-level orchestration. If that
becomes a risk, refactor the main script into a pure library (gated top-level
execution) and switch the harness to dot-sourcing.

---

## 6. Known limitations / gotchas

1. **Main script self-executes on dot-source.** It has a `param()` block and
   top-level logic, so `. 'Enable-Claude3P.ps1'` runs it (there is no `-DryRun`
   parameter  -  dry-run is the default when no `-Apply`/`-Interactive`/`-Restore`
   is passed). The test harness inlines copies of the helpers rather than
   dot-sourcing. **If the script is ever refactored into a pure library
   (functions only, gated top-level execution), `test-helpers.ps1` should switch
   to dot-sourcing instead.**

2. **`Set-JsonStringField` / `Remove-JsonField` / `Get-JsonStringField` are
   regex-based.** They work on the raw text, not parsed JSON. They can only
   UPDATE/REMOVE/READ a field that exists with a string value. Anywhere a field
   might be absent, the parse/merge/serialize ensure-helpers must run first.
   This was the root cause of finding #1 (the CRITICAL one). **Additionally
   (pinned by tests 2026-10-12):** these functions do NOT JSON-encode
   (`Set-JsonStringField` writes the raw value verbatim into the capture) or
   decode (`Get-JsonStringField` preserves `\"` sequences as-is in its return).
   The callers in the main script pass already-safe values (`'3p'`, API keys,
   URLs  -  no raw quotes/control chars), so this is safe in practice, but a
   future caller passing a value containing a literal `"` would produce invalid
   JSON. If that ever becomes a risk, switch these to parse-based or add an
   escape/unescape layer  -  the tests will flag the contract change.

3. **`Out-File -Encoding utf8` emits a BOM in PS 5.1.** All writes in the main
   script use `[System.IO.File]::WriteAllText($path, $content, (New-Object
   System.Text.UTF8Encoding($false)))` (no BOM). The test harness uses `Out-File`
   for synthetic temp files only  -  not production paths.

4. **bash→powershell backtick escaping is unworkable for inline PS.**
   `powershell -Command "..."` from bash collides on backticks (`` `n `` etc.).
   For anything non-trivial, write a `.ps1` file and run it with `-File`.

5. **Exit code 5 covers two cases.** It fires both when a user answers `N` at a
   confirm prompt AND when a non-interactive session refuses without `-Force`.
   Automation that needs to distinguish "user aborted" from "non-interactive
   refusal" should check stdout, not just the exit code.

6. **`-Models`: `name` is load-bearing, `labelOverride` is cosmetic.** In each
   model entry, `name` is the wire model id sent in every API request  -  a value
   the gateway doesn't route silently breaks inference at launch. `labelOverride`
   is UI-only and safe to set to anything (that's the whole point: present a
   gateway model under a custom label). The `-Interactive` summary warns
   non-blocking if a `name` doesn't match a recognized Claude id regex, but
   **does not block**  -  the user may legitimately be pointing `name` at a
   non-Claude gateway-served id. `Resolve-InferenceModels` is pure (no file I/O)
   and validated early (exit 7 on bad input), distinct from on-disk parse
   failures (exit 3/6).
