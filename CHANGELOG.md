# Changelog

Notable changes to `Enable-Claude3P.ps1` and its test harness. This project
does not use semantic versioning; entries are dated and grouped by feature.

## 2026-10-15  -  single-element `-Models` fix, validator repair, scaled harness, README tutorial

A focused session on the `Resolve-InferenceModels` crash and the no-`settings.json`
test surface, ending with a README redesign. 6 commits (`9bce883`..`fbba099`).

### Fixed
- **`Resolve-InferenceModels` falsely rejected a 1-element `-Models` array
  (HIGH).** `ConvertFrom-Json` unwraps a 1-element JSON array to a bare
  `PSCustomObject`, so the post-parse `-is [System.Array]` guard threw
  "-Models must be a JSON array" for a valid single-model catalog. The 2+
  element cases passed by luck (arrays of >=2 stay arrays). **This was a
  production bug**, not just a test artifact: a user passing
  `-Models '[{...one model...}]'` on the real CLI would exit 7 for a valid
  catalog. Fix: detect array-wrapping at the JSON-text level (first
  non-whitespace char must be `[`), then normalize with `@($parsed)` to
  re-wrap the unwrapped single element. Bare objects (`{"name":...}`, not
  array-wrapped) still throw. Empty `[]` and multi-element arrays unchanged.
  Same fix applied to the `test-helpers.ps1` mirror.
- **`validate-template.ps1` had a dead hardcoded path (MEDIUM).** It pointed
  at `C:\CLAUDE\plugins\enable-claude-3p\Enable-Claude3P.ps1` — a path that
  no longer exists — so it failed at parse time and silently never ran. Fixed
  to resolve via `$PSScriptRoot` so it works from any CWD.
- **`validate-template.ps1` under-asserted the pristine template (MEDIUM).**
  Even with the path fixed, it only checked 5 fields (GIT_BASH_PATH, env key
  count, allow count, defaultMode, defaultShell, outputStyle) — NOT the three
  `ANTHROPIC_DEFAULT_*_MODEL` tier vars, NOT the top-level `model` field, NOT
  `model != "auto"`. Since `Ensure-SettingsEnvFields` only runs on EXISTING
  files, a tier var dropped from the pristine template would ship uncaught.
  Added 6 assertions: SONNET/HAIKU/OPUS tier vars present, `model` field
  present, `model == claude-sonnet-5-5` (not the legacy `auto` alias),
  `enableWorkflows`. Validator now 12/12.

### Added
- **`test-settings-env.ps1` Case 12 — scaled nesting fixture.** The harness
  only exercised a 4-plugin / 2-marketplace file. Case 12 adds a 12-plugin
  (mixed booleans) + 8-marketplace fixture spanning every schema-permitted
  `source` variant (`git`/`github`/`url`/`hostPattern`/`npm`/`file`/
  `directory`/`settings`) with their type-specific leaf fields, plus a
  sibling nested `stats` object. Asserts tier-var + model injection still
  fires, every plugin/marketplace leaf survives, sibling state untouched, and
  a second run is byte-identical to the first. Converts the "same code path,
  so scale doesn't matter" inference into a proof. (Also caught and fixed a
  self-comparison typo in the byte-identical assertion that would have
  claimed coverage it didn't provide.)
- **README: "Resulting files: both scenarios" section.** Exact `settings.json`
  + `.claude.json` for (A) pristine-no-files and (B) both-exist, with a
  field-by-field injection table and cross-file guarantees.
- **README: "Recommended: full hygiene key rotation" quickstart.** Step-by-step
  (quit → manual backup → conservative or clean-baseline path with full scrub
  flags → restart + log check).
- **README: tutorial redesign.** Restructured the reference-first doc into a
  tutorial-first journey with badges, emoji, callouts, and collapsible
  `<details>` sections for reference content.

### Changed
- `test-settings-env.ps1`: 46 -> 70 assertions (12 cases). All PASS.
- `README.md` §11 (test inventory) and §12 (tested scenarios) aligned with
  the current harness surface.
