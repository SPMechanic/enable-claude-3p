# Enable-Claude 3P  -  Run Claude Desktop on the LLM-Kita gateway

A single PowerShell script that flips Claude Desktop (and optionally the Claude
Code CLI) into **3P mode**  -  routing requests through an **LLM-Kita** gateway
instead of the default Anthropic endpoint. One idempotent, newbie-safe command.

---

## 1. What is LLM-Kita, and why 3P mode?

**LLM-Kita** is a third-party API gateway that exposes an
Anthropic-compatible endpoint. You sign up with LLM-Kita, receive an API key,
and Claude Desktop can then talk to `https://chat-api.llm-kita.com` instead of
`https://api.anthropic.com`. The gateway forwards your requests to the same
Claude models (Sonnet, Opus, Haiku) you'd use otherwise.

**Why do this?** The practical reasons:

- **Cost.** LLM-Kita offers its own pricing/billing. Depending on your plan,
  usage can be cheaper than paying Anthropic directly  -  especially for heavy
  Desktop usage where token costs add up fast.
- **One key, two apps.** The same LLM-Kita key serves both Claude Desktop *and*
  the Claude Code CLI, so you manage one credential instead of two.
- **Failover built in.** The script probes two LLM-Kita endpoints
  (`chat-api.llm-kita.com` → `api.llm-kita.com/api`) and picks the first healthy
  one. If one is down, the other takes over automatically.

**"3P mode"** is Claude Desktop's name for "use a third-party gateway." When
`claude_desktop_config.json` has `deploymentMode: "3p"`, the app reads its
gateway config (URL + key) from a `configLibrary` entry instead of hitting
Anthropic directly. That's all it is  -  a redirect at the app level.

> **You bring the key.** This script does not give you an LLM-Kita account or
> key. Get those from LLM-Kita first, then run the script.

---

## 2. What the script does to your machine

It writes to up to three places. **Every write is backed up first** (a `.bak`
copy sits next to the original), and the script only writes what's missing or
wrong  -  it never overwrites a value you already set.

| What | Where | Why |
|---|---|---|
| **Desktop gateway config** | `%LOCALAPPDATA%\Claude-3p\claude_desktop_config.json` | Sets `deploymentMode: "3p"` so Desktop uses the gateway. Preserves any existing MCP-server config. |
| **Gateway entry** | `...\Claude-3p\configLibrary\<id>.json` + `_meta.json` | The actual gateway URL, key, and auth scheme. Includes a 3-model catalog (Sonnet/Opus/Haiku). |
| **CLI settings** | `~/.claude\settings.json` + `~/.claude.json` | Syncs the same key/URL to the Claude Code CLI, plus sensible defaults. **Skipped with `-NoSyncCli`.** |

It also sets a `LLM_KITA_API_KEY` user environment variable (so the key is
available to other tools and new shells).

### The `settings.json` you'll get (pristine installs)

If `~/.claude/settings.json` doesn't exist yet, the script creates it with
these defaults:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_BASE_URL": "",
    "API_TIMEOUT_MS": "3000000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1",
    "ENABLE_TOOL_SEARCH": "true"
  },
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [ "... 32 PowerShell + Bash git allow entries ..." ]
  },
  "model": "auto",
  "enableWorkflows": true,
  "defaultShell": "powershell",
  "outputStyle": "Concise"
}
```

The key/URL are filled in immediately after from your `-NewKey`. If
`settings.json` already exists, the script **only adds missing keys**  -  it
never overwrites values you set yourself.

---

## 3. Prerequisites

- **Windows** with PowerShell 5.1 or newer (PowerShell 7 works too).
- **Claude Desktop** and/or **Claude Code CLI** installed (winget or MSIX/Store).
- **Git for Windows**  -  *strongly recommended*. The settings template hardcodes
  a Git Bash path and ships `Bash(git ...)` permission entries. Without Git, those
  entries are non-functional (the CLI still works via the PowerShell tool). The
  script warns you at apply time if Git is missing.
- **Your LLM-Kita API key** (get it from LLM-Kita before you start).

---

## 4. Quick start (newbie path)

If you're on a fresh install and just want it working:

```bash
powershell -ExecutionPolicy Bypass -File .\Enable-Claude3P.ps1 -Force

