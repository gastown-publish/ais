# Agent Setup Guide

How to configure Claude Code, Kimi Code, and OpenClaw instances for orchestrated multi-agent work.

---

## 1. Claude Code Sub-Agents

### Install Plugins

Each Claude Code account should have these plugins installed. Run inside a Claude Code session (or for each account):

```bash
# Essential for autonomous agents
/plugin install superpowers@claude-plugins-official
/plugin install code-review@claude-plugins-official
/plugin install code-simplifier@claude-plugins-official

# Optional but useful
/plugin install playwright@claude-plugins-official       # browser automation
/plugin install typescript-lsp@claude-plugins-official    # TS language server
/plugin install claude-code-setup@claude-plugins-official # setup automation
```

To install across all accounts:

```bash
for acct in cc1 cc2 cc3 hataricc nicxxx; do
  echo "=== Setting up $acct ==="
  CLAUDE_CONFIG_DIR=~/.claude-accounts/$acct claude --dangerously-skip-permissions \
    -c "/plugin install superpowers@claude-plugins-official" 2>/dev/null || true
done
```

### Settings for Autonomous Operation

Each account's `~/.claude-accounts/<name>/settings.json` should allow unattended execution:

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
      "WebSearch",
      "WebFetch(*)"
    ]
  }
}
```

Or simply use `--dangerously-skip-permissions` flag (which `ais create --yolo` does automatically for Claude).

### CLAUDE.md Template for Sub-Agents

Drop this in the working directory before spawning the agent:

```markdown
# Sub-Agent Standing Orders

You are a sub-agent managed by an orchestrator. Follow these rules:

1. **Stay focused** — complete only the task you were given
2. **Stay in scope** — only modify files in this directory
3. **Report completion** — when done, print: TASK COMPLETE: <summary>
4. **Report errors** — if stuck, print: TASK BLOCKED: <reason>
5. **No git push** — commit locally but do NOT push
6. **No interactive prompts** — never ask for confirmation, just proceed
```

### MCP Servers (Optional, Advanced)

For agents that need to control other tmux sessions or manage processes:

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

### Claude Code Account Reference

| Account | Tier | Use Case |
|---------|------|----------|
| `cc1` | Sonnet | Fast parallel tasks, simple fixes |
| `cc2` | Sonnet | Fast parallel tasks, simple fixes |
| `cc3` | Opus | Complex reasoning, architecture |
| `hataricc` | Opus | Complex tasks, fallback |
| `nicxxx` | Opus | Complex tasks, fallback |

---

## 2. Kimi Code Sub-Agents

### Account Setup

**API Key method (recommended for agents):**

```bash
kimi-account add sk-kimi-YOUR_KEY_HERE
```

Get keys from [platform.kimi.com](https://platform.kimi.com/). API keys never expire.

**OAuth method (for interactive use):**

```bash
kimi-account login              # auto-number
kimi-account login 3            # specific account
```

### Autonomous Operation

Use `--yolo` flag for auto-approve mode. `ais create --yolo` handles this automatically.

```bash
# Manual
KIMI_SHARE_DIR=~/.kimi-accounts/1 kimi --yolo

# Via ais (recommended)
ais create my-agent -a kimi -A 1 --yolo -c "your task"
```

### Kimi Skills

Kimi has its own skills directory at `~/.kimi/skills/`. To add a skill:

```bash
mkdir -p ~/.kimi/skills/my-skill/
cat > ~/.kimi/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: Description of the skill
---

