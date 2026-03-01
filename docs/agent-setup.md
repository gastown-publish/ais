# Agent Setup Guide

How to configure Claude Code, Kimi Code, and OpenClaw for orchestrated multi-agent work.

For account creation and authentication, see [`account-setup.md`](account-setup.md).

---

## 1. Claude Code Sub-Agents

### Permissions for Autonomous Operation

Each account's `~/.claude-accounts/<name>/settings.json` must allow unattended execution. `ais` creates this automatically on first use, but you can set it up manually:

```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebSearch(*)",
      "WebFetch(*)"
    ],
    "deny": []
  }
}
```

### CLAUDE.md Template for Sub-Agents

Drop this in the working directory before spawning an agent:

```markdown
# Sub-Agent Standing Orders

You are a sub-agent managed by an orchestrator. Follow these rules:

1. **Stay focused** — complete only the task you were given
2. **Stay in scope** — only modify files specified in your task
3. **Report completion** — when done, print: TASK COMPLETE: <summary>
4. **Report errors** — if stuck, print: TASK BLOCKED: <reason>
5. **No git push** — commit locally but do NOT push
6. **No interactive prompts** — never ask for confirmation, just proceed
```

### Claude Code Account Reference

| Account | Tier | Use Case |
|---------|------|----------|
| `cc1`, `cc2` | Sonnet | Fast parallel tasks, simple fixes |
| `cc3`, `hataricc`, `nicxxx` | Opus | Complex reasoning, architecture |

### MCP Servers (Optional)

For agents that need to control other tmux sessions:

```json
{
  "mcpServers": {
    "tmux": {
      "command": "npx",
      "args": ["-y", "@nickgnd/tmux-mcp"]
    }
  }
}
```

Add to `~/.claude-accounts/<name>/settings.json` under `mcpServers`.

---

## 2. Kimi Code Sub-Agents

### Autonomous Operation

Kimi supports `--yolo` (`--yes` / `-y`) for auto-approve mode. `ais create --yolo` passes this automatically.

For persistent default:

```toml
# In ~/.kimi-accounts/<name>/config.toml
default_yolo = true
```

### Kimi CLI Key Flags

| Flag | Purpose |
|------|---------|
| `--yolo` / `-y` | Auto-approve all tool actions |
| `--print` | Non-interactive stdout mode (implies --yolo) |
| `--quiet` | Print mode + text only + final message |
| `-p "prompt"` | One-shot prompt (exits after completion) |
| `-C` | Continue most recent session |
| `-w <dir>` | Set working directory |
| `-m <model>` | Override model |

### When to Use Kimi vs Claude

| Factor | Claude Code | Kimi Code |
|--------|------------|-----------|
| **Cost** | Credits (limited) | Free |
| **Rate limits** | Per-account credits | Request-based |
| **Reasoning** | Opus is strongest | K2.5 is good |
| **Speed** | Fast (Sonnet), slow (Opus) | Fast |
| **Best for** | Complex multi-file refactors | Tests, boilerplate, simple edits |
| **Auto-approve** | settings.json permissions | `--yolo` flag |
| **Account env var** | `CLAUDE_CONFIG_DIR` | `KIMI_SHARE_DIR` |

**Strategy:** Use Kimi for high-volume simple tasks (saves Claude credits). Use Claude Opus for tasks requiring deep reasoning. Use Claude Sonnet for medium-complexity tasks.

---

## 3. OpenClaw Orchestrator

The orchestrator is an OpenClaw agent that manages sub-agents via `ais`.

### Install the Orchestrator Skill

```bash
# Copy from the ais repo
cp -r /path/to/ais/skills/ais-openclaw ~/.openclaw/workspace/skills/ais/

# Or for Claude Code as orchestrator
cp /path/to/ais/skills/ais-claude-code/orchestrate.md ~/.claude/commands/orchestrate.md
```

### OpenClaw Configuration

The orchestrator can run on a free model to avoid consuming Claude credits:

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "openrouter/moonshotai/kimi-k2.5",
        "fallbacks": ["openrouter/qwen/qwen3-coder:free"]
      }
    }
  }
}
```

---

## 4. Full Stack Verification

```bash
# 1. Check accounts
ais accounts

# 2. Test Claude agent
ais create test-claude -a claude -A cc1 --yolo -d /tmp \
  -c "echo hello. Print TASK COMPLETE: claude works."
sleep 30
ais inspect test-claude -n 20

# 3. Test Kimi agent
ais create test-kimi -a kimi -A 1 --yolo -d /tmp \
  -c "echo hello. Print TASK COMPLETE: kimi works."
sleep 20
ais inspect test-kimi -n 20

# 4. Clean up
ais kill --all
```
