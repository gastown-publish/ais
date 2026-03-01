# ais Improvement Checklist

Full audit of the codebase conducted 2026-03-01. 10 issues filed in `.beads/issues.jsonl`.
Items are grouped by issue ID and ordered by priority. Check off items as they are fixed.

**Summary:** 10 issues · 2 critical · 3 high · 4 medium · 1 low · 34 sub-items

---

## ais-1 — CRITICAL: Command injection & race conditions
**Priority:** 0 (critical) · **Type:** bug · **Files:** `bin/ais`, `bin/kimi-account`, `scripts/check-kimi-credit.sh`

### Acceptance criteria
All extra arguments are passed to tmux as literal strings (not shell-interpolated).
Config file generation escapes special characters. No path or key value can break
out of its intended context.

### Checklist
- [ ] **bin/ais `cmd_create()`** — extra args collected via `--` (lines ~131–136) are
  interpolated directly into a shell string passed to `tmux send-keys`. Replace
  string interpolation with array-based `tmux send-keys` that quotes each arg
  individually, so shell metacharacters (`;`, `|`, `$()`, backticks) are treated as literals.
- [ ] **bin/ais** — background command injection (lines ~220–231): after `sleep` +
  `tmux has-session` check, the script continues regardless of whether the session
  is still responsive. Add a post-injection verification step (e.g. capture pane and
  confirm the command appeared) and log an error if the session died mid-injection.
- [ ] **bin/kimi-account `cmd_add()`** — API key is embedded in a heredoc TOML string
  (line ~88) without escaping. A key containing `"` or `\` breaks TOML syntax.
  Escape or quote the key value before inserting: at minimum, verify the key
  matches `^sk-kimi-[A-Za-z0-9_-]+$` and reject keys with special chars.
- [ ] **scripts/check-kimi-credit.sh** — `$cred_file` is embedded unescaped inside
  an inline `python3 -c "..."` string (lines ~97–128). A path containing `"` or `\`
  breaks the Python string literal. Pass the path via environment variable instead:
  `CRED_FILE="$cred_file" python3 -c "import os; f=os.environ['CRED_FILE']; ..."`.

---

## ais-2 — CRITICAL: Hardcoded session name & missing output sanitization
**Priority:** 0 (critical) · **Type:** bug · **Files:** `scripts/check-credit.sh`, `scripts/check-kimi-credit.sh`

### Acceptance criteria
Concurrent runs of check-credit.sh do not interfere with each other. All tmux
capture-pane output is sanitized before any grep/sed pattern matching.

### Checklist
- [ ] **scripts/check-credit.sh line ~14** — `TMUX_SESSION="credit-check-tmp"` is a fixed
  string. Two simultaneous runs (e.g. in CI, or two terminal windows) attach to the same
  session and mix output. Change to: `TMUX_SESSION="credit-check-$$-${RANDOM}"`.
  Ensure the cleanup trap at the end uses the same variable.
- [ ] **scripts/check-credit.sh** — every `tmux capture-pane -p` call (lines ~110, ~150,
  ~157, ~161, ~165, etc.) sends raw tmux output (with ANSI escape codes) directly
  into `grep`. Add `sanitize_utf8()` pipe after every capture:
  `tmux capture-pane -p ... | LC_ALL=C sed 's/[^[:print:][:space:]]//g'`.
- [ ] **scripts/check-kimi-credit.sh** — same issue: `tmux capture-pane` calls (lines
  ~74, ~141) used in `test_result` are not sanitized. Apply the same fix.
- [ ] Verify: run both scripts twice simultaneously in separate shells against the same
  account and confirm output does not mix between the two processes.

---

## ais-3 — HIGH: Missing input validation across CLI
**Priority:** 1 (high) · **Type:** bug · **Files:** `bin/ais`, `bin/kimi-account`

### Acceptance criteria
Invalid flag values produce a clear error message and exit 1. Binary paths resolve
correctly regardless of how `~` is handled. Account names are checked for safety.

### Checklist
- [ ] **bin/ais `-n`/`--lines` flag** (line ~316) — add numeric validation before use:
  ```bash
  [[ "$lines" =~ ^[0-9]+$ ]] || die "--lines requires a positive integer, got: $lines"
  ```
