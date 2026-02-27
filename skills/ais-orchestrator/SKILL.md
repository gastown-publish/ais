---
name: ais-orchestrator
description: "Orchestrate many Claude Code and Kimi Code sub-agents in parallel via tmux. Use when: decomposing large tasks into parallel work, managing multiple coding agents, monitoring agent health, rotating accounts on rate limits. Requires: ais CLI (~/.local/bin/ais), tmux, kimi-account (~/.local/bin/kimi-account)."
metadata:
  { "openclaw": { "emoji": "🕸️", "os": ["linux", "darwin"], "requires": { "bins": ["ais", "tmux"] } } }
---

# AI Session Orchestrator

Manage a fleet of Claude Code and Kimi Code sub-agents running in parallel tmux sessions. Each agent gets its own account, working directory, and task. You monitor them, detect failures, rotate accounts on rate limits, and collect results.

## Prerequisites

- `ais` CLI installed at `~/.local/bin/ais`
- `kimi-account` CLI installed at `~/.local/bin/kimi-account`
- tmux installed
- Claude Code accounts configured in `~/.claude-accounts/`
- Kimi Code accounts configured in `~/.kimi-accounts/`

## Account Inventory

Check what's available before spawning agents:

```bash
ais accounts
```

### Claude Code Accounts

| Account | Model | Best For |
|---------|-------|----------|
| `cc1` | Sonnet | Fast tasks, polecat workers |
| `cc2` | Sonnet | Fast tasks, parallel workers |
| `cc3` | Opus | Complex reasoning, planning |
| `hataricc` | Opus | Complex tasks, fallback |
| `nicxxx` | Opus | Complex tasks, fallback |

**Env var:** `CLAUDE_CONFIG_DIR=~/.claude-accounts/<name>`

### Kimi Code Accounts

Run `kimi-account list` to see all. Kimi is **free** (no credit cost) but has rate limits.

| Account | Auth | Best For |
|---------|------|----------|
| `1` | OAuth | Interactive, browser-login |
| `2` | API key | Servers, headless agents |
| `3+` | Varies | Add more with `kimi-account add <key>` |

**Env var:** `KIMI_SHARE_DIR=~/.kimi-accounts/<number>`

---

## Core Workflow

### Step 1: Decompose the Task

Break the user's request into independent subtasks that can run in parallel. Each subtask should:
- Be self-contained (no dependency on other subtasks)
- Have a clear, specific objective
- Target a specific directory or set of files
- Be completable in one session

**Example decomposition:**
```
User: "Fix all failing tests and add missing error handling across the backend"

Subtasks:
1. Fix order-service tests         → agent: claude/cc1, dir: services/order-service/
2. Fix product-service tests       → agent: claude/cc2, dir: services/product-service/
3. Fix payment-service tests       → agent: kimi/1,     dir: services/payment-service/
4. Add error handling to auth      → agent: claude/cc3, dir: services/auth-service/
5. Add error handling to shipping  → agent: kimi/2,     dir: services/shipping-service/
```

### Step 2: Spawn Sub-Agents

Use `ais create` for each subtask. Spread across accounts to avoid rate limits.

```bash
# Claude Code agents (use --yolo for auto-approve)
ais create fix-orders -a claude -A cc1 --yolo -d ~/project/services/order-service \
  -c "Fix all failing tests. Run pytest and fix until all pass."

ais create fix-products -a claude -A cc2 --yolo -d ~/project/services/product-service \
  -c "Fix all failing tests. Run pytest and fix until all pass."

# Kimi Code agents (--yolo built in)
ais create fix-payments -a kimi -A 1 --yolo -d ~/project/services/payment-service \
  -c "Fix all failing tests. Run pytest and fix until all pass."

ais create add-auth-errors -a claude -A cc3 --yolo -d ~/project/services/auth-service \
  -c "Add proper error handling to all Lambda handlers. Use villa_common.exceptions."

ais create add-ship-errors -a kimi -A 2 --yolo -d ~/project/services/shipping-service \
  -c "Add proper error handling to all Lambda handlers."
```

