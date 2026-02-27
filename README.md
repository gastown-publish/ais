# ais

AI coding agent session manager. Create, monitor, and control Claude Code and Kimi Code sessions in tmux.

## Features

- **Multi-agent support** — Works with both Claude Code and Kimi Code CLI tools
- **Multi-account management** — Run multiple accounts simultaneously across providers
- **Session lifecycle** — Create, list, inspect, inject commands, watch, and kill sessions
- **Live monitoring** — Watch session output in real-time with configurable refresh
- **Rate limit detection** — Automatically detect and alert on rate limit errors
- **Auto-injection** — Schedule commands to run after agent loads
- **Orchestrator skill** — OpenClaw skill for managing multi-agent workflows
- **Credit monitoring** — Check remaining credits for Claude and Kimi accounts

## Quick Start

```bash
# Clone and add to PATH
git clone https://github.com/gastown-publish/ais.git
export PATH="$PWD/ais/bin:$PATH"

# List available accounts
ais accounts

# Create your first agent session
ais create worker1 -a claude -A cc1 -c "fix the auth bug"

# Watch it work
ais watch worker1
```

## Usage

### Create a session

```bash
ais create <name> [options]

Options:
  -a, --agent TYPE      Agent type: claude or kimi (default: kimi)
  -A, --account ID      Account identifier (claude: cc1, cc2, ... | kimi: 1, 2, ...)
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
ais inject <name> "run tests"   # Send command to session
ais watch <name> -i 5           # Watch live, refresh every 5s
ais watch <name> --until "done" # Watch until pattern appears
ais logs <name>                 # Save full scrollback to file
ais kill <name>                 # Graceful shutdown
ais kill --all --force          # Force kill everything
```

## Tools Included

| Tool | Location | Description |
|------|----------|-------------|
| `ais` | `bin/` | Main CLI — session lifecycle manager |
| `kimi-account` | `bin/` | Kimi multi-account manager |
| `check-credit.sh` | `scripts/` | Claude credit/usage checker |
| `check-kimi-credit.sh` | `scripts/` | Kimi credit/usage checker |
| `ais-orchestrator` | `skills/` | OpenClaw skill for multi-agent orchestration |
| Agent setup guide | `docs/` | Plugin and skill configuration for Claude/Kimi/OpenClaw |
| Tmux agent control | `docs/` | Tmux patterns and recipes for agent management |

## Account Setup

### Claude Code

Accounts live in `~/.claude-accounts/`. Each directory (e.g., `cc1`, `cc2`) contains a separate Claude Code configuration. See `docs/agent-setup.md` for detailed setup instructions.

### Kimi Code

Accounts live in `~/.kimi-accounts/`. Use the `kimi-account` tool to manage multiple Kimi accounts. Run `kimi-account --help` for usage.

## Architecture

`ais` uses tmux as the execution environment. Each agent session runs in a named tmux session with metadata stored in session environment variables:

- `AIS_MANAGED` — Flag identifying ais-managed sessions
- `AIS_AGENT` — Agent type (claude/kimi)
- `AIS_ACCOUNT` — Account identifier
- `AIS_DIR` — Working directory
- `AIS_CREATED` — Creation timestamp

The orchestrator skill (`skills/ais-orchestrator/SKILL.md`) provides a higher-level workflow for OpenClaw agents to coordinate multiple ais sessions, handling task distribution, monitoring, and result collection.

## Contributing

This project uses [beads](https://github.com/gastown-publish/beads) for issue tracking. See `AGENTS.md` for the collaboration workflow.

```bash
bd ready          # Find available work
bd show <id>      # View issue details
bd close <id>     # Complete work
bd sync           # Sync with git
```

## License

MIT — see [LICENSE](LICENSE).
