# Controlling AI Agents via Tmux

A practical guide for programmatically creating, controlling, and monitoring Claude Code and Kimi Code sessions through tmux. All patterns are battle-tested from production patrol/nudge automation.

## Quick Start: `ais` CLI

The `ais` (AI Sessions) tool wraps all the patterns below into a single command:

```bash
# Install
curl -sL <gist-raw-url>/ais.sh -o ~/.local/bin/ais && chmod +x ~/.local/bin/ais

# Create a session
ais create worker1 -a kimi -A 1 -c "fix the tests"    # kimi account 1
ais create reviewer -a claude -A cc3 --yolo             # claude account cc3

# Monitor & interact
ais ls                              # list all sessions
ais inspect worker1 -n 100          # capture last 100 lines
ais inspect worker1 --rate-limit    # check for rate limits
ais inject worker1 "run the tests"  # send command
ais watch worker1 -i 5              # live monitor (every 5s)
ais logs worker1 -o session.log     # save full scrollback

# Manage
ais kill worker1                    # graceful shutdown
ais kill --all                      # kill all managed sessions
ais accounts                        # list available accounts
```

The rest of this document explains the raw tmux patterns that `ais` uses under the hood.

---

## Table of Contents

- [Core Concepts](#core-concepts)
- [Account Isolation](#account-isolation)
- [Session Lifecycle](#session-lifecycle)
- [Sending Commands](#sending-commands)
- [Capturing Output](#capturing-output)
- [Detecting Problems](#detecting-problems)
- [Common Recipes](#common-recipes)
- [Account Rotation](#account-rotation)
- [Safety Rules](#safety-rules)
- [Quick Reference](#quick-reference)

---

## Core Concepts

Both Claude Code and Kimi Code are interactive TUI (terminal UI) applications. To automate them:

1. **Create** a detached tmux session
2. **Launch** the agent inside it (with account env vars)
3. **Send** commands via `tmux send-keys`
4. **Capture** output via `tmux capture-pane`
5. **Parse** the captured text for status, errors, rate limits
6. **Exit** gracefully when done

---

## Account Isolation

Each tool uses an environment variable to point to an isolated config/credentials directory.

### Claude Code

```bash
# Env var: CLAUDE_CONFIG_DIR
# Default: ~/.claude
# Accounts live in: ~/.claude-accounts/<name>/

# Launch Claude Code with a specific account
CLAUDE_CONFIG_DIR=~/.claude-accounts/cc1 claude

# Each account dir contains:
# ~/.claude-accounts/cc1/
# ├── settings.json
# ├── credentials.json
# ├── projects/
# └── ...
```

### Kimi Code

```bash
# Env var: KIMI_SHARE_DIR
# Default: ~/.kimi
# Accounts live in: ~/.kimi-accounts/<number>/

# Launch Kimi with a specific account
KIMI_SHARE_DIR=~/.kimi-accounts/1 kimi

# Or use the wrapper
kimi-account 1

# Each account dir contains:
# ~/.kimi-accounts/1/
# ├── config.toml          # API key or OAuth config
# ├── credentials/          # OAuth tokens (if OAuth)
# └── sessions/
```

### OpenCode (uses Kimi credentials)

```bash
# OpenCode respects the same KIMI_SHARE_DIR
KIMI_SHARE_DIR=~/.kimi-accounts/1 opencode

# Or use the wrapper
kimi-account opencode 1
```

---

## Session Lifecycle

### Create a Session

```bash
SESSION="my-agent"

# Kill existing session if any (idempotent start)
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Create detached session with explicit dimensions
# Width 160+ avoids line-wrap issues in captured output
tmux new-session -d -s "$SESSION" -x 160 -y 50
```

### Launch Agent in Session

```bash
# Claude Code with account isolation
tmux send-keys -t "$SESSION" \
  "CLAUDE_CONFIG_DIR=~/.claude-accounts/cc1 claude" Enter

# Kimi Code with account isolation
tmux send-keys -t "$SESSION" \
  "KIMI_SHARE_DIR=~/.kimi-accounts/1 kimi" Enter

# Kimi Code with specific flags
tmux send-keys -t "$SESSION" \
  "KIMI_SHARE_DIR=~/.kimi-accounts/2 kimi --yolo" Enter

# OpenCode
tmux send-keys -t "$SESSION" \
  "KIMI_SHARE_DIR=~/.kimi-accounts/1 opencode" Enter

# IMPORTANT: Wait for the agent to fully start before sending commands
sleep 12  # Claude Code needs ~10-15 seconds to initialize
sleep 8   # Kimi Code needs ~5-10 seconds
```

### Exit Gracefully

```bash
# Claude Code: send /exit slash command
tmux send-keys -t "$SESSION" '/exit' Enter
sleep 3

# Kimi Code: send /exit or Ctrl-D
tmux send-keys -t "$SESSION" '/exit' Enter
sleep 3

# If the session is still alive, kill it
tmux kill-session -t "$SESSION" 2>/dev/null || true
```

### Check if Session Exists

```bash
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session is running"
else
  echo "Session is dead"
fi
```

---

## Sending Commands

### Basic Text Input

```bash
# Send a prompt/question to the agent
tmux send-keys -t "$SESSION" "fix the failing tests in auth.py" Enter

# Send a slash command
tmux send-keys -t "$SESSION" "/status" Enter

# Send just Enter (to accept a prompt, unstick a waiting agent)
tmux send-keys -t "$SESSION" Enter
```

### Navigating TUI Menus

Some commands (like Claude's `/usage`) open a picker menu:

```bash
# Send the command
tmux send-keys -t "$SESSION" '/usage' Enter
sleep 2

# Navigate down in the picker and select
tmux send-keys -t "$SESSION" Down Enter
sleep 5  # Wait for output to render
```

### Multi-Step Interactions

```bash
# Example: Check Claude Code credit usage
WAIT_LOAD=14    # Startup wait
WAIT_USAGE=8    # /usage response wait

# 1. Launch
tmux send-keys -t "$SESSION" \
  "CLAUDE_CONFIG_DIR=~/.claude-accounts/cc1 claude" Enter
sleep "$WAIT_LOAD"

# 2. Send /usage command
tmux send-keys -t "$SESSION" '/usage' Enter
sleep 2

# 3. Select first option in picker
tmux send-keys -t "$SESSION" Enter
sleep "$WAIT_USAGE"

# 4. Now capture the output (see next section)
```

### Timing Rules

| Action | Wait After |
|--------|-----------|
| Launch Claude Code | 12-15 seconds |
| Launch Kimi Code | 5-10 seconds |
| Send slash command | 2-3 seconds |
| Send text prompt | 1-2 seconds (before capture) |
| `/usage` response | 5-8 seconds |
| `/exit` command | 2-3 seconds |
| Navigate menu (Down/Enter) | 1-2 seconds |

---

## Capturing Output

### Basic Capture

```bash
# Capture the last 200 lines of output
OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -200 2>/dev/null)

# Flags:
#   -t SESSION   target session
#   -p           print to stdout (instead of paste buffer)
#   -S -200      start 200 lines back in scrollback history
#   2>/dev/null  suppress error if session doesn't exist
```

### Capture Depth Guidelines

| Purpose | Depth | Why |
|---------|-------|-----|
| Quick status check | `-S -50` | Recent activity only |
| Agent status/idle detection | `-S -200` | Need enough context to detect stalls |
| Rate limit detection | `-S -500` | Rate limit messages can scroll up fast |
| Full session review | `-S -1000` | Deep history for debugging |

### UTF-8 Sanitization (Critical)

Tmux captures can include invalid UTF-8 bytes, ANSI escape codes, and non-printable characters that break downstream parsers (JSON, Python, etc.). **Always sanitize:**

```bash
sanitize_utf8() {
  LC_ALL=C sed 's/[^[:print:][:space:]]//g' | \
    iconv -f utf-8 -t utf-8 -c 2>/dev/null || cat
}

# Usage
OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -200 2>/dev/null \
  | tail -200 \
  | sanitize_utf8)
```

### Trimming Output

When feeding captured output to another AI (e.g., Kimi for analysis), trim to avoid overwhelming the context:

```bash
# Trim to first 2000 characters
TRIMMED=$(echo "$OUTPUT" | head -c 2000)

# Or trim to last N lines
RECENT=$(echo "$OUTPUT" | tail -50)
```

### Multi-Agent Capture

```bash
# Capture all crew agents at once
SESSIONS="agent-1 agent-2 agent-3"
ALL_STATUS=""

for sess in $SESSIONS; do
  PANE_OUT=$(tmux capture-pane -t "$sess" -p -S -200 2>/dev/null \
    | tail -200 | sanitize_utf8 || echo "[session not found]")

  if [ -z "$PANE_OUT" ] || [ "$PANE_OUT" = "[session not found]" ]; then
    ALL_STATUS+="$sess: [NOT RUNNING]\n"
  else
    TRIMMED=$(echo "$PANE_OUT" | head -c 2000)
    ALL_STATUS+="--- $sess ---\n$TRIMMED\n\n"
  fi
done

echo -e "$ALL_STATUS"
```

---

## Detecting Problems

### Rate Limits

```bash
OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -500 2>/dev/null)

if echo "$OUTPUT" | grep -qiE \
  "rate.?limit|429|overloaded|quota.?exceeded|too many requests|credit balance is too low|insufficient_quota|hit your limit"; then
  echo "RATE LIMITED"
fi
```

**Patterns to detect:**

| Pattern | Meaning |
|---------|---------|
| `rate.?limit` | Generic rate limit |
| `429` | HTTP 429 Too Many Requests |
| `overloaded` | Service overloaded |
| `quota.?exceeded` | API quota exhausted |
| `too many requests` | Rate limit message |
| `credit balance is too low` | Claude Code credits gone |
| `insufficient_quota` | API quota error |
| `hit your limit` | Generic limit hit |

### Stalled / Idle Agent

```bash
OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -100 2>/dev/null)

# Check for idle indicators
if echo "$OUTPUT" | grep -qiE \
  "waiting.*instruction|standing by|no work|nothing to do"; then
  echo "AGENT IDLE"
fi

# Check for error states
if echo "$OUTPUT" | grep -qiE \
  "error|crash|failed|exception|traceback"; then
  echo "AGENT ERROR"
fi
```

### Authentication Errors

```bash
if echo "$OUTPUT" | grep -qiE \
  "auth|unauthorized|invalid.*key|401|403|token.*expired|login.*required"; then
  echo "AUTH ERROR"
fi
```

### Testing if Agent Responds

```bash
# Quick test: send a simple prompt and check response
KIMI_SHARE_DIR=~/.kimi-accounts/1 timeout 20 kimi \
  -c "Say just the word 'ok'" --quiet 2>/dev/null

# Evaluate response
RESULT=$?
if [ $RESULT -eq 0 ]; then
  echo "WORKING"
elif [ $RESULT -eq 124 ]; then
  echo "TIMEOUT"
else
  echo "FAILED"
fi
```

---

## Common Recipes

### Recipe 1: One-Shot Command with Result

Run a command, capture the output, clean up.

```bash
#!/bin/bash
SESSION="oneshot-$$"
ACCOUNT_DIR=~/.kimi-accounts/1
PROMPT="list all files in the current directory"

# Create session and launch
tmux new-session -d -s "$SESSION" -x 160 -y 50
tmux send-keys -t "$SESSION" \
  "KIMI_SHARE_DIR=$ACCOUNT_DIR kimi -c '$PROMPT' --quiet" Enter

# Wait for completion (adjust timeout as needed)
sleep 30

# Capture result
RESULT=$(tmux capture-pane -t "$SESSION" -p -S -200 2>/dev/null | sanitize_utf8)

# Clean up
tmux kill-session -t "$SESSION" 2>/dev/null || true

echo "$RESULT"
```

### Recipe 2: Interactive Agent with Periodic Monitoring

Launch an agent and check on it every N minutes.

```bash
#!/bin/bash
SESSION="my-worker"
CHECK_INTERVAL=300  # 5 minutes

# Launch
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -x 160 -y 50
tmux send-keys -t "$SESSION" \
  "CLAUDE_CONFIG_DIR=~/.claude-accounts/cc1 claude --yolo" Enter
sleep 15

# Monitor loop
while true; do
  sleep "$CHECK_INTERVAL"

  # Check if session still exists
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session died. Restarting..."
    tmux new-session -d -s "$SESSION" -x 160 -y 50
    tmux send-keys -t "$SESSION" \
      "CLAUDE_CONFIG_DIR=~/.claude-accounts/cc1 claude --yolo" Enter
    sleep 15
    continue
  fi

  # Capture and check for problems
  OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -500 2>/dev/null | sanitize_utf8)

  if echo "$OUTPUT" | grep -qiE "rate.?limit|429|credit balance"; then
    echo "Rate limited! Consider rotating account."
    # See Account Rotation section below
  fi
done
```

### Recipe 3: Send a Nudge to Running Agent

```bash
# Send a message/instruction to a running Claude Code session
SESSION="my-worker"
MSG="Please check the test results and fix any failures"

# Just type the message into the agent's input
tmux send-keys -t "$SESSION" "$MSG" Enter
```

### Recipe 4: Check All Claude Accounts

```bash
#!/bin/bash
ACCOUNTS=(cc1 cc2 cc3 hataricc nicxxx)
SESSION="credit-check-tmp"
CLAUDE_BIN=~/.claude/local/claude

for acct in "${ACCOUNTS[@]}"; do
  config_dir=~/.claude-accounts/$acct

  tmux kill-session -t "$SESSION" 2>/dev/null || true
  tmux new-session -d -s "$SESSION" -x 160 -y 50

  tmux send-keys -t "$SESSION" \
    "CLAUDE_CONFIG_DIR=$config_dir $CLAUDE_BIN" Enter
  sleep 14

  tmux send-keys -t "$SESSION" '/usage' Enter
  sleep 2
  tmux send-keys -t "$SESSION" Enter
  sleep 8

  OUTPUT=$(tmux capture-pane -t "$SESSION" -p -S -100 2>/dev/null)
  echo "=== $acct ==="
  echo "$OUTPUT" | grep -iE "percent|usage|credit|limit|reset" || echo "(no usage data found)"
  echo ""

  tmux send-keys -t "$SESSION" '/exit' Enter
  sleep 2
  tmux kill-session -t "$SESSION" 2>/dev/null || true
done
```

### Recipe 5: Check All Kimi Accounts

```bash
#!/bin/bash
ACCOUNTS_DIR=~/.kimi-accounts
KIMI_BIN=~/.local/bin/kimi

for d in "$ACCOUNTS_DIR"/*/; do
  [ ! -d "$d" ] && continue
  acct=$(basename "$d")
  printf "  %-4s  " "$acct"

  result=$(KIMI_SHARE_DIR="$d" timeout 20 "$KIMI_BIN" \
    -c "Say just the word 'ok'" --quiet 2>/dev/null || echo "FAILED")

  if echo "$result" | grep -qi "ok\|yes\|hello"; then
    echo "WORKING"
  elif echo "$result" | grep -qi "rate.limit\|429"; then
    echo "RATE LIMITED"
  elif echo "$result" | grep -qi "auth\|unauthorized\|401"; then
    echo "BAD KEY"
  else
    echo "NO RESPONSE"
  fi
done
```

### Recipe 6: Run Multiple Agents in Parallel

```bash
#!/bin/bash
# Launch 3 Kimi agents on different accounts, each in their own tmux session

AGENTS=("worker-1:1" "worker-2:2" "worker-3:3")  # session:account

for entry in "${AGENTS[@]}"; do
  sess="${entry%%:*}"
  acct="${entry##*:}"

  tmux kill-session -t "$sess" 2>/dev/null || true
  tmux new-session -d -s "$sess" -x 160 -y 50
  tmux send-keys -t "$sess" \
    "KIMI_SHARE_DIR=~/.kimi-accounts/$acct kimi --yolo" Enter
done

echo "Launched ${#AGENTS[@]} agents. Use 'tmux ls' to see sessions."
echo "Attach: tmux attach -t worker-1"
echo "Monitor: tmux capture-pane -t worker-1 -p -S -50"
```

---

## Account Rotation

When an agent hits a rate limit, rotate to a different account.

### Round-Robin Selection

```bash
ALL_ACCOUNTS=(cc1 cc2 cc3 hataricc nicxxx)

get_next_account() {
  local current="$1"
  local found=false

  for acct in "${ALL_ACCOUNTS[@]}"; do
    if [ "$found" = true ]; then
      echo "$acct"
      return
    fi
    [ "$acct" = "$current" ] && found=true
  done

  # Wrap around to first
  echo "${ALL_ACCOUNTS[0]}"
}

# Usage
CURRENT="cc1"
NEXT=$(get_next_account "$CURRENT")
echo "Rotating from $CURRENT to $NEXT"
```

### Rotation with Cooldown

Prevent rotating the same agent too frequently:

```bash
ROTATION_COOLDOWN=300  # 5 minutes

should_rotate() {
  local agent_name="$1"
  local cooldown_file="/tmp/rotation-${agent_name}"

  if [ -f "$cooldown_file" ]; then
    local last_rotation=$(cat "$cooldown_file" 2>/dev/null || echo 0)
    local now=$(date +%s)
    local elapsed=$((now - last_rotation))

    if [ "$elapsed" -lt "$ROTATION_COOLDOWN" ]; then
      echo "Cooldown active (${elapsed}s / ${ROTATION_COOLDOWN}s). Skipping."
      return 1
    fi
  fi

  # Record this rotation
  date +%s > "$cooldown_file"
  return 0
}

# Usage
if should_rotate "my-agent"; then
  NEXT=$(get_next_account "$CURRENT")
  # Restart agent with new account...
fi
```

### Full Rotation Flow (Claude Code)

```bash
rotate_claude_agent() {
  local session="$1"
  local current_account="$2"
  local next_account=$(get_next_account "$current_account")

  echo "Rotating $session: $current_account -> $next_account"

  # Gracefully exit current session
  tmux send-keys -t "$session" '/exit' Enter
  sleep 3

  # Relaunch with new account
  tmux send-keys -t "$session" \
    "CLAUDE_CONFIG_DIR=~/.claude-accounts/$next_account claude --yolo" Enter
  sleep 15

  echo "Rotated to $next_account"
}
```

### Full Rotation Flow (Kimi Code)

```bash
rotate_kimi_agent() {
  local session="$1"
  local current_account="$2"
  local next_account=$((current_account + 1))

  # Check if next account exists, wrap around if not
  if [ ! -d ~/.kimi-accounts/$next_account ]; then
    next_account=1
  fi

  echo "Rotating $session: account $current_account -> $next_account"

  # Exit current session
  tmux send-keys -t "$session" '/exit' Enter
  sleep 3

  # Relaunch with new account
  tmux send-keys -t "$session" \
    "KIMI_SHARE_DIR=~/.kimi-accounts/$next_account kimi --yolo" Enter
  sleep 10

  echo "Rotated to account $next_account"
}
```

### Kimi Config Fallback (API key → OAuth)

When using Kimi one-shot commands, try API key config first, fall back to OAuth:

```bash
KIMI_CONFIGS=(
  ~/.kimi-accounts/2/config.toml    # API key (try first)
  ~/.kimi-accounts/1/config.toml    # OAuth (fallback)
)
RESULT=""

for cfg in "${KIMI_CONFIGS[@]}"; do
  [ ! -f "$cfg" ] && continue
  RESULT=$(timeout 90 kimi -c "$PROMPT" --quiet --config-file "$cfg" 2>/dev/null || true)
  if [ -n "$RESULT" ] && [ ${#RESULT} -ge 10 ]; then
    break  # Got a real response
  fi
  RESULT=""
done

if [ -z "$RESULT" ]; then
  echo "All Kimi configs failed"
fi
```

---

## Safety Rules

### Never Kill with Ctrl-C

```bash
# NEVER DO THIS — it kills the Claude/Kimi process abruptly
tmux send-keys -t "$SESSION" C-c   # BAD! Don't do this!

# Instead, use the graceful exit command
tmux send-keys -t "$SESSION" '/exit' Enter  # Correct
```

### Always Sanitize Captured Output

Raw tmux capture includes ANSI escapes, non-printable bytes, and potentially invalid UTF-8. Always sanitize before:
- Passing to `grep`/`sed`
- Feeding to another AI model
- Storing in a file or variable for JSON serialization

```bash
sanitize_utf8() {
  LC_ALL=C sed 's/[^[:print:][:space:]]//g' | \
    iconv -f utf-8 -t utf-8 -c 2>/dev/null || cat
}
```

### Wait Before Capturing

Never `send-keys` and `capture-pane` in the same instant. The agent needs time to process the command and render output.

```bash
# BAD — output won't have the response yet
tmux send-keys -t "$SESSION" "hello" Enter
tmux capture-pane -t "$SESSION" -p

# GOOD — give it time
tmux send-keys -t "$SESSION" "hello" Enter
sleep 5
tmux capture-pane -t "$SESSION" -p -S -50
```

### Use Adequate Capture Depth

Shallow captures miss important context. Rate limit errors and long outputs scroll fast.

```bash
# BAD — too shallow, misses rate limit messages
tmux capture-pane -t "$SESSION" -p -S -10

# GOOD — deep enough for rate limits
tmux capture-pane -t "$SESSION" -p -S -500
```

### Trim Before Feeding to AI

Don't feed 10,000 characters of raw tmux output to a model. Trim it:

```bash
# Trim to 2000 chars per agent
TRIMMED=$(echo "$OUTPUT" | head -c 2000)
```

### Suppress Errors on Dead Sessions

Always redirect stderr when accessing tmux sessions that might not exist:

```bash
tmux capture-pane -t "$SESSION" -p -S -50 2>/dev/null || echo "[session not found]"
tmux has-session -t "$SESSION" 2>/dev/null
tmux send-keys -t "$SESSION" Enter 2>/dev/null || true
```

---

## Quick Reference

### Environment Variables

| Variable | Tool | Purpose |
|----------|------|---------|
| `CLAUDE_CONFIG_DIR` | Claude Code | Point to account-specific config dir |
| `KIMI_SHARE_DIR` | Kimi Code, OpenCode | Point to account-specific share dir |

### Account Directories

| Tool | Base Dir | Example |
|------|----------|---------|
| Claude Code | `~/.claude-accounts/` | `~/.claude-accounts/cc1/` |
| Kimi Code | `~/.kimi-accounts/` | `~/.kimi-accounts/1/` |

### Tmux Commands Cheat Sheet

```bash
# Session management
tmux new-session -d -s NAME -x 160 -y 50    # Create detached
tmux has-session -t NAME 2>/dev/null          # Check exists
tmux kill-session -t NAME 2>/dev/null         # Destroy
tmux ls                                        # List all sessions
tmux attach -t NAME                            # Attach (interactive)

# Sending input
tmux send-keys -t NAME "text" Enter            # Type + enter
tmux send-keys -t NAME Enter                   # Just press enter
tmux send-keys -t NAME Down Enter              # Navigate menu

# Capturing output
tmux capture-pane -t NAME -p                   # Capture visible
tmux capture-pane -t NAME -p -S -500           # Capture with history
tmux capture-pane -t NAME -p -S -500 | tail -100  # Last 100 lines
```

### Timing Cheat Sheet

| Operation | Sleep After |
|-----------|------------|
| Launch Claude Code | 12-15s |
| Launch Kimi Code | 5-10s |
| Send slash command | 2-3s |
| Send text prompt | 1-2s |
| `/usage` response | 5-8s |
| `/exit` before kill | 2-3s |
| Menu navigation | 1-2s |

### Detection Patterns

```bash
# Rate limits
grep -qiE "rate.?limit|429|overloaded|quota.?exceeded|too many requests|credit balance is too low|insufficient_quota|hit your limit"

# Auth errors
grep -qiE "auth|unauthorized|invalid.*key|401|403|token.*expired"

# Agent idle
grep -qiE "waiting.*instruction|standing by|no work|nothing to do"

# Agent working
grep -qiE "running|executing|reading|writing|searching|thinking"
```