### Step 3: Monitor All Agents

```bash
# List all running agents
ais ls

# Quick health check on all
for name in fix-orders fix-products fix-payments add-auth-errors add-ship-errors; do
  echo "=== $name ==="
  ais inspect "$name" -n 10 --rate-limit 2>/dev/null || echo "[dead]"
  echo ""
done
```

### Step 4: Detect and Recover from Problems

```bash
# Check for rate limits
ais inspect fix-orders --rate-limit

# If rate limited, kill and respawn with different account
ais kill fix-orders
ais create fix-orders -a claude -A cc3 --yolo -d ~/project/services/order-service \
  -c "Fix all failing tests. Run pytest and fix until all pass."
```

### Step 5: Collect Results

```bash
# Capture final output from each agent
ais inspect fix-orders -n 100 > /tmp/results-orders.txt
ais inspect fix-products -n 100 > /tmp/results-products.txt

# Save full scrollback logs
ais logs fix-orders -o /tmp/fix-orders-full.log
ais logs fix-products -o /tmp/fix-products-full.log
```

### Step 6: Clean Up

```bash
# Kill all managed sessions
ais kill --all

# Or kill individually with log save
ais kill fix-orders --save
ais kill fix-products --save
```

---

## Problem Detection & Recovery Playbook

### Rate Limit Detected

**Detection:** `ais inspect <name> --rate-limit` prints `*** RATE LIMIT DETECTED ***`

**Recovery:**
1. Note which account is rate-limited
2. Kill the session: `ais kill <name>`
3. Pick a different account from the same agent type
4. Respawn: `ais create <name> -a <agent> -A <new-account> ...`

**Account rotation order:**
- Claude: cc1 → cc2 → cc3 → hataricc → nicxxx → cc1
- Kimi: 1 → 2 → 3 → ... → 1

```bash
# Example rotation
ais kill worker1
ais create worker1 -a claude -A cc2 --yolo -d ~/project -c "continue the previous task"
```

### Agent Crashed / Session Dead

**Detection:** `ais ls` doesn't show the session, or `ais inspect <name>` returns error

**Recovery:**
1. Check if session exists: `tmux has-session -t <name> 2>/dev/null && echo alive || echo dead`
2. If dead, respawn with same account: `ais create <name> -a <agent> -A <account> ...`
3. If the crash was due to a bug in the task, adjust the prompt

### Agent Stuck / Idle

**Detection:** `ais inspect <name> -n 20` shows no recent activity, or shows a prompt waiting for input

**Recovery:**
1. Try sending Enter to unstick: `ais inject <name> ""`
2. If waiting for a yes/no prompt: `ais inject <name> "y"`
3. If truly stuck, kill and respawn with a clearer prompt

### Authentication Error

**Detection:** Output contains `unauthorized`, `401`, `403`, `invalid key`, `token expired`

**Recovery for Claude:** Re-login the account (`CLAUDE_CONFIG_DIR=~/.claude-accounts/<name> claude /login`)
**Recovery for Kimi API key:** Key is permanent, shouldn't expire. Check config.
**Recovery for Kimi OAuth:** Re-login: `kimi-account login <number>`

### Connection Error

**Detection:** Output contains `ECONNREFUSED`, `timeout`, `network error`, `connection reset`

**Recovery:**
1. Wait 30 seconds, check again
2. If persistent, kill and respawn (network issue may have resolved)
3. If all agents have connection errors, it's likely a network or service outage — wait and retry

---

## Monitoring Patrol Loop

For long-running orchestration, run a patrol loop:

