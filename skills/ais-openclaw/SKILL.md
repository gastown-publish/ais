---
name: ais
description: "Run AI coding agents (Claude Code, Kimi Code) via the ais CLI. Use this skill when a user asks you to run, spawn, manage, or orchestrate AI agents, coding agents, Claude, or Kimi sessions. Requires: ais CLI, tmux."
metadata:
  { "openclaw": { "emoji": "🤖", "os": ["linux", "darwin"], "requires": { "bins": ["ais", "tmux"] } } }
---

# ais — Run AI Agents

Spawn and manage Claude Code and Kimi Code sessions using the `ais` CLI. Use this when users ask you to run AI agents on a task, parallelize work, or orchestrate multiple coding agents.

## Commands

```bash
ais create <name> -a claude|kimi -A <account> --yolo -d <dir> -c "<prompt>"
ais ls                              # list sessions
ais inspect <name> -n <lines>       # read output
ais inspect <name> --rate-limit     # check rate limit
ais inject <name> "<text>"          # send input
ais watch <name> -i <seconds>       # live tail
ais logs <name> -o <file>           # save scrollback
ais kill <name> [--save]            # stop agent
ais kill --all                      # stop all
ais accounts                        # list accounts
```

## Quick Start

```bash
# 1. Check available accounts
ais accounts

# 2. Spawn an agent
ais create my-task -a claude -A cc1 --yolo -d ~/project \
  -c "Fix the failing test in tests/test_auth.py. Only modify src/auth.py. Print TASK COMPLETE when done."

# 3. Check on it
ais inspect my-task -n 20

# 4. Collect result and clean up
ais inspect my-task -n 100
ais kill my-task --save
```

## Writing Good Prompts

The prompt you pass to `-c` determines whether the agent succeeds or wastes time. Follow these rules:

**Be specific.** Name the exact files, functions, and error messages.

**Set scope.** Tell the agent which files to modify and which to leave alone.

**Signal completion.** Always include: "Print TASK COMPLETE: `<summary>` when done."

**Give context.** Paste error output and relevant code. Don't tell the agent to go find it.

### Template

```
<One-sentence task description>

Context:
<Error message, test output, or relevant code>

Scope:
- Modify: <specific files>
- Do NOT modify: <off-limits files>

When done: run <verification command> and print TASK COMPLETE: <summary>.
```

### Example

```bash
ais create fix-discount -a claude -A cc1 --yolo -d ~/project \
  -c "Fix tests/test_checkout.py::test_apply_discount.
Error: AssertionError: expected 90.0 but got 100.0.
The discount logic is in src/checkout/pricing.py apply_discount().
Only modify src/checkout/pricing.py.
Run: pytest tests/test_checkout.py -v
Print TASK COMPLETE: <pass/fail count>."
```

## Choosing the Right Agent

| Task | Agent | Account | Why |
|------|-------|---------|-----|
| Complex debugging, architecture | Claude Opus | cc3, hataricc, nicxxx | Best reasoning |
| Standard fixes, medium work | Claude Sonnet | cc1, cc2 | Fast, capable |
| Boilerplate, tests, simple edits | Kimi | 1, 2, 3... | Free |

## Parallel Work

Spawn multiple agents across different accounts:

```bash
ais create worker1 -a claude -A cc1 --yolo -d ~/project/svc-a -c "task 1..."
ais create worker2 -a claude -A cc2 --yolo -d ~/project/svc-b -c "task 2..."
ais create worker3 -a kimi   -A 1   --yolo -d ~/project/svc-c -c "task 3..."
```

Monitor all:

```bash
for name in $(ais ls 2>/dev/null | tail -n +3 | awk '{print $1}'); do
  echo "=== $name ==="
  ais inspect "$name" -n 5 2>/dev/null | tail -3
done
```

## Rate Limit Recovery

If `ais inspect <name> --rate-limit` detects a limit:

```bash
ais kill <name>
ais create <name> -a claude -A <different-account> --yolo -d <same-dir> -c "<same-prompt>"
```

Rotation order — Claude: cc1→cc2→cc3→hataricc→nicxxx. Kimi: 1→2→3→...

## Rules

1. Run `ais accounts` before spawning — know your inventory
2. One account per agent — never double up
3. Use Kimi for simple tasks — it's free
4. Every prompt needs TASK COMPLETE signal
5. Monitor every 2-5 minutes
6. Rotate immediately on rate limit
7. Save logs before killing: `ais kill <name> --save`