- [ ] **bin/ais `-i`/`--interval` flag** (lines ~396–397) — same pattern:
  ```bash
  [[ "$interval" =~ ^[0-9]+$ ]] || die "--interval requires a positive integer, got: $interval"
  ```
- [ ] **bin/ais `--size` flag** (line ~145) — validate format before splitting:
  ```bash
  [[ "$2" =~ ^[0-9]+x[0-9]+$ ]] || die "--size must be WxH (e.g. 160x50), got: $2"
  ```
- [ ] **bin/ais constants** (lines ~22–23) — `CLAUDE_BIN=~/.local/bin/claude` and
  `KIMI_BIN=~/.local/bin/kimi`: tilde is not expanded in assignment context.
  Replace with `CLAUDE_BIN="${HOME}/.local/bin/claude"` and same for `KIMI_BIN`.
- [ ] **bin/kimi-account `cmd_run()`** (line ~262) — account argument used as directory
  component without validation. Add:
  ```bash
  [[ "$acct" =~ ^[a-zA-Z0-9_-]+$ ]] || die "invalid account name: $acct"
  ```

---

## ais-4 — HIGH: Portability failures and fragile parsing in check-credit.sh
**Priority:** 1 (high) · **Type:** bug · **Files:** `scripts/check-credit.sh`

### Acceptance criteria
Script produces a clear error on non-Linux systems. Parsing failures emit a warning
rather than silently returning `?`. Script does not block indefinitely.

### Checklist
- [ ] **GNU `date -d` portability** — add an OS check near the top:
  ```bash
  if ! date --version 2>/dev/null | grep -q GNU; then
    die "check-credit.sh requires GNU coreutils date (Linux only). On macOS, install: brew install coreutils"
  fi
  ```
- [ ] **Credit percentage grep patterns** (lines ~157, ~161, ~165) — add a fallback and
  warning when `grep -oP` returns nothing:
  ```bash
  week_all=$(... | grep -oP '\d+(?=% used)' | head -1)
  [[ -z "$week_all" ]] && { warn "could not parse week_all for $account — output format may have changed"; week_all="?"; }
  ```
  Apply the same guard to all three percentage fields.
- [ ] **No overall timeout on wait loop** (line ~108) — the retry loop can run 60+ seconds
  if Claude hangs. Wrap with a watchdog using `SECONDS`:
  ```bash
  DEADLINE=$(( SECONDS + 90 ))
  while ...; do
    [[ $SECONDS -gt $DEADLINE ]] && { warn "timed out waiting for $account"; break; }
    ...
  done
  ```
- [ ] **Inconsistent `CLAUDE_BIN` path** (line ~12) — change `~/.npm/bin/claude` to
  `"${HOME}/.local/bin/claude"` to match the path used in `bin/ais`.
- [ ] **Hardcoded ACCOUNTS array** (line ~22) — replace with auto-discovery:
  ```bash
  mapfile -t ACCOUNTS < <(find "${HOME}/.claude-accounts" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort)
  [[ ${#ACCOUNTS[@]} -eq 0 ]] && die "no accounts found in ~/.claude-accounts/"
  ```

---

## ais-5 — HIGH: Missing CLI features for scripting and daily workflows
**Priority:** 1 (high) · **Type:** feature · **Files:** `bin/ais`

### Acceptance criteria
`ais ls --json` outputs valid JSON array. `ais status` returns a single state token.
`ais rotate` performs kill + recreate atomically. `ais ls --health` pings each session.

### Checklist
- [ ] **`--json` flag for `ais ls`** — add `-j`/`--json` option that outputs a JSON array
  where each element has keys: `name`, `agent`, `account`, `dir`, `age_seconds`, `created`.
  Use `printf '{"name":"%s",...}\n'` construction; one object per line (JSONL) is acceptable.
- [ ] **`--json` flag for `ais accounts`** — add `-j`/`--json` option outputting arrays of
  `{"name":"cc1","type":"claude","dir":"..."}` and `{"name":"1","type":"kimi","auth":"api_key"}`.
