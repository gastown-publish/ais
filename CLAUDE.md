# ais — AI Session Orchestrator

This repo contains the tooling for managing AI coding agent sessions (Claude Code, Kimi Code) via tmux.

## Project Structure

```
bin/          CLI tools (ais, kimi-account)
scripts/      Credit checkers and utilities
skills/       OpenClaw skills for agent orchestration
docs/         Setup guides and tmux patterns
```

## Key Commands

```bash
ais create <name> -a claude -A cc1    # Create Claude session
ais create <name> -a kimi -A 2        # Create Kimi session
ais ls                                 # List sessions
ais inspect <name>                     # View session output
ais inject <name> "command"            # Send command to session
ais watch <name>                       # Live monitor
ais kill <name>                        # Shutdown session
ais accounts                           # List available accounts
```

## Rules

- Use `bd` (beads) for issue tracking — see AGENTS.md
- Follow Landing the Plane protocol when ending sessions
- Keep shell scripts POSIX-compatible where possible
- Test changes against both Claude and Kimi agent types
- Do not hardcode account paths — use the `~/.claude-accounts/` and `~/.kimi-accounts/` conventions
