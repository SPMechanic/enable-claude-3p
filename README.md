<div align="center">

# 🚀 Enable-Claude 3P

### Run Claude Desktop & Claude Code CLI on the **LLM-Kita** gateway — one idempotent script

![Platform](https://img.shields.io/badge/Platform-Windows-0078D4?logo=windows)
![Shell](https://img.shields.io/badge/Shell-PowerShell%205.1%2B-5391FE?logo=powershell)
![Target](https://img.shields.io/badge/Targets-Claude%20Desktop%20%2B%20CLI-D97757)
![Mode](https://img.shields.io/badge/Mode-Idempotent-2DA44E)
![Health](https://img.shields.io/badge/Probe-Live%20Failover-6E40C9)

</div>

---

> 💡 **TL;DR —** You have an LLM-Kita API key and want Claude Desktop (and the
> Code CLI) to route through it instead of Anthropic's default endpoint. Run
> **one script**, it probes the gateway, writes the config, syncs the CLI, and
> you restart. Done.

---

## 📖 What & Why

### What is LLM-Kita?

**LLM-Kita** is a third-party API gateway that exposes an
Anthropic-compatible endpoint. You sign up with LLM-Kita, receive an API key,
and Claude can then talk to `https://chat-api.llm-kita.com` instead of
`https://api.anthropic.com`. The gateway forwards your requests to the same
Claude models (Sonnet, Opus, Haiku) you'd use otherwise.

### What is "3P mode"?

Claude Desktop's name for "use a third-party gateway." When
`claude_desktop_config.json` has `deploymentMode: "3p"`, the app reads its
gateway config (URL + key) from a `configLibrary` entry instead of hitting
Anthropic directly. That's all it is — a redirect at the app level.

### Why do this?

| Perk | What it gets you |
|---|---|
| 💰 **Cost** | LLM-Kita offers its own pricing/billing — often cheaper than paying Anthropic directly for heavy Desktop usage. |
| 🔑 **One key, two apps** | The same LLM-Kita key serves both Claude Desktop *and* the Claude Code CLI. One credential, not two. |
| 🔄 **Failover built in** | The script probes two endpoints (`chat-api.llm-kita.com` → `api.llm-kita.com/api`) and picks the first healthy one. If one is down, the other takes over. |
| 🧰 **Sensible defaults** | PowerShell tool, tool-search, autocompact, git allowlist — all preconfigured for a smooth CLI experience. |

> ⚠️ **You bring the key.** This script does not give you an LLM-Kita account
> or key. Get those from LLM-Kita first, then run the script.

---

## ✅ Prerequisites

- 🪟 **Windows** with PowerShell 5.1 or newer (PowerShell 7 works too).
- 📦 **Claude Desktop** and/or **Claude Code CLI** installed (winget or MSIX/Store).
- 🔧 **Git for Windows** — *strongly recommended*. The settings template hardcodes a Git Bash path and ships `Bash(git ...)` permission entries. Without Git, those entries are non-functional (the CLI still works via the PowerShell tool). The script warns you at apply time if Git is missing.
- 🗝️ **Your LLM-Kita API key** (get it from LLM-Kita before you start).

---

## 🚀 Tutorial: Get running in 5 steps

Follow these top-to-bottom. Each step builds on the last.

### Step 1 — Grab your key

Make sure you have your LLM-Kita API key ready (a string like
`sk-...` or `pr-...`). You'll pass it via `-NewKey` or be prompted for it
masked.

### Step 2 — Audit your current state (dry run, nothing written)

Before touching anything, see what state your machine is in. With **no**
`-Apply`/`-Interactive`/`-Restore` flag, the script is a **dry run**: it
reports your current 3P state, probes both failover endpoints, lists every
credential location, and prints stale keys found on disk.

```bash
.\Enable-Claude3P.ps1
```

Look for the probe result:

```
 /v1/models   : 200   (https://chat-api.llm-kita.com)
 /v1/messages : 200 (model=auto)
```

> ℹ️ **`model=auto` in the probe is fine.** That's the gateway advertising a
> model literally named `auto` (meaning "let the gateway pick"), which the
> probe prefers for its inference health check. It's unrelated to the legacy
> `"model": "auto"` settings value that this script fixes to `claude-sonnet-5-5`.

If either status isn't `200`, stop — your key or base URL is wrong, and
`-Apply` would refuse anyway (exit 2).

### Step 3 — Back up (precaution)

The script writes a `.bak` next to every file it touches, but for your own
rollback anchor, copy the two files that matter most before any write:

```bash
$stamp = Get-Date -Format yyyyMMdd-HHmmss
Copy-Item "$env:USERPROFILE\.claude\settings.json" "$env:USERPROFILE\settings.json.backup-$stamp" -ErrorAction SilentlyContinue
Copy-Item "$env:USERPROFILE\.claude.json"           "$env:USERPROFILE\.claude.json.backup-$stamp"   -ErrorAction SilentlyContinue
```

(If a file doesn't exist yet, the copy errors harmlessly — skip it.)

### Step 4 — Apply

**First-time / interactive (asks y/N before writing):**

```bash
.\Enable-Claude3P.ps1 -Interactive -NewKey "<YOUR-LLM-KITA-KEY>"
```

**Or non-interactive (CI / you know what you're doing):**

```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<YOUR-LLM-KITA-KEY>" -Force
```

That single command will:

1. 🔍 **Probe** the LLM-Kita gateway (both failover endpoints, first healthy wins).
2. 📝 **Show a plain-English summary** of every file it will write (with
   `-Interactive`).
3. ❓ **Ask `y/N`** before writing anything (with `-Interactive`).
4. On `y`: create `claude_desktop_config.json`, write the gateway entry, sync
   `settings.json`, set the `LLM_KITA_API_KEY` env var, and seed the CLI
   onboarding flags so the first-run wizard is skipped.

<details>
<summary><b>📦 What gets written — both scenarios</b></summary>

The script touches two JSON files in your home directory. What you end up with
depends on whether they existed before. Both paths are covered by the test
harness (`test-settings-env.ps1` 12 cases + `validate-template.ps1`).

#### Scenario A — neither file exists (truly pristine install)

**`~/.claude/settings.json`** is created from a hardcoded template, then the
gateway key/URL are filled in from `-NewKey`:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "<YOUR-KEY>",
    "ANTHROPIC_API_KEY": "<YOUR-KEY>",
    "ANTHROPIC_BASE_URL": "https://chat-api.llm-kita.com/",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80",
    "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1",
    "ENABLE_TOOL_SEARCH": "true",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-5-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-5-5",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4.8"
  },
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [ "... 32 PowerShell + Bash git allow entries ..." ]
  },
  "model": "claude-sonnet-5-5",
  "enableWorkflows": true,
  "defaultShell": "powershell",
  "outputStyle": "Concise"
}
```

**`~/.claude.json`** is created from scratch with just the onboarding flags
(the app populates `machineID`/`userID`/`projects`/etc. on first launch):

```json
{
  "hasCompletedOnboarding": true,
  "hasTrustDialogAccepted": true,
  "hasResetAutoModeOptInForDefaultOffer": true,
  "_enableClaude3pSeededOnboarding": true
}
```

The three onboarding bools suppress the CLI's first-run wizard, project-trust
prompt, and auto-mode opt-in. The sentinel marks them as *script-seeded* so
`-Restore` can remove exactly those later without touching onboarding you did
via the stock flow.

#### Scenario B — both files already exist

The script **only adds missing keys — it never overwrites a value you set
yourself**. Your existing `enabledPlugins`, `extraKnownMarketplaces`,
`permissions`, custom `model`, and any custom tier vars are preserved
byte-for-byte (proven by the harness against a 12-plugin / 8-marketplace
fixture spanning every schema `source` variant).

**`~/.claude/settings.json`** — `Ensure-SettingsEnvFields` injects, *only if
absent*:

| Field | Value if inserted |
|---|---|
| `env` (the whole block) | created as `{}` if missing |
| `env.ANTHROPIC_AUTH_TOKEN` | `""` (then filled with your key) |
| `env.ANTHROPIC_API_KEY` | `""` (then filled with your key) |
| `env.ANTHROPIC_BASE_URL` | `""` (then filled with the probed URL) |
| `env.API_TIMEOUT_MS` | `"3000000"` |
| `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | `"80"` |
| `env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `"1"` |
| `env.CLAUDE_CODE_USE_POWERSHELL_TOOL` | `"1"` |
| `env.ENABLE_TOOL_SEARCH` | `"true"` |
| `env.ANTHROPIC_DEFAULT_SONNET_MODEL` | `"claude-sonnet-5-5"` |
| `env.ANTHROPIC_DEFAULT_HAIKU_MODEL` | `"claude-haiku-5-5"` |
| `env.ANTHROPIC_DEFAULT_OPUS_MODEL` | `"claude-opus-4.8"` |
| top-level `model` | `"claude-sonnet-5-5"` if absent; rewritten from the legacy `"auto"` alias to `"claude-sonnet-5-5"`; **any other value preserved verbatim** |

Key difference from Scenario A: an existing file does **not** gain
`$schema`, the `permissions` block, `enableWorkflows`, `defaultShell`, or
`outputStyle` — those live only in the pristine template. An existing file
keeps its own shape; only the env gateway vars, the three tier-mapping vars,
and `model` are touched. If every one of those is already present and
correct, the file is a byte-identical no-op (idempotent re-run).

**`~/.claude.json`** — `Set-ClaudeStateOnboarding` adds the same three
onboarding bools + sentinel, *only if absent*. All app-owned state
(`machineID`, `userID`, `firstStartTime`, `projects`, `pluginUsage`,
`skillUsage`, migration version, etc.) is preserved via a `-Depth 50`
parse/merge/serialize round-trip. If the bools are already present, the file
is untouched. If the file is corrupt JSON or a non-object (array/scalar), the
script refuses to touch it and exits 6.

#### Guarantees that hold in either scenario

- **Every write is backed up first** (a `.bak.TIMESTAMP` sits next to the
  original).
- **No-BOM UTF-8** (`[System.IO.File]::WriteAllText` with
  `UTF8Encoding($false)`).
- **Re-parse guard**: after writing, the file is parsed again; if it's invalid
  JSON the script exits 3 (`settings.json`) or 6 (`.claude.json`) and tells you
  to restore from the `.bak`.
- **Idempotent**: re-running with the same key changes nothing (no `.bak`
  stacking, byte-identical output).

</details>

### Step 5 — Restart & verify

The env vars and credential files are read at **launch**, not on the fly. So:

1. 🛑 **Fully quit Claude Desktop AND the CLI** — not minimized, actually
   exited (check Task Manager for `Claude.exe`, `claude`, and any `node` CLI
   processes).
2. ▶️ **Launch them fresh.**
3. ✅ **Confirm the log is clean:**

```bash
Get-Content "$env:LOCALAPPDATA\Claude-3p\logs\main.log" -Tail 200 |
  Select-String 'Opening 3P setup window|credential rejected'
```

No output = clean. If you see `credential rejected`, your key or base URL is
wrong — re-run the audit (`.\Enable-Claude3P.ps1`).

🎉 **You're on the gateway.**

---

## 🧹 Deep clean: full hygiene key rotation

Use this when you're rotating to a new key and want stale copies of the old
key purged from disk, the registry, and caches — the most thorough refresh.

> ⚠️ **Read this first.** This path runs destructive flags. Step 0 (quit) and
> Step 1 (manual backup) are not optional.

**0. Fully quit Claude Desktop + CLI.**

```bash
Get-Process Claude, claude -ErrorAction SilentlyContinue | Stop-Process -Force
```

**1. Back up both files by hand** (your rollback anchor — see Step 3 above).

**2. Choose a path:**

<details>
<summary><b>🅰️ Path A — conservative (keep current config, rotate + scrub)</b></summary>

Keeps your existing `enabledPlugins` / `extraKnownMarketplaces` / `permissions`
/ `model` untouched; only the key, URL, tier vars, and onboarding flags are
synced, stale old-key copies are overwritten, and caches are cleared:

```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<NEW-KEY>" -AuthScheme Bearer `
  -ScrubStale -ScrubEnv -ResetCaches -Force
```

</details>

<details>
<summary><b>🅱️ Path B — clean baseline (Restore first, then fresh apply)</b></summary>

Use this if your config is in an unknown state, or you want a guaranteed-clean
slate. `-Restore` wipes everything 3P-related (deploymentMode, gateway entry,
`_meta.json`, CLI gateway fields, the seeded onboarding bools) preserving your
`.bak` files, then you re-apply fresh. **Restore removes your working 3P
setup** — that's the point, but it's why Step 1's manual backup matters:

```bash
.\Enable-Claude3P.ps1 -Restore -Apply -Force
.\Enable-Claude3P.ps1 -Apply -NewKey "<NEW-KEY>" -AuthScheme Bearer `
  -ScrubStale -ScrubEnv -ResetCaches -Force
```

</details>

**3. Restart Claude Desktop + CLI, then run the log check from Step 5.**

---

## 📚 Reference

<details>
<summary><b>🔧 Parameter reference (click to expand)</b></summary>

| Parameter | What it does |
|---|---|
| `-NewKey "<KEY>"` | Your LLM-Kita gateway key. Omit to be prompted (masked). |
| `-BaseUrl "<URL>"` | Probe ONLY this URL instead of failover. Add `-SkipProbe` to write without probing. |
| `-AuthScheme bearer` | Auth scheme written to the gateway entry. Default `bearer`. |
| `-Models "<JSON>"` | Optional JSON array overriding the model catalog. Each entry needs `name` (wire model id, load-bearing) + `labelOverride` (UI label); other fields fill with defaults. Full rebuild — result has exactly as many entries as you pass. Passing it replaces an existing catalog (reported first). Omit to keep the default 3-model catalog on pristine installs. Exit 7 on bad JSON or missing fields. |
| `-Apply` | Commit changes. Without it, dry run only. |
| `-Interactive` | Like `-Apply` but prints a summary and asks `y/N`. Implies `-Apply`. **The safe default for humans.** |
| `-SkipProbe` | Write the key/URL without probing. You accept them unverified. |
| `-NoSyncCli` | Don't touch the CLI `settings.json`. Use when the CLI points at another provider. |
| `-MachineEnv` | Also write `LLM_KITA_API_KEY` to the machine-wide registry (HKLM). **Requires admin.** |
| `-ScrubStale` | Overwrite stale keys found in history/transcripts/backups with the new key. Hygiene only. |
| `-ScrubEnv` | Remove stale `ANTHROPIC_*` / `LLM_KITA_API_KEY` values from the registry. **Multi-provider safe:** only removes values whose base URL is an LLM-Kita host, or empty values. Never deletes a non-empty non-LLM-Kita key. |
| `-ResetCaches` | Delete Electron caches (Cache, Code Cache, GPUCache...). Safe; they regenerate on next launch. |
| `-Restore` | Undo 3P: remove `deploymentMode`, delete the gateway entry, zero `_meta.json`, strip CLI gateway fields. Use with `-Apply`. |
| `-Force` | Proceed with writes even while `Claude.exe` is running (also skips the `y/N` prompt). |

</details>

<details>
<summary><b>📦 Where it writes (click to expand)</b></summary>

| What | Where | Why |
|---|---|---|
| **Desktop gateway config** | `%LOCALAPPDATA%\Claude-3p\claude_desktop_config.json` | Sets `deploymentMode: "3p"` so Desktop uses the gateway. Preserves any existing MCP-server config. |
| **Gateway entry** | `...\Claude-3p\configLibrary\<id>.json` + `_meta.json` | The actual gateway URL, key, and auth scheme. Includes a 3-model catalog (Sonnet/Opus/Haiku). |
| **CLI settings** | `~/.claude\settings.json` + `~/.claude.json` | Syncs the same key/URL to the Claude Code CLI, plus sensible defaults. **Skipped with `-NoSyncCli`.** |

It also sets a `LLM_KITA_API_KEY` user environment variable (so the key is
available to other tools and new shells).

</details>

<details>
<summary><b>🧩 Advanced combinations (click to expand)</b></summary>

#### Present the native 3-model Claude pair

```bash
.\Enable-Claude3P.ps1 -Interactive -NewKey "<YOUR-LLM-KITA-KEY>" `
  -Models '[{"name":"claude-sonnet-5-5","labelOverride":"Sonnet 5.5"},{"name":"claude-opus-4.8","labelOverride":"Opus 4.8"},{"name":"claude-haiku-5-5","labelOverride":"Haiku 5.5"}]' `
  -AuthScheme Bearer -ScrubStale -ResetCaches -Force
```

| Pos | Tier | `name` | `labelOverride` |
|---|---|---|---|
| 0 | sonnet | `claude-sonnet-5-5` | `Sonnet 5.5` |
| 1 | opus | `claude-opus-4.8` | `Opus 4.8` |
| 2 | haiku | `claude-haiku-5-5` | `Haiku 5.5` |

Subsets work too — pass only the tiers you want. Pass `-Models '[]'` to clear
the catalog entirely. Omit `-Models` to leave an existing catalog untouched.

#### Multi-provider: Desktop on LLM-Kita, CLI on OpenRouter

```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KITA-KEY>" -NoSyncCli
```

The CLI keeps whatever `ANTHROPIC_BASE_URL` it already has (OpenRouter, etc.),
and only Desktop flips to LLM-Kita.

#### Machine-wide key (admin, shared workstation)

```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>" -MachineEnv -Force
```

Writes `LLM_KITA_API_KEY` to HKLM so every user on the machine gets it.

#### Write a custom gateway URL without probing

```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>" -BaseUrl "https://custom.llm-kita.example/v1" -SkipProbe
```

For when you have a private/dedicated endpoint or the probe is blocked by a
firewall.

#### Post-compromise cleanup without re-applying

```bash
.\Enable-Claude3P.ps1 -Apply -ScrubStale -ScrubEnv -ResetCaches -Force
```

If you rotated the key elsewhere and just want to scrub the old one from disk
and the registry. (Omit `-NewKey`; the script uses the existing key.)

</details>

<details>
<summary><b>🚦 Exit codes (click to expand)</b></summary>

| Code | Meaning |
|---|---|
| `0` | ✅ Success, dry-run completion, or "nothing to do" (e.g. Restore on an already-stock install). |
| `1` | ❌ No Claude-3p install found, or no key supplied and none found on disk. |
| `2` | ❌ Gateway probe failed — neither failover endpoint was healthy for the supplied key. |
| `3` | ❌ `settings.json` parse error — the file is invalid JSON before or after a write. Inspect the `.bak`. |
| `4` | ❌ `claude_desktop_config.json` / configLibrary re-parse failure after a write. Inspect the `.bak`. |
| `5` | ⚠️ Aborted — user answered `N` at a confirm, or a non-interactive session without `-Force`. |
| `6` | ❌ `.claude.json` parse error — the CLI state file is invalid JSON before or after a write. Inspect the `.bak`. |
| `7` | ❌ `-Models` validation failed — bad JSON, not an array, or an entry missing `name` or `labelOverride`. |

</details>

<details>
<summary><b>🛠️ Troubleshooting (click to expand)</b></summary>

#### "Claude Desktop still hits Anthropic after running"

1. Run a dry run: `.\Enable-Claude3P.ps1` — check the `deploymentMode` row says `3p`.
2. If it says `3p`, the app may be caching. Quit fully (check Task Manager), then
   run `.\Enable-Claude3P.ps1 -Apply -ResetCaches -Force`, then relaunch.
3. If `deploymentMode` is blank, re-run `-Apply -NewKey "<KEY>"` — the script's
   `Ensure-DesktopDeploymentMode` helper inserts it.

#### "The CLI Code tab doesn't use the gateway"

You likely ran with `-NoSyncCli`. Re-run without it:
`.\Enable-Claude3P.ps1 -Interactive -NewKey "<KEY>"`.

#### "Git Bash warning at apply time"

The script couldn't find Git for Windows. Install it
(`winget install Git.Git`), or ignore the warning — the CLI works via the
PowerShell tool regardless, but `Bash(git ...)` allow entries won't function
until Git is installed.

#### Backups

Every write produces a `.bak` next to the original (e.g.
`settings.json.bak`, `claude_desktop_config.json.bak`). To recover, quit Claude,
copy the `.bak` over the live file, and relaunch.

</details>

<details>
<summary><b>⛔ What to avoid (click to expand)</b></summary>

| Don't | Why | Do this instead |
|---|---|---|
| **Run anything in `_archive\`** | That folder holds superseded/dead code (`Initialize-ClaudeConfig.ps1`, `gateway.py`, `sync-gateway-key.ps1`) and old credential-bearing copies. `Initialize-ClaudeConfig.ps1` is the destructive v1 (wholesale overwrite, BOM, placeholder URL). | Always use `Enable-Claude3P.ps1`. |
| **Run with `-Apply` before auditing** | You skip the chance to see what would change. | Run a bare dry run first (no flags), then `-Interactive`. |
| **Edit the config files manually after running** | The script is idempotent and check-and-fill; manual edits can desync `deploymentMode`/`configLibrary`/`_meta.json`/`settings.json` from each other. | Re-run the script with the new key/URL — it updates all locations atomically. |
| **Use `-SkipProbe` casually** | You write a key/URL that was never validated. A typo'd URL or dead key silently breaks Claude Desktop at launch. | Let the probe run. Only use `-SkipProbe` if a firewall blocks it or you have a private endpoint you've tested manually. |
| **Use `-NoSyncCli` when you want the CLI in 3P too** | The CLI keeps pointing at Anthropic (or wherever it was) — the Code tab inside Desktop won't use the gateway. | Omit `-NoSyncCli`. It's opt-*out*, not opt-*in*. |
| **Run while Claude Desktop is open** (without `-Force`) | The script warns and refuses; forcing writes while the app holds file handles can produce partial writes. | Quit Claude Desktop first. If you must force, the `.bak` files let you recover. |
| **Use `-MachineEnv` without admin** | The HKLM write fails partway — the user-level env var is set but the machine-wide one isn't, leaving an inconsistent state. | Run from an elevated shell, or omit `-MachineEnv`. |
| **Use `-ScrubEnv` blindly with other providers** | It's multi-provider safe by design (only removes LLM-Kita-host-matching or empty values), but **audit first** with a dry run to see exactly what it'll touch. | Run `.\Enable-Claude3P.ps1` (no `-Apply`) with `-ScrubEnv` to audit, then `-Apply`. |
| **Pass a key containing quotes or control chars** | The regex-based field writers don't JSON-encode. The script's own callers pass keys/URLs (no raw `"`), so this is safe in practice — but a hand-edited key with a `"` would produce invalid JSON. | Use the key exactly as LLM-Kita issued it. |
| **Expect `-Restore` to fix a corrupt install** | Restore is a clean inverse of *what this script did*. If your config is corrupt from manual edits, Restore may not know what to undo. | Restore from the `.bak` files, or do a clean reset (Restore → re-Apply). |
| **Pass `-Models` with a `name` the gateway doesn't serve** | `name` is the wire model id sent in every API request — load-bearing. A typo or a model the gateway doesn't route silently breaks inference at launch. `labelOverride` is UI-only and safe to set to anything. | Confirm the `name` values against the gateway's model list first. |

</details>

---

## ↩️ Undo (Restore)

```bash
.\Enable-Claude3P.ps1 -Restore -Apply -Force
```

Restore is a **true factory-reset** of what this script did:

- 🗑️ Removes `deploymentMode` from `claude_desktop_config.json` (preserves MCP config).
- 🗑️ Deletes the `configLibrary` gateway entry, zeros `_meta.json`.
- 🗑️ Strips `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` from
  `settings.json` (preserves everything else).
- 🗑️ Removes the onboarding bools it seeded in `.claude.json` — but **only if it
  seeded them**. A sentinel field (`_enableClaude3pSeededOnboarding`) marks
  script-seeded bools vs. app/user-seeded ones, so if you completed Claude's
  stock onboarding *before* running 3P, your onboarding state is left intact.

After Restore, Claude Desktop + CLI are back on the default Anthropic endpoint.

---

## 🧪 Tested scenarios

The script has been verified against these states (full list in `SUMMARY.md`):

- ✅ Truly pristine winget install (no dirs, no files).
- ✅ Pristine MSIX/Store install (Packages\Claude_* enumeration).
- ✅ Pristine "app launched once then quit".
- ✅ Idempotent re-run with the same key (no `.bak` stacking, byte-identical).
- ✅ Key rotation across all locations.
- ✅ Existing stock Claude applying 3P (`.claude.json` state preserved).
- ✅ `-ScrubEnv` with non-LLM-Kita values (host-matching preserves them).
- ✅ `-Restore` on an already-stock install (clean no-op).
- ✅ **`settings.json` 12 file shapes**: no file, `{}`, minimal-universal, complex
  nested plugins+marketplaces (real user shape), legacy `"model":"auto"`, custom
  model id, custom tier var, corrupt JSON, no-env, empty-env, array-root, and a
  scaled 12-plugin / 8-marketplace fixture across all schema `source` variants.
- ✅ **Pristine template**: AST-extracted and asserted to carry the three
  tier-mapping vars, `model=claude-sonnet-5-5` (not `"auto"`), and the full
  env/permissions/shell shape.

---

## 🔧 For developers / maintainers

- 📋 **Audit & architecture details:** see `SUMMARY.md` — full audit findings table
  (14 findings, all resolved), helper-function reference, and test coverage.
- 🧪 **Tests:** `test-helpers.ps1` (156 assertions, all functions + Restore logic),
  `test-settings-env.ps1` (70 assertions across 12 file shapes, including a
  scaled 12-plugin / 8-marketplace fixture spanning every schema `source`
  variant), and `validate-template.ps1` (AST-based pristine-template validation,
  asserting the tier-mapping vars + `model` field are present and `model != "auto"`).

  ```bash
  powershell -ExecutionPolicy Bypass -File .\validate-template.ps1
  powershell -ExecutionPolicy Bypass -File .\test-settings-env.ps1
  powershell -ExecutionPolicy Bypass -File .\test-helpers.ps1
  ```

- ⚙️ **The main script self-executes on dot-source** (it has a `param()` block +
  top-level logic, not a pure library). The test harness inlines copies of the
  helpers rather than dot-sourcing.
- 📝 **All JSON writes are no-BOM UTF-8** via `[System.IO.File]::WriteAllText` with
  `UTF8Encoding($false)`.

---

<div align="center">

<sub>Built for the LLM-Kita gateway · One script, one key, two apps.</sub>

</div>