```bash
#!/bin/bash
# patrol.sh — monitor all ais agents every 2 minutes
INTERVAL=120
RATE_LIMIT_PATTERN='rate.?limit|429|overloaded|quota.?exceeded|too many requests|credit balance is too low|insufficient_quota|hit your limit'

while true; do
  echo "=== Patrol $(date +%H:%M:%S) ==="

  for sess in $(ais ls 2>/dev/null | tail -n +3 | awk '{print $1}'); do
    [ -z "$sess" ] && continue

    # Check if alive
    if ! tmux has-session -t "$sess" 2>/dev/null; then
      echo "  $sess: DEAD"
      continue
    fi

    # Check for rate limits
    output=$(ais inspect "$sess" -n 50 2>/dev/null)
    if echo "$output" | grep -qiE "$RATE_LIMIT_PATTERN"; then
      echo "  $sess: RATE LIMITED — needs account rotation"
    else
      # Show last meaningful line
      last_line=$(echo "$output" | grep -v '^$' | tail -1)
      echo "  $sess: alive — $last_line"
    fi
  done

  echo ""
  sleep "$INTERVAL"
done
```

---

## Agent Prompt Templates

### Claude Code Sub-Agent Prompt

When spawning Claude Code agents, inject a prompt that:
1. States the specific task clearly
2. Sets boundaries (which files/dirs to touch)
3. Requests a summary when done

```
Fix all failing tests in this service directory.

Steps:
1. Run: python3 -m pytest tests/ -v
2. Read failing test output carefully
3. Fix the code (not the tests) to make them pass
4. Re-run tests to confirm all pass
5. When done, print: TASK COMPLETE: <number of tests fixed>

Do NOT modify files outside this directory.
```

### Kimi Code Sub-Agent Prompt

Kimi works similarly but has different strengths (free, good at code generation):

```
Add comprehensive error handling to all Lambda handlers in this service.

For each handler:
1. Wrap the main logic in try/except
2. Use villa_common.exceptions (ValidationError, NotFoundError)
3. Return proper HTTP status codes using villa_common.response helpers
4. Log errors with the Lambda context request_id

When done, print: TASK COMPLETE: <number of handlers updated>
```

---

## Capacity Planning

| Agent Type | Max Concurrent | Notes |
|-----------|---------------|-------|
| Claude Code (Opus) | 3 | cc3, hataricc, nicxxx — shared rate limit pool |
| Claude Code (Sonnet) | 2 | cc1, cc2 — faster but less capable |
| Kimi Code | 2+ | Free, add more with `kimi-account add <key>` |
| **Total** | ~7 | Mix Claude + Kimi for maximum parallelism |

**Strategy:** Use Kimi for simpler tasks (test fixing, boilerplate, error handling). Use Claude Opus for complex tasks (architecture, debugging, multi-file refactors). Use Claude Sonnet for medium tasks.

---

## Quick Reference

```bash
# === LIFECYCLE ===
ais create <name> -a claude|kimi -A <account> [--yolo] [-c "cmd"] [-d dir]
ais ls                              # list all sessions
ais kill <name>                     # graceful shutdown
ais kill --all                      # kill everything

# === MONITORING ===
ais inspect <name> -n 100           # capture last 100 lines
ais inspect <name> --rate-limit     # check for rate limits
ais watch <name> -i 5               # live tail (every 5s)
ais logs <name> -o file.log         # save full scrollback

# === INTERACTION ===
ais inject <name> "do the thing"    # send command
ais inject <name> "y"               # answer a prompt

# === ACCOUNTS ===
ais accounts                        # list all accounts
kimi-account list                   # list kimi accounts
kimi-account check                  # test all kimi accounts
kimi-account add sk-kimi-XXX        # add new kimi account
```

---

## Rules

1. **Always check `ais accounts` before spawning** — know what's available
2. **Spread across accounts** — don't put 5 agents on the same account
3. **Monitor regularly** — check every 2-5 minutes for problems
4. **Rotate on rate limit** — don't wait, immediately kill and respawn with different account
5. **Use Kimi for simple tasks** — it's free, save Claude credits for hard problems
6. **Save logs before killing** — `ais kill <name> --save` preserves evidence
7. **Never send Ctrl-C** — always use `ais kill` for graceful shutdown
8. **Keep the user informed** — report what's running, what finished, what failed