- `SUMMARY.md`: fixed stale file-inventory path (`C:\CLAUDE\plugins\...` ->
  `C:\CLAUDE\Enable-Claude3P-v1.1\`).

### Corrected (stale claim in a prior entry)
- The `2026-10-12 audit-driven hardening` entry's "Non-issues" section
  asserted that single-element `-Models '[{...}]'` was safe in PS 5.1 —
  claiming `ConvertFrom-Json` returns an `Object[]` of count 1 with no unwrap.
  **That claim was wrong.** This session reproduced the unwrap: a 1-element
  array comes back as a bare `PSCustomObject`, the `-is [System.Array]` check
  fails, and `Resolve-InferenceModels` exits 7. The fix above (JSON-text-level
  array detection + `@()` normalization) resolves it. The prior "non-issue"
  note is retained for history but should be read as superseded by this fix.

## 2026-10-12  -  `-Models` parameter (model catalog override)

Added an optional `-Models '<JSON array>'` parameter that lets the user
present a gateway-served model under a custom UI label (e.g. `name="claude-sonnet-5-5"`,
`labelOverride="Sonnet 5.5"`).

### Added
- `[string]$Models` parameter with full `.PARAMETER Models` help docs.
- `Resolve-InferenceModels` pure helper (no file I/O): parses/validates the
  `-Models` JSON into a catalog array. Each entry needs non-empty `name` +
  `labelOverride`; the 4 optional fields (`supports1m`, `isFamilyDefault`,
  `maxEffort`, `anthropicFamilyTier`) fill with defaults if absent.
  `anthropicFamilyTier` defaults by position (0=sonnet, 1=opus, 2=haiku,
  else sonnet). Throws on bad JSON / non-array / missing mandatory fields /
  non-object element.
- `Write-GatewayConfigEntry -ResolvedModels` param with 3-branch model logic:
  full rebuild (replace) when `-Models` passed; default 3-model seed on
  pristine; existing catalog left untouched when `-Models` omitted.
- Validation gate (after all function defs, before the mode branch): exits 7
  on bad `-Models` input (distinct from on-disk parse failures 3/6).
- Dry-run/interactive catalog report block: prints current `inferenceModels`
  then would-write entries before any change.
- Interactive summary: non-blocking warning if a `name` isn't a recognized
  Claude id regex.
- README §5 param table, §6 recipe, §8 gotcha row, §9 exit code 7, §11 test
  count update.
- SUMMARY helper table row, Apply-block note, test-coverage section, new
  gotcha #6 (load-bearing `name` vs cosmetic `labelOverride`).
- `test-helpers.ps1`: 32 new assertions (142 total) covering
  `Resolve-InferenceModels` pure cases + `Write-GatewayConfigEntry`
  `-ResolvedModels` full-rebuild / pristine-default / existing-untouched.

### Changed
- `Write-GatewayConfigEntry` model-injection logic split from 1 branch
  (pristine-seed only) into 3 branches. `ConvertTo-Json -Depth` raised from
  10 to 50 to match the other writers.
- The default 3-model hardcoded catalog (sonnet/opus/haiku) is unchanged  - 
  fable/mythos tiers are not seeded by default. Pass them explicitly via
  `-Models` if the gateway serves them.

### Fixed (in-progress, this release)
- Validation gate originally placed at line ~214, before `Resolve-InferenceModels`
  was defined (~line 480). PowerShell executes top-level code top-to-bottom, so
  the function was not yet defined when the gate ran  -  `Resolve-InferenceModels`
  was unrecognized at runtime. Gate relocated to after all function definitions
  (just before the `$Mode = ...` line). Caught by a smoke test before release.

### Known limitations
- Position-based `anthropicFamilyTier` default fills sonnet/opus/haiku/fable/
  mythos for indices 0-4; index >= 5 always gets `sonnet` regardless of array
  length. Documented in `.PARAMETER Models`. If passing >5 entries without
  explicit `anthropicFamilyTier`, set it explicitly per entry.

## 2026-10-12  -  `Remove-JsonField` trailing-comma fix (Restore path)

### Fixed
- **`Remove-JsonField` left a dangling trailing comma when the removed field was
  the LAST entry in a nested object (HIGH).** The trailing-comma cleanup regex
  was `,(\s*\}\s*$)` -- it only matched a comma immediately followed by the
  object's closing `}` at **end-of-string**. When the closing `}` was mid-file
  (e.g. the `env` object followed by `"permissions":`), the comma before the
  now-last field was left intact, producing `},}` -> invalid JSON. This made
  `-Restore` silently corrupt `settings.json` whenever it stripped the last env
  field. Changed to `,(\s*\})` (matches anywhere, first occurrence). The Apply
  path was unaffected (it uses `Set-JsonStringField`, not `Remove-JsonField`,
  and its pre-edit parse guard correctly refuses corrupt files).
- Discovered when a user's enable run hit `PARSE ERROR (pre-edit): Invalid JSON
  primitive: .` -- the guard worked as designed (refused to edit a corrupt
  file), but the corruption came from a prior Restore on the same machine.

### Tests
- `test-helpers.ps1`: 152 -> 156 assertions. Added a nested-last-field
  regression (closing brace mid-file) and a real-shape 3-field strip
  (ANTHROPIC_AUTH_TOKEN/BASE_URL/API_KEY removed from the settings.json env
  block; verifies remaining keys and JSON validity).

## 2026-10-12  -  audit-driven hardening (post-review fixes)

Applied after a two-pass code review (dirty/existing-state audit + pristine-state
audit). 152 assertions (was 142); all PASS.

### Fixed
- **Empty-array `-Models '[]'` silently bypassed rebuild (MEDIUM→HIGH).**
  PowerShell treats an empty array as falsy, so the old `if ($ResolvedModels)`
  branch fell through to seed/preserve instead of clearing the catalog. Added a
  `$ModelsSupplied` boolean tracked at the validation gate and threaded through
  `Write-GatewayConfigEntry`, the interactive summary, and the report block.
  `-Models '[]'` now correctly clears `inferenceModels` (count 0).
- **`Write-GatewayConfigEntry` existing-empty suppression (LOW).** The elseif
  was `(-not ($existing.Contains('inferenceModels') -and $existing['inferenceModels']))`,
  which re-seeded the default catalog if an existing `inferenceModels` was `[]`.
  Changed to existence-only (`-not $existing.Contains('inferenceModels')`) so an
  existing empty array is preserved when `-Models` is omitted.
- **Warning regex false-negative for Claude 3.0 ids (LOW).** Added bare `3` (and
  the new `fable`/`mythos` tiers) to the `^claude-(...)` alternation so ids like
  `claude-3-opus` aren't false-warned as unrecognized.
- **Report block null-safety (LOW).** Split `$cfgObj.PSObject.Properties['inferenceModels'].Value`
  into a two-step access (get property, then value) so the normal missing-key
  case doesn't depend on a caught exception.

### Changed
- **Extended the position-based `anthropicFamilyTier` default from 3 to 5
  tiers** (sonnet/opus/haiku/fable/mythos, indices 0-4), matching the inference
  config dropdown order. Index >= 5 falls back to `sonnet`. `test-helpers.ps1`
  updated: the old "idx 3 → sonnet" assertion now expects `fable`; added an
  idx-5 fallback assertion.

### Non-issues (verified, no change needed)
- The pristine-state audit flagged single-element `-Models '[{...}]'` as a
  crash. Empirically verified in PS 5.1: `ConvertFrom-Json` returns an
  `Object[]` of count 1 (no unwrap, no throw). The `Resolve-InferenceModels`
  array check (`$parsed -is [System.Array]`) passes. The "test crashes at
  test-helpers:677" claim was a hypothetical trace, not a real failure  -  the
  `rim 1-entry` tests pass cleanly.
- Single-object existing `inferenceModels` (non-array) + no `-Models`: tested
  explicitly and confirmed untouched without crash.

## Earlier  -  v2 rewrite

The script was rewritten from `Initialize-ClaudeConfig.ps1` (the destructive
v1: wholesale overwrite, BOM, placeholder URL) into the current check-and-fill
`Enable-Claude3P.ps1`. See `SUMMARY.md` §4 (audit results, 14 findings all
resolved) and the `_archive\` folder for the superseded v1 code.