- [ ] **`ais status <name>` subcommand** — new command that inspects a session and returns
  one of: `running` (prompt visible), `working` (command in progress), `idle` (prompt, no
  recent output), `rate_limited` (rate limit pattern matched), `dead` (session not found).
  Exits 0 for running/working/idle, 1 for rate_limited, 2 for dead.
- [ ] **`ais rotate <name> -A <account>` subcommand** — automates rate-limit recovery:
  saves scrollback log, kills the session, recreates it on the new account in the same
  directory. Accepts the same flags as `ais create` (-c for initial command, --yolo, etc.).
- [ ] **`ais ls --health`** — adds a `STATUS` column to `ais ls` output by doing a quick
  `tmux has-session` + `is_prompt_visible` check per session. Flag is optional; omitting
  it keeps current fast behavior (no per-session pane reads).

---

## ais-6 — MEDIUM: DRY violations — account management and rate-limit detection
**Priority:** 2 (medium) · **Type:** task · **Files:** `bin/ais`, `bin/kimi-account`, `scripts/check-kimi-credit.sh`

### Acceptance criteria
Account listing logic exists in one place and is sourced by all consumers. Rate-limit
detection is a single shared function. Load-time constants respect env var overrides.

### Checklist
- [ ] **Extract account discovery to `bin/ais-lib.sh`** (or inline shared functions via
  source) — define `list_claude_accounts()` and `list_kimi_accounts()` once; have
  `bin/ais cmd_accounts()`, `bin/kimi-account cmd_list()`, and
  `scripts/check-kimi-credit.sh` all source and call these. Ensures consistent
  error messages and glob patterns.
- [ ] **Extract `check_rate_limit()`** — define once (e.g. in `bin/ais-lib.sh`):
  ```bash
  check_rate_limit() { echo "$1" | grep -qiE "$RATE_LIMIT_PATTERN"; }
  ```
  Replace the four current inline grep calls in `cmd_inspect()`, `cmd_watch()`,
  `kimi-account cmd_check()`, and `check-kimi-credit.sh`.
- [ ] **Extract `test_kimi_account()`** — the `timeout 20 "$KIMI_BIN" -c "Say just the word 'ok'"` pattern appears in both `bin/kimi-account` and `scripts/check-kimi-credit.sh`.
  Define once as a shared function (accepting account dir as arg) and call from both.
- [ ] **`CLAUDE_LOAD_TIME` / `KIMI_LOAD_TIME` env var overrides** — change hardcoded
  constants throughout all scripts to:
  ```bash
  CLAUDE_LOAD_TIME="${CLAUDE_LOAD_TIME:-14}"
  KIMI_LOAD_TIME="${KIMI_LOAD_TIME:-8}"
  ```
  Also apply to `KIMI_CHECK_TIMEOUT` (currently `20` in two scripts).

---

## ais-7 — MEDIUM: Code quality and error handling inconsistencies
**Priority:** 2 (medium) · **Type:** task · **Files:** `bin/kimi-account`, `scripts/check-kimi-credit.sh`

### Acceptance criteria
`bin/kimi-account` uses `die()`/`warn()` consistently. No silent failures. JWT padding
is calculated correctly. OAuth credentials are validated after creation.

### Checklist
- [ ] **`bin/kimi-account` error output** — replace all `echo "Error: ..."` and
  `echo "  Error: ..."` calls with `die "..."` or `warn "..."` (sourcing helpers from
  `bin/ais` or duplicating the minimal definitions). Ensures consistent formatting
  and that fatal errors actually exit.
- [ ] **`bin/kimi-account cmd_setup()` silent skip** (line ~183) — change:
  ```bash
  [[ ! "$line" == sk-* ]] && continue
  ```
  to:
  ```bash
  [[ ! "$line" == sk-* ]] && { warn "skipping invalid line: $line"; continue; }
  ```
- [ ] **`bin/kimi-account cmd_list()` API key grep** (line ~213) — make extraction more
  robust by anchoring to the start of the TOML key:
  `grep '^api_key' config.toml | grep -o 'sk-kimi-[^"]*'`
