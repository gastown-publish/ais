<p align="center">
  <h1 align="center">ais</h1>
  <p align="center">
    Scriptable, multi-provider AI agent session manager.
    <br />
    Create, monitor, and orchestrate Claude Code and Kimi Code sessions in tmux.
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
    <a href="#"><img src="https://img.shields.io/badge/shell-bash-green.svg" alt="Bash"></a>
    <a href="#"><img src="https://img.shields.io/badge/platform-linux%20%7C%20macos-lightgrey.svg" alt="Platform"></a>
    <a href="https://github.com/gastown-publish/ais/actions"><img src="https://github.com/gastown-publish/ais/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  </p>
</p>

---

## Why ais?

Most multi-agent tools give you a dashboard. `ais` gives you a **scriptable CLI** that agents themselves can operate — enabling agent-orchestrates-agents workflows.

| | ais | claude-squad | agent-deck |
|---|---|---|---|
| **Multi-provider** (Claude + Kimi) | Yes | Claude only | Claude only |
| **Multi-account** (rotate credits) | Yes | No | No |
| **Scriptable** (no TUI required) | Yes | TUI-first | TUI-first |
| **Agent-operable** (AI runs AI) | Yes | No | No |
| **Headless/CI-friendly** | Yes | No | No |
| **Rate limit detection** | Built-in | No | No |
| **Orchestrator skill** (OpenClaw) | Yes | No | No |

`ais` is built for power users who run fleets of AI agents, rotate across accounts to avoid rate limits, and want their orchestrator agent to manage the whole thing.

---

## Quick Start

```bash
# Install
git clone https://github.com/gastown-publish/ais.git
export PATH="$PWD/ais/bin:$PATH"

# See your accounts
ais accounts

# Launch an agent
ais create worker1 -a claude -A cc1 -c "fix the auth bug"

# Watch it work
ais watch worker1
```

<details>
<summary><strong>Example: <code>ais ls</code> output</strong></summary>

```
  NAME                 AGENT    ACCOUNT    DIR                            AGE
  ──────────────────── ──────── ────────── ────────────────────────────── ────────
  worker1              claude   cc1        ~/project                      12m
  worker2              claude   cc2        ~/project                      8m
  kimi-refactor        kimi     2          ~/other-project                3m
```

</details>

<details>
<summary><strong>Example: <code>ais accounts</code> output</strong></summary>

```
  Claude Code accounts (~/.claude-accounts)
  ─────────────────────────────────────
    cc1           (logged in)
    cc2           (logged in)
    cc3           (configured)

  Kimi Code accounts (~/.kimi-accounts)
  ─────────────────────────────────────
    1             (API key)
    2             (OAuth)
```

</details>

---

## Real-World Workflows

### Parallel bug hunt across 3 agents

```bash
# Spin up 3 agents on different accounts to avoid rate limits
ais create hunt1 -a claude -A cc1 -d ~/app -c "find the memory leak in src/server/"
ais create hunt2 -a claude -A cc2 -d ~/app -c "audit error handling in src/api/"
ais create hunt3 -a kimi   -A 1  -d ~/app -c "review database queries for N+1 issues"

# Monitor all of them
ais ls

# Check on progress
ais inspect hunt1 -n 100

# When done, clean up
ais kill --all --save
```

### Credit rotation

```bash
# Check remaining credits across all accounts
./scripts/check-credit.sh      # Claude
./scripts/check-kimi-credit.sh  # Kimi

# Check specific accounts only
./scripts/check-credit.sh cc1 cc3
```

<details>
<summary><strong>Example output</strong></summary>

```
╔══════════════════════════════════════════════════════════════════════╗
║  Claude Code Credit Check (GMT+7)                                  ║
╚══════════════════════════════════════════════════════════════════════╝

┌──────────────┬──────────┬──────────┬───────────┬──────────────────────────┐
│ Account      │ Week All │  Sonnet  │ Remaining │ Resets (GMT+7)           │
├──────────────┼──────────┼──────────┼───────────┼──────────────────────────┤
│ cc1          │    6%    │    0%    │   94% OK  │ Mar 06, 10:00am (GMT+7)  │
│ cc2          │    1%    │    0%    │   99% OK  │ Mar 06, 12:00pm (GMT+7)  │
│ cc3          │    2%    │    0%    │   98% OK  │ Mar 06, 11:00am (GMT+7)  │
└──────────────┴──────────┴──────────┴───────────┴──────────────────────────┘

  Best account: cc2 (99% remaining)
```

</details>

```bash
# Switch to a fresh account when one hits limits
ais kill worker1
ais create worker1 -a claude -A cc2 -d ~/app -c "continue from where cc1 left off"
```

### Agent-orchestrates-agents (via OpenClaw)

The `skills/ais-orchestrator/SKILL.md` enables an OpenClaw agent to:
1. Spawn worker agents with `ais create`
2. Monitor their output with `ais inspect`
3. Detect rate limits and rotate accounts
4. Collect results and coordinate across sessions

This is the "AI that runs AIs" pattern — your orchestrator agent manages a fleet of coding agents without human intervention.

---

## Usage Reference

### Create a session