powershell -ExecutionPolicy Bypass -File .\Enable-Claude3P.ps1 -Interactive -NewKey "YOUR-LLM-KITA-KEY" -Force
```

That single command will:

1. **Probe** the LLM-Kita gateway (both failover endpoints, first healthy wins).
2. **Show you a plain-English summary** of every file it will write.
3. **Ask `y/N`** before writing anything.
4. On `y`: create `claude_desktop_config.json`, write the gateway entry, create
   `settings.json` with the key/URL, set the `LLM_KITA_API_KEY` env var, and
   seed the CLI onboarding flags so the first-run wizard is skipped.

Launch Claude Desktop  -  it should now route through LLM-Kita.

### Not sure? Audit first (no writes)

```bash
powershell -ExecutionPolicy Bypass -File .\Enable-Claude3P.ps1
```

With no `-Apply`/`-Interactive`/`-Restore`, the script is a **dry run**: it
reports your current 3P state, probes both endpoints, lists every credential
location, and prints stale keys found on disk  -  **nothing is written**. Run this
first if you're unsure what state your machine is in.

---

## 5. Parameter reference

| Parameter | What it does |
|---|---|
| `-NewKey "<KEY>"` | Your LLM-Kita gateway key. Omit to be prompted (masked). |
| `-BaseUrl "<URL>"` | Probe ONLY this URL instead of failover. Add `-SkipProbe` to write without probing. |
| `-AuthScheme bearer` | Auth scheme written to the gateway entry. Default `bearer`. |
| `-Models "<JSON>"` | Optional JSON array overriding the model catalog. Each entry needs `name` (wire model id, load-bearing) + `labelOverride` (UI label); other fields fill with defaults. Full rebuild  -  result has exactly as many entries as you pass. Passing it replaces an existing catalog (reported first). Omit to keep the default 3-model catalog on pristine installs. Exit 7 on bad JSON or missing fields. |
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

---

## 6. Usage recipes

### First-time setup (pristine, interactive)
```bash
.\Enable-Claude3P.ps1 -Interactive -NewKey "<KEY>"
```

### Audit only (dry run  -  no writes)
```bash
.\Enable-Claude3P.ps1
```

### CI / automation (non-interactive)
```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>" -Force
```

### Rotate the key interactively (prompts for the new key, masked)
```bash
.\Enable-Claude3P.ps1 -Interactive
```

### Recover from a bad base URL (omit `-BaseUrl`; both endpoints probed, first healthy wins)
```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>"
```

### Desktop-only 3P (leave the CLI pointed at OpenRouter/OpenCode/KiloCode)
```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>" -NoSyncCli
```

### Full hygiene pass (after a key compromise or rotation)
```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>" -ScrubStale -ScrubEnv -ResetCaches -Force
```

### Revert to stock Anthropic mode
```bash
.\Enable-Claude3P.ps1 -Restore -Apply -Force
```

### Present the native 3-model Claude pair

The default catalog the script seeds on a pristine install is the native
3-model Claude pair (Sonnet / Opus / Haiku). This is the recommended baseline:

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

Subsets work too - pass only the tiers you want. Pass `-Models '[]'` to clear
the catalog entirely. Omit `-Models` to leave an existing catalog untouched
(the default 3-model catalog only seeds on pristine installs).

### Safe retest flow (live probe, no guessing)

Every run probes the gateway live **unless you pass `-SkipProbe`**. The probe
hits `/v1/models` (key valid?) and `/v1/messages` (inference works?), then
prints the HTTP status of each before anything is written. Use this two-step
flow to verify the model id + labelOverride mapping safely:

**1. Dry-run first  -  probe + report, no writes.** Omits `-Apply`, so the
script probes the gateway, shows the current catalog, and prints what it
*would* write. Nothing touches disk:

```bash
.\Enable-Claude3P.ps1 -NewKey "<YOUR-LLM-KITA-KEY>" `
  -Models '[{"name":"claude-sonnet-5-5","labelOverride":"Sonnet 5.5"},{"name":"claude-opus-4.8","labelOverride":"Opus 4.8"},{"name":"claude-haiku-5-5","labelOverride":"Haiku 5.5"}]' `
  -AuthScheme Bearer