# Skill content here
EOF
```

### Kimi vs Claude — When to Use Which

| Factor | Claude Code | Kimi Code |
|--------|------------|-----------|
| **Cost** | Credits (limited) | Free |
| **Rate limits** | Per-account credits | Request-based |
| **Reasoning** | Opus is strongest | K2.5 is good, not Opus-level |
| **Speed** | Fast (Sonnet), slow (Opus) | Fast |
| **Best for** | Complex multi-file refactors, debugging | Test fixing, boilerplate, error handling |
| **Auto-approve** | `--dangerously-skip-permissions` | `--yolo` |
| **Account env var** | `CLAUDE_CONFIG_DIR` | `KIMI_SHARE_DIR` |

**Strategy:** Use Kimi for high-volume simple tasks (saves Claude credits). Use Claude Opus for tasks requiring deep reasoning. Use Claude Sonnet for medium-complexity tasks.

### Kimi Account Reference

Run `kimi-account list` to see all accounts.

| Account | Auth | Expiry |
|---------|------|--------|
| `1` | OAuth | 30-day refresh token |
| `2` | API key | Never |
| `3+` | Add more | `kimi-account add <key>` |

---

## 3. OpenClaw Orchestrator

The orchestrator is an OpenClaw agent that manages all the sub-agents.

### Install the Orchestrator Skill

```bash
mkdir -p ~/.openclaw/skills/ais-orchestrator/scripts/
cp /path/to/orchestrator-skill.md ~/.openclaw/skills/ais-orchestrator/SKILL.md
cp ~/.local/bin/ais ~/.openclaw/skills/ais-orchestrator/scripts/ais
chmod +x ~/.openclaw/skills/ais-orchestrator/scripts/ais
```

### Required Built-in Skills

These ship with OpenClaw and should already be available:

| Skill | Purpose |
|-------|---------|
| `tmux` | Raw tmux send-keys / capture-pane control |
| `coding-agent` | Spawn Claude/Codex/OpenCode as background processes |
| `clawhub` | Discover and install skills from ClawHub registry |
| `github` | GitHub repo management |
| `gh-issues` | GitHub issue tracking |

Verify they're available:

```bash
ls ~/.local/lib/node_modules/openclaw/skills/ | grep -E "tmux|coding-agent|clawhub|github"
```

### OpenClaw Configuration

The orchestrator's `~/.openclaw/openclaw.json` should have:

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

This means the orchestrator itself runs on Kimi K2.5 (free) — it doesn't consume Claude credits for management overhead.

### Optional: Additional ClawHub Skills

Browse and install from ClawHub if needed:

```bash
# Search for relevant skills
clawhub search "task management"
clawhub search "monitoring"

# Install a skill
clawhub install <skill-slug>

# Update all installed skills
clawhub update --all
```

**Security warning:** ClawHub is an open registry. Vet skills before installing — check the source code, author reputation, and avoid skills that request elevated permissions unnecessarily.

### Optional: MCP Servers for the Orchestrator

If using Claude Code as the orchestrator instead of OpenClaw:

```json
{
  "mcpServers": {
    "tmux": {
      "command": "npx",
      "args": ["-y", "@nickgnd/tmux-mcp"]
    },
    "taskqueue": {
      "command": "npx",
      "args": ["-y", "taskqueue-mcp"]
    }
  }
}
```

- **tmux-mcp** (`nickgnd/tmux-mcp`) — lets Claude Code directly read/control tmux sessions
- **taskqueue-mcp** (`chriscarrollsmith/taskqueue-mcp`) — structured task queue with approval checkpoints
- **pm-mcp** (`patrickjm/pm-mcp`) — process manager for background tasks, log searching

---

## 4. ais CLI Setup

The `ais` tool is the glue between the orchestrator and sub-agents.

### Install

```bash
curl -sL <gist-raw-url>/ais.sh -o ~/.local/bin/ais
chmod +x ~/.local/bin/ais
```

Or copy from this gist's `ais.sh` file.

### Verify

```bash
ais --version          # should print "ais 1.0.0"
ais accounts           # should list Claude + Kimi accounts
ais ls                 # should show no sessions (or existing ones)
```

### Quick Test

```bash
# Create a test session
ais create test -a kimi -A 1 -c "say hello"
sleep 12

# Check it's running
ais ls
ais inspect test -n 10

# Clean up
ais kill test
```

---

## 5. Full Stack Verification

After setting up everything, verify the full orchestration chain:

```bash
# 1. Check accounts are configured
ais accounts

# 2. Check Claude accounts have credit
bash check-credit.sh

# 3. Check Kimi accounts are working
kimi-account check

# 4. Test spawning agents
ais create test-claude -a claude -A cc1 --yolo -c "echo hello from claude"
ais create test-kimi -a kimi -A 1 --yolo -c "say hello from kimi"
sleep 15

# 5. Verify both running
ais ls

# 6. Check output
ais inspect test-claude -n 10
ais inspect test-kimi -n 10

# 7. Clean up
ais kill --all

# 8. Check OpenClaw skill is available
ls ~/.openclaw/skills/ais-orchestrator/
```

---

## Marketplace Reference

### Claude Code Plugins

| Source | URL |
|--------|-----|
| Official | [github.com/anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) |
| In-app | `/plugin > Discover` inside Claude Code |
| Community | [claudecodeplugins.io](https://claudecodeplugins.io/) |

### OpenClaw Skills

| Source | URL |
|--------|-----|
| ClawHub | [clawhub.ai](https://clawhub.ai/) |
| Built-in | `~/.local/lib/node_modules/openclaw/skills/` |
| Custom | `~/.openclaw/skills/` |
| Curated | [github.com/VoltAgent/awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills) |

### MCP Servers

| Source | URL |
|--------|-----|
| Official registry | [registry.modelcontextprotocol.io](https://registry.modelcontextprotocol.io/) |
| Community (17K+) | [mcp.so](https://mcp.so/) |
| Curated list | [github.com/punkpeye/awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers) |
| Official implementations | [github.com/modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) |
