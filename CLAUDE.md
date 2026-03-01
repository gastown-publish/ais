# ais — AI Session Orchestrator

Scriptable multi-provider AI agent session manager for orchestrating Claude Code
and Kimi Code sessions via tmux. Designed to be operated by both humans and AI
agents.

## Project Structure

```
bin/
  ais               Main CLI — session lifecycle management
  kimi-account      Kimi multi-account manager (add, login, check, run)
scripts/
  check-credit.sh   Check Claude Code credit usage across accounts
  check-kimi-credit.sh  Check Kimi account status and auth validity
skills/
  ais-orchestrator/
    SKILL.md        OpenClaw skill for multi-agent orchestration
docs/
  agent-setup.md    Setup guides: Claude Code, Kimi Code, OpenClaw, ais
  tmux-agent-control.md  Low-level tmux patterns and recipes
AGENTS.md           Agent workflow rules (beads, Landing the Plane)
CONTRIBUTING.md     Development guidelines
```

## Key Commands

```bash
# Session lifecycle
ais create <name> -a claude -A cc1              # Create Claude session
ais create <name> -a claude -A cc1 -c "task"   # Create and inject command
ais create <name> -a kimi -A 2                  # Create Kimi session
ais create <name> -a claude -A cc1 --yolo       # Skip permissions prompts

# Session management
ais ls                          # List all managed sessions (type, account, dir, age)
ais inspect <name>              # Capture current output (last 100 lines)
ais inspect <name> -n 200       # Capture last 200 lines
ais inspect <name> --rate-limit # Return exit 1 if rate limit detected
ais inject <name> "text"        # Send text/command to session
ais watch <name>                # Live monitor (auto-refreshes every 3s)
ais watch <name> -i 5           # Live monitor with 5s interval
ais logs <name>                 # Capture full scrollback
ais logs <name> -o file.txt     # Save scrollback to file
ais kill <name>                 # Graceful shutdown (sends /exit, waits, force-kills)
ais kill --all                  # Kill all managed sessions
ais accounts                    # List configured Claude and Kimi accounts
```

## Architecture

### Tmux as Execution Layer

Each agent runs in a detached tmux session. Communication happens via:
- `tmux send-keys` — inject text/commands
- `tmux capture-pane` — read output
- `tmux show-environment` — read/write session metadata

### Session Metadata

Stored as tmux environment variables on each session:
```
AIS_MANAGED=1          # Tag identifying ais-managed sessions
AIS_AGENT=claude|kimi  # Agent type
AIS_ACCOUNT=cc1        # Account name/number used
AIS_DIR=/path/to/dir   # Working directory at creation
AIS_CREATED=<epoch>    # Unix timestamp of creation
```

### Account Isolation

Each account runs with its own config directory passed as env var:
- Claude Code: `CLAUDE_CONFIG_DIR=~/.claude-accounts/<name>/`
- Kimi Code: `KIMI_SHARE_DIR=~/.kimi-accounts/<number>/`

This prevents credential and session bleed between accounts.

### Key Constants (`bin/ais`)

```bash
CLAUDE_BIN=~/.local/bin/claude
KIMI_BIN=~/.local/bin/kimi
CLAUDE_ACCOUNTS_DIR=~/.claude-accounts
KIMI_ACCOUNTS_DIR=~/.kimi-accounts
DEFAULT_WIDTH=160
DEFAULT_HEIGHT=50
CLAUDE_LOAD_TIME=14     # seconds to wait for Claude to be ready
KIMI_LOAD_TIME=8        # seconds to wait for Kimi to be ready
RATE_LIMIT_PATTERN='rate.?limit|429|overloaded|quota.?exceeded|too many requests|credit balance is too low|insufficient_quota|hit your limit'
```

### UTF-8 Sanitization

Always sanitize tmux output before processing — ANSI escape codes and
non-printable characters cause silent parse failures:
```bash
sanitize_utf8() {
  LC_ALL=C sed 's/[^[:print:][:space:]]//g' | iconv -f utf-8 -t utf-8 -c 2>/dev/null || cat
}
```
This function is defined in `bin/ais` and used in all capture operations.

## Account Conventions

### Claude Code Accounts

Directory: `~/.claude-accounts/<name>/`

Each account directory contains:
```
settings.json       # Permissions, plugins, MCP config
credentials.json    # Auth tokens (managed by Claude Code)
projects/           # Project history
```