```

Look for `Probe` output like:
```
 /v1/models   : 200   (https://chat-api.llm-kita.com)
 /v1/messages : 200 (model=auto)
```
If either is not `200`, stop  -  the key or base URL is wrong, and `-Apply`
would refuse anyway (exit 2 when the probe fails under `-Apply`).

**2. Apply once the probe is green.** Add `-Apply` (and `-Force` if Claude
processes are running) to commit:

```bash
.\Enable-Claude3P.ps1 -Apply -Force -NewKey "<YOUR-LLM-KITA-KEY>" `
  -Models '[{"name":"claude-sonnet-5-5","labelOverride":"Sonnet 5.5"},{"name":"claude-opus-4.8","labelOverride":"Opus 4.8"},{"name":"claude-haiku-5-5","labelOverride":"Haiku 5.5"}]' `
  -AuthScheme Bearer -ScrubStale -ResetCaches
```

**Switching the probe variant**  -  to probe a *different* base URL than the
default failover list, pass `-BaseUrl` (the script probes only that URL). To
write a URL without probing it at all (e.g. the endpoint is up but blocks
`/v1/models`), pass `-SkipProbe`:

```bash
# Probe only a custom URL, then apply if healthy
.\Enable-Claude3P.ps1 -Apply -NewKey "<YOUR-LLM-KITA-KEY>" `
  -BaseUrl "https://chat-api.llm-kita.com" -Models '[{"name":"claude-sonnet-5-5","labelOverride":"Sonnet 5.5"},{"name":"claude-opus-4.8","labelOverride":"Opus 4.8"},{"name":"claude-haiku-5-5","labelOverride":"Haiku 5.5"}]' `
  -AuthScheme Bearer -Force

# Skip the probe entirely (writes without verifying health)
.\Enable-Claude3P.ps1 -Apply -SkipProbe -NewKey "<YOUR-LLM-KITA-KEY>" `
  -Models '[{"name":"claude-sonnet-5-5","labelOverride":"Sonnet 5.5"},{"name":"claude-opus-4.8","labelOverride":"Opus 4.8"},{"name":"claude-haiku-5-5","labelOverride":"Haiku 5.5"}]' `
  -AuthScheme Bearer -Force
```

The probe does not test each model id individually  -  `/v1/messages` uses
`model=auto` for its health check. To confirm a specific `name` routes before
committing, curl the gateway directly:

```bash
curl -s -H "Authorization: Bearer <YOUR-LLM-KITA-KEY>" \
  "https://chat-api.llm-kita.com/v1/models" | grep -o '"id":"[^"]*"'
```
That prints every model id the gateway serves; match your `name` values
against it.

Pass `-Models` to set the inference catalog yourself. `name` is the model id
sent in API requests (load-bearing  -  a wrong value silently breaks inference);
`labelOverride` is the UI label only. The result has exactly as many entries as
you pass  -  other fields (`supports1m`, `isFamilyDefault`, `maxEffort`,
`anthropicFamilyTier`) fill with defaults if you omit them. `anthropicFamilyTier`
defaults by position: `sonnet`/`opus`/`haiku` for indices 0-2,
then `sonnet` for index 3+. Passing `-Models` on an install that already has a
catalog reports the current catalog first, then replaces it. Pass `-Models '[]'`
to clear the catalog entirely (empty array = valid rebuild target, not omitted).
Omit `-Models` to leave an existing catalog untouched (the default 3-model
catalog only seeds on pristine installs).

---

## 7. Advanced combinations

These are the power-user patterns. Read carefully before combining flags.

### Clean reset (restore → re-apply)
```bash
.\Enable-Claude3P.ps1 -Restore -Apply -Force
.\Enable-Claude3P.ps1 -Interactive -NewKey "<NEW-KEY>"
```
Use when your config is in an unknown state and you want a guaranteed-clean
baseline. Restore wipes everything 3P-related (preserving your `.bak` files),
then you re-apply fresh.

### Multi-provider: Desktop on LLM-Kita, CLI on OpenRouter
```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KITA-KEY>" -NoSyncCli
```
The CLI keeps whatever `ANTHROPIC_BASE_URL` it already has (OpenRouter, etc.),
and only Desktop flips to LLM-Kita. The `LLM_KITA_API_KEY` env var is still set
globally  -  if you don't want that, unset it manually after.

### Machine-wide key (admin, shared workstation)
```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>" -MachineEnv -Force
```
Writes `LLM_KITA_API_KEY` to HKLM so every user on the machine gets it. Requires
an elevated shell.

### Write a custom gateway URL without probing
```bash
.\Enable-Claude3P.ps1 -Apply -NewKey "<KEY>" -BaseUrl "https://custom.llm-kita.example/v1" -SkipProbe
```
For when you have a private/dedicated endpoint or the probe is blocked by a
firewall. You're accepting the key/URL unverified  -  `-Interactive` will warn
before confirming.

### Post-compromise cleanup without re-applying
```bash
.\Enable-Claude3P.ps1 -Apply -ScrubStale -ScrubEnv -ResetCaches -Force
```
If you rotated the key elsewhere and just want to scrub the old one from disk
and the registry. (Omit `-NewKey`; the script uses the existing key for the
scrub-overwrite.)

---

## 8. What to avoid

| Don't | Why | Do this instead |
|---|---|---|
| **Run anything in `_archive\`** | That folder holds superseded/dead code (`Initialize-ClaudeConfig.ps1`, `gateway.py`, `sync-gateway-key.ps1`) and old credential-bearing copies. `Initialize-ClaudeConfig.ps1` is the destructive v1 (wholesale overwrite, BOM, placeholder URL). | Always use `Enable-Claude3P.ps1`. |
| **Run with `-Apply` before auditing** | You skip the chance to see what would change. | Run a bare dry run first (no flags), then `-Interactive`. |
| **Edit the config files manually after running** | The script is idempotent and check-and-fill; manual edits can desync `deploymentMode`/`configLibrary`/`_meta.json`/`settings.json` from each other. | Re-run the script with the new key/URL  -  it updates all locations atomically. |
| **Use `-SkipProbe` casually** | You write a key/URL that was never validated. A typo'd URL or dead key silently breaks Claude Desktop at launch. | Let the probe run. Only use `-SkipProbe` if a firewall blocks it or you have a private endpoint you've tested manually. |
| **Use `-NoSyncCli` when you want the CLI in 3P too** | The CLI keeps pointing at Anthropic (or wherever it was)  -  the Code tab inside Desktop won't use the gateway. | Omit `-NoSyncCli`. It's opt-*out*, not opt-*in*. |
| **Run while Claude Desktop is open** (without `-Force`) | The script warns and refuses; forcing writes while the app holds file handles can produce partial writes. | Quit Claude Desktop first. If you must force, the `.bak` files let you recover. |
| **Use `-MachineEnv` without admin** | The HKLM write fails partway  -  the user-level env var is set but the machine-wide one isn't, leaving an inconsistent state. | Run from an elevated shell, or omit `-MachineEnv`. |
| **Use `-ScrubEnv` blindly with other providers** | It's multi-provider safe by design (only removes LLM-Kita-host-matching or empty values), but **audit first** with a dry run to see exactly what it'll touch. | Run `.\Enable-Claude3P.ps1` (no `-Apply`) with `-ScrubEnv` to audit, then `-Apply`. |
| **Pass a key containing quotes or control chars** | The regex-based field writers don't JSON-encode. The script's own callers pass keys/URLs (no raw `"`), so this is safe in practice  -  but a hand-edited key with a `"` would produce invalid JSON. | Use the key exactly as LLM-Kita issued it. |
| **Expect `-Restore` to fix a corrupt install** | Restore is a clean inverse of *what this script did*. If your config is corrupt from manual edits, Restore may not know what to undo. | Restore from the `.bak` files, or do a clean reset (Restore → re-Apply). |
| **Pass `-Models` with a `name` the gateway doesn't serve** | `name` is the wire model id sent in every API request  -  load-bearing. A typo or a model the gateway doesn't route silently breaks inference at launch. `labelOverride` is UI-only and safe to set to anything. | Confirm the `name` values against the gateway's model list first. The `-Interactive` summary warns (non-blocking) if a `name` isn't a recognized Claude id. |

---

## 9. Troubleshooting

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success, dry-run completion, or "nothing to do" (e.g. Restore on an already-stock install). |
| `1` | No Claude-3p install found, or no key supplied and none found on disk. |
| `2` | Gateway probe failed  -  neither failover endpoint was healthy for the supplied key. |
| `3` | `settings.json` parse error  -  the file is invalid JSON before or after a write. Inspect the `.bak`. |
| `4` | `claude_desktop_config.json` / configLibrary re-parse failure after a write. Inspect the `.bak`. |
| `5` | Aborted  -  user answered `N` at a confirm, or a non-interactive session without `-Force`. |
| `6` | `.claude.json` parse error  -  the CLI state file is invalid JSON before or after a write. Inspect the `.bak`. |
| `7` | `-Models` validation failed  -  bad JSON, not an array, or an entry missing `name` or `labelOverride`. |

### "Claude Desktop still hits Anthropic after running"

1. Run a dry run: `.\Enable-Claude3P.ps1`  -  check the `deploymentMode` row says `3p`.
2. If it says `3p`, the app may be caching. Quit fully (check Task Manager), then
   run `.\Enable-Claude3P.ps1 -Apply -ResetCaches -Force`, then relaunch.
3. If `deploymentMode` is blank, re-run `-Apply -NewKey "<KEY>"`  -  the script's
   `Ensure-DesktopDeploymentMode` helper inserts it.

### "The CLI Code tab doesn't use the gateway"

You likely ran with `-NoSyncCli`. Re-run without it:
`.\Enable-Claude3P.ps1 -Interactive -NewKey "<KEY>"`.

### "Git Bash warning at apply time"

The script couldn't find Git for Windows. Install it
(`winget install Git.Git`), or ignore the warning  -  the CLI works via the
PowerShell tool regardless, but `Bash(git ...)` allow entries won't function until
Git is installed.

### Backups

Every write produces a `.bak` next to the original (e.g.
`settings.json.bak`, `claude_desktop_config.json.bak`). To recover, quit Claude,
copy the `.bak` over the live file, and relaunch.

---

## 10. Undoing it (Restore)

```bash
.\Enable-Claude3P.ps1 -Restore -Apply -Force
```

Restore is a **true factory-reset** of what this script did:

- Removes `deploymentMode` from `claude_desktop_config.json` (preserves MCP config).
- Deletes the `configLibrary` gateway entry, zeros `_meta.json`.
- Strips `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` from
  `settings.json` (preserves everything else).
- Removes the onboarding bools it seeded in `.claude.json`  -  but **only if it
  seeded them**. A sentinel field (`_enableClaude3pSeededOnboarding`) marks
  script-seeded bools vs. app/user-seeded ones, so if you completed Claude's
  stock onboarding *before* running 3P, your onboarding state is left intact.

After Restore, Claude Desktop + CLI are back on the default Anthropic endpoint.

---

## 11. For developers / maintainers

- **Audit & architecture details:** see `SUMMARY.md`  -  full audit findings table
  (14 findings, all resolved), helper-function reference, and test coverage.
- **Tests:** `test-helpers.ps1` (156 assertions, all functions + Restore logic)
  and `validate-template.ps1` (AST-based template validation).
  ```bash
  powershell -ExecutionPolicy Bypass -File .\validate-template.ps1
  powershell -ExecutionPolicy Bypass -File .\test-helpers.ps1
  ```
- **The main script self-executes on dot-source** (it has a `param()` block +
  top-level logic, not a pure library). The test harness inlines copies of the
  helpers rather than dot-sourcing.
- **All JSON writes are no-BOM UTF-8** via `[System.IO.File]::WriteAllText` with
  `UTF8Encoding($false)`.

---

## 12. Tested scenarios

The script has been verified against these states (full list in `SUMMARY.md`):

- Truly pristine winget install (no dirs, no files).
- Pristine MSIX/Store install (Packages\Claude_* enumeration).
- Pristine "app launched once then quit".
- Idempotent re-run with the same key (no `.bak` stacking).
- Key rotation across all locations.
- Existing stock Claude applying 3P (`.claude.json` state preserved).
- `-ScrubEnv` with non-LLM-Kita values (host-matching preserves them).
- `-Restore` on an already-stock install (clean no-op).
