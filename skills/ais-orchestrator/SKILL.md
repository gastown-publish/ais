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

## Prompting Playbook

The quality of your sub-agent prompts determines success or failure. Bad prompts waste credits, produce wrong output, and leave agents stuck. Good prompts finish fast with exactly what you need.

### The 7 Rules of Sub-Agent Prompts

1. **One task, one agent.** Never give an agent two unrelated goals. Split them.
2. **Be specific about what, not how.** Say "fix the failing test in `test_auth.py`" not "look at the tests and see if anything needs fixing."
3. **Name the files.** Agents waste time exploring when you already know the target. Say "edit `src/auth/handler.py`" not "find the auth code."
4. **Set boundaries.** "Only modify files in `services/order/`" prevents agents from wandering into unrelated code.
5. **Define done.** "When done, print `TASK COMPLETE: <summary>`" gives you a machine-detectable completion signal.
6. **Give context, not instructions to find context.** Paste the error message, the test output, the relevant function signature. Don't say "run the tests to see what fails" when you already know.
7. **Match agent to task.** Opus for architecture and debugging. Sonnet for straightforward fixes. Kimi for free boilerplate and simple edits.

### Prompt Structure

Every sub-agent prompt should have these sections in order:

```
[WHAT] One sentence stating the task.

[CONTEXT] The error, the test output, the function signature — whatever the agent needs to understand the problem without exploring first.

[SCOPE] Which files or directories to touch. Which to leave alone.

[DONE] How to signal completion. What to output.

[CONSTRAINTS] Things to avoid. Don't push. Don't modify tests. Don't refactor unrelated code.
```

### Example: Bad vs Good Prompts

**Bad — vague, no context, no boundaries:**
```
Look at the backend and fix any issues you find.
```

**Good — specific, scoped, with context:**
```
Fix the failing test in tests/test_checkout.py::test_apply_discount.

The error is:
  AssertionError: expected 90.0 but got 100.0

The discount logic is in src/checkout/pricing.py, function apply_discount().
Only modify src/checkout/pricing.py. Do not change the test.
When done, run pytest tests/test_checkout.py -v and print TASK COMPLETE: <pass/fail count>.
```

**Bad — asks the agent to explore:**
```
Add error handling to the project.
```

**Good — tells the agent exactly what to do:**
```
Add try/except error handling to these 3 Lambda handlers in src/handlers/:
- create_order.py: handler()
- update_order.py: handler()
- delete_order.py: handler()

Wrap each handler body in try/except. Catch ValidationError and return 400.
Catch Exception and return 500 with the request_id from context.
Use the existing error_response() helper from src/utils/responses.py.
Do NOT modify any other files.
When done, print TASK COMPLETE: <number of handlers updated>.
```

### Prompt Templates by Task Type

#### Test Fixing
```
Fix the failing test: {test_file}::{test_name}

Error output:
{paste error here}

The code under test is in {source_file}.
Fix the source code, not the test.
Run: pytest {test_file}::{test_name} -v
Print TASK COMPLETE when all pass.
```

#### Code Generation
```
Create {file_path} that implements {description}.

Requirements:
- {requirement 1}
- {requirement 2}

Follow the patterns in {example_file} for style and conventions.
Do NOT modify existing files.
Print TASK COMPLETE when the file is written.
```

#### Refactoring
```
Refactor {function_name} in {file_path}.

Current problems:
- {problem 1}
- {problem 2}

Target state:
- {goal 1}
- {goal 2}

Only modify {file_path} and its direct imports.
Run existing tests after: pytest {test_dir} -v
Print TASK COMPLETE: <pass/fail count>.
```

#### Bug Investigation
```
Investigate why {symptom} happens in {area}.

Steps:
1. Read {entry_point_file}
2. Trace the call chain to find where {bad_thing} occurs
3. Fix the root cause
4. Add a test that would have caught this

Only modify files in {directory}.
Print TASK COMPLETE: <root cause summary and fix description>.
```

### Multi-Agent Coordination Patterns

#### Fan-Out: Same Task, Different Targets
When you have the same type of work across multiple directories:

```bash
for svc in order product payment shipping; do
  ais create "fix-${svc}" -a kimi -A $((RANDOM % 3 + 1)) --yolo \
    -d ~/project/services/${svc}-service \
    -c "Fix all failing tests. Run pytest tests/ -v. Fix source code only. Print TASK COMPLETE when all pass."
done
```

#### Pipeline: Sequential Dependencies
When task B depends on task A's output:

```bash
# Phase 1: Generate the interface
ais create gen-interface -a claude -A cc3 --yolo -d ~/project \
  -c "Design and create src/interfaces/payment.ts based on the API spec in docs/payment-api.md. Print TASK COMPLETE when done."

# Wait for phase 1
while ! ais inspect gen-interface -n 20 2>/dev/null | grep -q "TASK COMPLETE"; do sleep 30; done

# Phase 2: Implement using the interface (fan-out)
ais create impl-stripe -a claude -A cc1 --yolo -d ~/project \
  -c "Implement StripePaymentProvider in src/providers/stripe.ts using the interface in src/interfaces/payment.ts."
ais create impl-paypal -a kimi -A 1 --yolo -d ~/project \
  -c "Implement PaypalPaymentProvider in src/providers/paypal.ts using the interface in src/interfaces/payment.ts."
```