- [ ] **`bin/kimi-account` OAuth credential validation** (line ~163) — after OAuth login
  succeeds (exit 0 + file exists), validate the file is non-empty valid JSON:
  ```bash
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$cred_file" \
    || die "OAuth credential file is invalid: $cred_file"
  ```
- [ ] **`bin/kimi-account` model hardcoding** — replace `"kimi-for-coding"` in the config
  template with `"${KIMI_MODEL:-kimi-for-coding}"` so users can override without editing
  source.
- [ ] **`check-kimi-credit.sh` JWT padding** (lines ~104, ~122) — replace the incorrect
  padding calculation:
  ```python
  # Wrong:
  payload += '=' * (4 - len(payload) % 4)
  # Correct:
  while len(payload) % 4:
      payload += '='
  ```

---

## ais-8 — MEDIUM: Zero test infrastructure
**Priority:** 2 (medium) · **Type:** chore · **Files:** `tests/`, `.github/workflows/ci.yml`, `.gitignore`

### Acceptance criteria
`bats tests/` passes with at least smoke test coverage of create/inspect/kill.
CI runs `bats tests/` in addition to shellcheck. `.gitignore` covers test artifacts.

### Checklist
- [ ] **Create `tests/` directory** with a `README.md` explaining how to install BATS
  (`npm install -g bats` or `brew install bats-core`) and run the suite (`bats tests/`).
- [ ] **Create `tests/ais-smoke.bats`** — BATS test file covering the core session lifecycle
  using a stub/mock approach (fake tmux or a real session against a no-op script):
  - Test: `ais create` exits 0 and session appears in `ais ls`
  - Test: `ais inspect <name>` exits 0 and returns non-empty output
  - Test: `ais kill <name>` exits 0 and session disappears from `ais ls`
  - Test: `ais create` with invalid agent type exits non-zero
  - Test: `ais inspect` with `--lines abc` exits non-zero with useful message
- [ ] **Create `tests/kimi-account.bats`** — BATS tests for account management using
  fixture config files under `tests/fixtures/`:
  - Test: `kimi-account list` with fixture accounts dir outputs expected format
  - Test: `kimi-account add` with valid key creates config.toml
  - Test: `kimi-account add` with key containing `"` produces an error (injection fix check)
- [ ] **Update `.github/workflows/ci.yml`** — add a `test` job after shellcheck:
  ```yaml
  - name: Install bats
    run: npm install -g bats
  - name: Run tests
    run: bats tests/
  ```
- [ ] **Update `.gitignore`** — add missing patterns:
  ```
  tmp/
  *.log
  .kimi/
  tests/fixtures/tmp/
  ```

---

## ais-9 — MEDIUM: Hardcoded timing constants and terminal compatibility
**Priority:** 2 (medium) · **Type:** task · **Files:** `bin/ais`, `bin/kimi-account`, `scripts/check-credit.sh`, `scripts/check-kimi-credit.sh`

### Acceptance criteria
All timing constants can be overridden via environment variables. Table output
degrades gracefully to ASCII on non-UTF-8 terminals.

### Checklist
- [ ] **`bin/ais` timing constants** — change hardcoded assignments to env-overridable:
  ```bash
  CLAUDE_LOAD_TIME="${CLAUDE_LOAD_TIME:-14}"
  KIMI_LOAD_TIME="${KIMI_LOAD_TIME:-8}"
  ```
  Document these env vars in `CLAUDE.md` under "Key Constants".
- [ ] **`scripts/check-credit.sh` timing constants** — same treatment for `WAIT_LOAD`,
  `WAIT_USAGE`, and any hardcoded `sleep N` values that correspond to agent startup.
- [ ] **`KIMI_CHECK_TIMEOUT`** (hardcoded `20` in `bin/kimi-account` and
  `scripts/check-kimi-credit.sh`) — replace with `"${KIMI_CHECK_TIMEOUT:-20}"`.
