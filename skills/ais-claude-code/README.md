# ais — Claude Code Skill

A Claude Code custom slash command that teaches Claude how to orchestrate multiple AI coding agents in parallel using the `ais` CLI.

## Install

Copy the command file to your Claude Code commands directory:

```bash
mkdir -p ~/.claude/commands
cp orchestrate.md ~/.claude/commands/orchestrate.md
```

## Usage

Inside Claude Code, type:

```
/orchestrate Fix all failing tests across the backend services
```

Claude will decompose the task, spawn sub-agents via `ais`, monitor them, and report results.

## Requirements

- `ais` CLI installed (`~/.local/bin/ais`)
- `tmux` installed
- At least one Claude Code or Kimi Code account configured