#### Specialist Agents
Assign roles based on agent strengths:

```bash
# Opus for architecture decisions
ais create architect -a claude -A cc3 --yolo -d ~/project \
  -c "Review src/api/ and design a caching strategy. Write the plan to CACHING_PLAN.md. Print TASK COMPLETE when done."

# Sonnet for mechanical work
ais create implement -a claude -A cc1 --yolo -d ~/project \
  -c "Implement the caching strategy described in CACHING_PLAN.md. Follow the plan exactly."

# Kimi for tests (free)
ais create test-cache -a kimi -A 1 --yolo -d ~/project \
  -c "Write comprehensive tests for the caching layer in src/cache/. Cover: cache hits, misses, expiry, invalidation. Put tests in tests/test_cache.py."
```

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
  -c "Fix all failing tests. Run pytest and fix until all pass. Print TASK COMPLETE when done."

ais create fix-products -a claude -A cc2 --yolo -d ~/project/services/product-service \
  -c "Fix all failing tests. Run pytest and fix until all pass. Print TASK COMPLETE when done."

# Kimi Code agents (--yolo built in)
ais create fix-payments -a kimi -A 1 --yolo -d ~/project/services/payment-service \
  -c "Fix all failing tests. Run pytest and fix until all pass. Print TASK COMPLETE when done."

ais create add-auth-errors -a claude -A cc3 --yolo -d ~/project/services/auth-service \
  -c "Add proper error handling to all Lambda handlers. Use villa_common.exceptions. Print TASK COMPLETE when done."

ais create add-ship-errors -a kimi -A 2 --yolo -d ~/project/services/shipping-service \
  -c "Add proper error handling to all Lambda handlers. Print TASK COMPLETE when done."
```

### Step 3: Monitor All Agents

```bash
# List all running agents
ais ls

# Quick health check on all
for name in $(ais ls 2>/dev/null | tail -n +3 | awk '{print $1}'); do
  echo "=== $name ==="
  output=$(ais inspect "$name" -n 10 --rate-limit 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "[dead]"
  elif echo "$output" | grep -q "TASK COMPLETE"; then
    echo "[DONE] $(echo "$output" | grep 'TASK COMPLETE')"
  else
    echo "$output" | tail -3
  fi
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
  -c "Fix all failing tests. Run pytest and fix until all pass. Print TASK COMPLETE when done."
```

### Step 5: Collect Results

```bash
# Capture final output from each agent
for name in $(ais ls 2>/dev/null | tail -n +3 | awk '{print $1}'); do
  echo "=== $name ===" >> /tmp/results.txt
  ais inspect "$name" -n 100 >> /tmp/results.txt
  echo "" >> /tmp/results.txt
done

# Save full scrollback logs
ais logs fix-orders -o /tmp/fix-orders-full.log
```

### Step 6: Clean Up

```bash
# Kill all managed sessions
ais kill --all

# Or kill individually with log save
ais kill fix-orders --save
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

### Agent Crashed / Session Dead

**Detection:** `ais ls` doesn't show the session, or `ais inspect <name>` returns error

**Recovery:**
1. Check if session exists: `tmux has-session -t <name> 2>/dev/null && echo alive || echo dead`
2. If dead, respawn with same account: `ais create <name> -a <agent> -A <account> ...`
3. If the crash was due to a bug in the task, rewrite the prompt with more context

### Agent Stuck / Idle

**Detection:** `ais inspect <name> -n 20` shows no recent activity, or shows a prompt waiting for input

**Recovery:**
1. Try sending Enter to unstick: `ais inject <name> ""`
2. If waiting for a yes/no prompt: `ais inject <name> "y"`
3. If truly stuck, kill and respawn with a clearer, more specific prompt

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
3. If all agents have connection errors, it's likely a service outage — wait and retry

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

    if ! tmux has-session -t "$sess" 2>/dev/null; then
      echo "  $sess: DEAD"
      continue
    fi

    output=$(ais inspect "$sess" -n 50 2>/dev/null)
    if echo "$output" | grep -qiE "$RATE_LIMIT_PATTERN"; then
      echo "  $sess: RATE LIMITED — needs account rotation"
    elif echo "$output" | grep -q "TASK COMPLETE"; then
      echo "  $sess: DONE — $(echo "$output" | grep 'TASK COMPLETE' | tail -1)"
    else
      last_line=$(echo "$output" | grep -v '^$' | tail -1)
      echo "  $sess: alive — $last_line"
    fi
  done

  echo ""
  sleep "$INTERVAL"
done
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
9. **Write specific prompts** — follow the Prompting Playbook. Vague prompts waste credits.
10. **Include TASK COMPLETE signals** — every prompt should tell the agent how to signal completion