- [ ] **Unicode box-drawing characters** — add a terminal capability guard near the top
  of each script that draws tables:
  ```bash
  if [[ "${LANG:-}" =~ UTF-8 ]] && [[ "${TERM:-}" != dumb ]]; then
    H="─" V="│" TL="┌" TR="┐" BL="└" BR="┘" LM="├" RM="┤"
  else
    H="-" V="|" TL="+" TR="+" BL="+" BR="+" LM="+" RM="+"
  fi
  ```
  Apply to `bin/ais`, `bin/kimi-account`, `scripts/check-credit.sh`, `scripts/check-kimi-credit.sh`.

---

## ais-10 — LOW: Documentation gaps
**Priority:** 3 (low) · **Type:** chore · **Files:** `docs/`, `README.md`, `CONTRIBUTING.md`

### Acceptance criteria
A new user can reach their first working session in under 5 minutes using only
`docs/quickstart.md`. Common failure modes are documented with solutions.

### Checklist
- [ ] **Create `docs/quickstart.md`** — sub-5-minute first-session guide:
  1. Install prerequisites (bash 4.0+, tmux 3.0+, Claude/Kimi CLIs)
  2. Configure one account
  3. `ais create hello -a claude -A cc1 -c "say hello"`
  4. `ais watch hello`
  5. `ais kill hello`
- [ ] **Add Troubleshooting section to `docs/agent-setup.md`** — cover:
  - `ais create` fails: binary not found → check `CLAUDE_BIN`/`KIMI_BIN` paths
  - Session starts but immediately exits: auth expired → run `claude` manually to re-auth
  - `ais inspect` returns garbage: ANSI codes → verify `sanitize_utf8` is applied
  - Rate limits hit immediately: account overused → `ais accounts` to find alternatives
  - tmux: session not found → check `AIS_MANAGED` env var, may have been killed externally
- [ ] **Add error recovery recipes to `docs/tmux-agent-control.md`**:
  - Session crashed mid-capture: force-kill and check `ais logs` for last output
  - Agent stopped responding: inject Enter, wait, re-inspect; if still hung, kill/respawn
  - Pane accidentally split: tmux kill-pane to close extra pane, session still running
- [ ] **Add architecture diagram to `README.md`** — ASCII diagram showing:
  orchestrator → ais CLI → tmux sessions → Claude/Kimi agents; include account isolation flow.
- [ ] **Expand `CONTRIBUTING.md`** — add:
  - Testing instructions (install BATS, run `bats tests/`)
  - How to add support for a new agent type (where to add constants, create/kill/detect functions)
  - PR review SLA (target: 3 business days for review)

---

## Quick Reference: Issue → File Map

| Issue | Priority | Files affected |
|-------|----------|---------------|
| ais-1 | CRITICAL | `bin/ais`, `bin/kimi-account`, `scripts/check-kimi-credit.sh` |
| ais-2 | CRITICAL | `scripts/check-credit.sh`, `scripts/check-kimi-credit.sh` |
| ais-3 | HIGH | `bin/ais`, `bin/kimi-account` |
| ais-4 | HIGH | `scripts/check-credit.sh` |
| ais-5 | HIGH | `bin/ais` |
| ais-6 | MEDIUM | `bin/ais`, `bin/kimi-account`, `scripts/check-kimi-credit.sh` |
| ais-7 | MEDIUM | `bin/kimi-account`, `scripts/check-kimi-credit.sh` |
| ais-8 | MEDIUM | `tests/` (new), `.github/workflows/ci.yml`, `.gitignore` |
| ais-9 | MEDIUM | `bin/ais`, `bin/kimi-account`, `scripts/*.sh` |
| ais-10 | LOW | `docs/` (new files), `README.md`, `CONTRIBUTING.md` |

## Test Run Results (2026-03-01)

| Check | Result | Notes |
|-------|--------|-------|
| `shellcheck bin/ais` | Not run locally | shellcheck not installed; CI enforces on push |
| `shellcheck bin/kimi-account` | Not run locally | Same |
| `shellcheck scripts/*.sh` | Not run locally | Same |
| `bats tests/` | N/A | No tests exist yet — tracked in ais-8 |
| `python3 -m json.tool .beads/issues.jsonl` | PASS | All 10 issue records are valid JSON |