```bash
ais create <name> [options]

Options:
  -a, --agent TYPE      Agent: claude, kimi (default: kimi)
  -A, --account ID      Account: cc1..nicxxx for claude, 1..N for kimi
  -c, --cmd TEXT        Command to inject after agent loads
  -d, --dir PATH        Working directory (default: current)
  --yolo                Auto-approve mode
  --attach              Attach to session after creation
  --size WxH            Terminal size (default: 160x50)
  --                    Pass remaining flags to agent CLI
```

### Manage sessions

```bash
ais ls                          # List all managed sessions
ais inspect <name> -n 200       # Capture last 200 lines of output
ais inspect <name> --rate-limit # Check for rate limit errors
ais inject <name> "run tests"   # Send command to session
ais watch <name> -i 5           # Watch live, refresh every 5s
ais watch <name> --until "done" # Watch until pattern appears
ais logs <name>                 # Save full scrollback to file
ais kill <name>                 # Graceful shutdown
ais kill <name> --save          # Save logs, then kill
ais kill --all --force          # Force kill everything
```

---

## Tools Included

| Tool | Location | Description |
|------|----------|-------------|
| `ais` | `bin/` | Main CLI — session lifecycle manager |
| `kimi-account` | `bin/` | Kimi multi-account manager |
| `check-credit.sh` | `scripts/` | Claude credit/usage checker |
| `check-kimi-credit.sh` | `scripts/` | Kimi credit/usage checker |
| `ais-orchestrator` | `skills/` | OpenClaw skill for multi-agent orchestration |
| Agent setup guide | `docs/` | Plugin and skill configuration |
| Tmux agent control | `docs/` | Tmux patterns and recipes |

---

## Account Setup

### Claude Code

Each account lives in `~/.claude-accounts/<name>/` (e.g., `cc1`, `cc2`). Each directory contains a separate Claude Code configuration with its own credentials.

See [`docs/agent-setup.md`](docs/agent-setup.md) for detailed setup instructions.

### Kimi Code

Accounts live in `~/.kimi-accounts/<n>/`. Use the `kimi-account` tool to manage them:

```bash
kimi-account --help
```

---

## Architecture

`ais` uses tmux as the execution layer. Each agent session runs in a named tmux session with metadata stored in environment variables:

| Variable | Purpose |
|----------|---------|
| `AIS_MANAGED` | Identifies ais-managed sessions |
| `AIS_AGENT` | Agent type (`claude` / `kimi`) |
| `AIS_ACCOUNT` | Account identifier |
| `AIS_DIR` | Working directory |
| `AIS_CREATED` | Creation timestamp (epoch seconds) |

The orchestrator skill (`skills/ais-orchestrator/SKILL.md`) provides a higher-level interface for OpenClaw agents to coordinate multiple sessions — handling task distribution, rate limit rotation, and result collection.

---

## Prerequisites

- **bash** 4.0+
- **tmux** 3.0+
- **Claude Code CLI** (`~/.local/bin/claude`) and/or **Kimi Code CLI** (`~/.local/bin/kimi`)
- At least one configured account in `~/.claude-accounts/` or `~/.kimi-accounts/`

---

## FAQ

<details>
<summary><strong>How is this different from claude-squad?</strong></summary>

claude-squad is a TUI (terminal user interface) — you interact with it through a dashboard. `ais` is a scriptable CLI designed to be called from scripts, cron jobs, or other AI agents. If you want a visual dashboard, use claude-squad. If you want to automate multi-agent workflows or have an AI orchestrate other AIs, use `ais`.

</details>

<details>
<summary><strong>Can I use both Claude and Kimi in the same workflow?</strong></summary>

Yes. Each session independently specifies its agent type. You can run Claude agents on some tasks and Kimi agents on others, mixing providers freely.

</details>

<details>
<summary><strong>How does credit rotation work?</strong></summary>

Configure multiple accounts (e.g., `cc1`, `cc2`, `cc3`). When one hits rate limits (detected via `ais inspect --rate-limit`), kill that session and create a new one on a fresh account. The credit checker scripts help you monitor balances proactively.

</details>

<details>
<summary><strong>Can an AI agent operate ais?</strong></summary>

Yes — this is a core design goal. The OpenClaw orchestrator skill (`skills/ais-orchestrator/SKILL.md`) provides a complete workflow for an AI agent to spawn, monitor, and manage other AI agent sessions. All `ais` commands produce machine-parseable output suitable for programmatic use.

</details>

---

## Contributing

We welcome contributions! See [`CONTRIBUTING.md`](CONTRIBUTING.md) for guidelines.

This project uses [beads](https://github.com/gastown-publish/beads) for issue tracking:

```bash
bd ready          # Find available work
bd show <id>      # View issue details
bd close <id>     # Complete work
```

See [`AGENTS.md`](AGENTS.md) for the agent collaboration workflow.

---

## Prior Art

This repo consolidates tools originally shared as standalone gists:

- [Claude credit checker + agent setup](https://gist.github.com/thanakijwanavit/c0877d834e288de104b38f3f8cda233c) — `check-credit.sh`, `ais`, orchestrator skill, agent setup guide
- [Kimi credit checker + multi-account](https://gist.github.com/thanakijwanavit/4d0e343bd8e0fbeefa8c0c7e03d13b91) — `check-kimi-credit.sh`, `kimi-account`, Kimi multi-account README

This repo is the canonical, maintained version. The gists remain for reference.

## License

MIT — see [LICENSE](LICENSE).