Known accounts: `cc1`, `cc2`, `cc3`, `hataricc`, `nicxxx` (see `docs/agent-setup.md`)

### Kimi Code Accounts

Directory: `~/.kimi-accounts/<number>/`

Auth type determines structure:
```
# API key accounts
config.toml                    # Contains sk-kimi-* key inline

# OAuth accounts
config.toml                    # OAuth provider config
credentials/kimi-code.json     # OAuth tokens (JWT)
```

Use `kimi-account` to manage accounts:
```bash
kimi-account add <name>           # Add API key account
kimi-account login <name>         # OAuth login
kimi-account setup                # Bulk-add from stdin (one key/line)
kimi-account list                 # Show all accounts with auth type
kimi-account check                # Test all accounts (working/rate-limited/auth-error)
kimi-account run <name>           # Launch Kimi with account
```

## Development Rules

- **POSIX-compatible shell** — Bash 4.0+ features are acceptable; avoid bashisms not
  supported in bash 4. Use `set -uo pipefail` at top of all scripts.
- **No hardcoded account paths** — Always use `~/.claude-accounts/` and
  `~/.kimi-accounts/` conventions. Never embed specific paths.
- **ShellCheck must pass** — CI runs shellcheck on all files in `bin/` and
  `scripts/`. Fix all warnings before committing.
- **Test against both agents** — Changes to session create/inspect/inject/kill
  must be verified for both Claude Code and Kimi Code.
- **Error helpers** — Use `die()`, `warn()`, `info()` from `bin/ais`. Never
  use `echo` directly for errors.
- **2-space indentation** — Consistent throughout all shell scripts.

## CI/CD

GitHub Actions runs ShellCheck on push/PR to main:
```yaml
# .github/workflows/ci.yml
- shellcheck bin/*
- shellcheck scripts/*
```

Fix all ShellCheck issues locally before pushing:
```bash
shellcheck bin/ais bin/kimi-account scripts/*.sh
```

## Issue Tracking

This project uses **bd (beads)** for ALL issue tracking. Do NOT use markdown
TODO lists.

```bash
bd ready                     # Find available work
bd show <id>                 # View issue details
bd create "title" -t bug|feature|task|epic|chore -p 0-4   # Create issue
bd update <id> --status in_progress   # Claim work
bd close <id> --reason "Done"         # Complete work
bd sync                      # Sync with git
```

**Priority scale:** 0=critical, 1=high, 2=medium (default), 3=low, 4=backlog

**Always use `--json`** flag for programmatic/agent use.

See `AGENTS.md` for the full beads workflow reference.

## Landing the Plane (Session Completion)

When ending any work session, complete ALL steps. Work is NOT done until
`git push` succeeds.

1. **File issues** for remaining work — create beads issues for anything unfinished
2. **Run quality gates** — `shellcheck bin/* scripts/*`, any tests
3. **Update issue status** — close finished, update in-progress
4. **Push to remote:**
   ```bash
   git pull --rebase
   bd sync
   git push
   git status   # must show "up to date with origin"
   ```
5. **Verify** — all changes committed AND pushed
6. **Hand off** — summarize context for next session

**Never** stop before pushing. **Never** say "ready to push" — you must push.

## Rate Limit Handling

Detect via `ais inspect <name> --rate-limit` (returns exit 1) or by matching
`$RATE_LIMIT_PATTERN` against captured output. Recovery: rotate to a different
account by killing the session and recreating it with a new `-A <account>`.

See `skills/ais-orchestrator/SKILL.md` for the full account rotation playbook.

## Timing Reference

| Event                        | Wait time |
|------------------------------|-----------|
| Claude Code startup          | 14 s      |
| Kimi Code startup            | 8 s       |
| After sending command        | 2–5 s     |
| After `/usage` slash command | 5–8 s     |
| Graceful kill timeout        | 10 s      |

## Key Documentation

| File | Purpose |
|------|---------|
| `docs/tmux-agent-control.md` | Complete tmux patterns, recipes, safety rules |
| `docs/agent-setup.md`        | Setup guide for Claude, Kimi, OpenClaw, ais   |
| `skills/ais-orchestrator/SKILL.md` | Multi-agent orchestration playbook       |
| `AGENTS.md`                  | Beads workflow and Landing the Plane protocol  |
| `CONTRIBUTING.md`            | PR process and code standards                  |
