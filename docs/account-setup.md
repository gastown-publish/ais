# Account Setup

Step-by-step instructions for configuring Claude Code and Kimi Code accounts for use with `ais`.

Each account gets its own isolated directory so you can run multiple agents on different accounts simultaneously without credential conflicts.

---

## Claude Code Accounts

Each Claude Code account lives in `~/.claude-accounts/<name>/` with its own OAuth credentials and settings.

### Step 1: Create the account directory

```bash
# Pick a name (e.g., cc1, cc2, work, personal)
ACCOUNT=cc1
mkdir -p ~/.claude-accounts/$ACCOUNT
```

### Step 2: Log in via OAuth

```bash
CLAUDE_CONFIG_DIR=~/.claude-accounts/$ACCOUNT claude auth login
```

This opens a browser. Log in with your Anthropic account, authorize, and paste the code back into the terminal.

**Running as root (e.g., inside Docker)?** Add the sandbox bypass:

```bash
IS_SANDBOX=1 CLAUDE_CONFIG_DIR=~/.claude-accounts/$ACCOUNT claude auth login
```

**No browser available?** Copy the URL from the terminal, open it on any device, log in, and paste the code back.

### Step 3: Set up permissions for autonomous operation

Create `~/.claude-accounts/$ACCOUNT/settings.json`:

```bash
cat > ~/.claude-accounts/$ACCOUNT/settings.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "WebFetch(*)",
      "WebSearch(*)"
    ],
    "deny": []
  }
}
EOF
```

This allows the agent to run any command without prompting. **ais does this automatically** on first use of each account, but you can do it manually if you prefer.

### Step 4: Complete first-run onboarding (optional)

Claude Code has a first-run onboarding flow (theme picker, workspace trust, security notice). When you run `ais create` for the first time with a new account, the AI-powered TUI navigator handles this automatically. But if you want to complete it manually:

```bash
IS_SANDBOX=1 CLAUDE_CONFIG_DIR=~/.claude-accounts/$ACCOUNT claude
```

Walk through the prompts (theme, trust workspace, accept security notice), then type `/exit` to quit.

### Step 5: Verify

```bash
ais accounts
# Should show your account as "(logged in)" or "(configured)"
```

### Quick setup for multiple accounts

```bash
for ACCOUNT in cc1 cc2 cc3; do
  mkdir -p ~/.claude-accounts/$ACCOUNT
  echo "--- Setting up $ACCOUNT ---"
  echo "Run: CLAUDE_CONFIG_DIR=~/.claude-accounts/$ACCOUNT claude auth login"
  echo "Then paste the OAuth code when prompted."
  echo ""
done
```

Each account needs its own separate OAuth login — you cannot copy credentials between accounts because shared refresh tokens conflict.

### Troubleshooting

| Problem | Fix |
|---------|-----|
| "Cannot run as root" | Add `IS_SANDBOX=1` before the command |
| "Nested Claude Code session" | Unset `CLAUDECODE` env var: `CLAUDECODE= claude auth login` |
| Token refresh conflicts | Each account must have its own OAuth login, don't copy `.credentials.json` between accounts |
| Settings not applied | Check path: `~/.claude-accounts/<name>/settings.json` (not `~/.claude/settings.json`) |

---

## Kimi Code Accounts

Each Kimi Code account lives in `~/.kimi-accounts/<name>/` with its own credentials and config.

Kimi supports two auth methods: **OAuth** (free, browser-based) and **API key** (from platform.kimi.com).

### Option A: OAuth login

```bash
# Pick a name
ACCOUNT=kimi1
mkdir -p ~/.kimi-accounts/$ACCOUNT

# Log in
KIMI_SHARE_DIR=~/.kimi-accounts/$ACCOUNT kimi login
```

Follow the browser OAuth flow. Token refreshes automatically for ~30 days.

### Option B: API key

```bash
ACCOUNT=kimi1
mkdir -p ~/.kimi-accounts/$ACCOUNT

# Create config with API key
cat > ~/.kimi-accounts/$ACCOUNT/config.toml << EOF
[providers."managed:kimi-code"]
type = "kimi"
base_url = "https://api.kimi.com/coding/v1"
api_key = "sk-YOUR-KIMI-API-KEY"
EOF
```

Get API keys from [platform.kimi.com](https://platform.kimi.com/). API keys never expire.

### Using the kimi-account helper

If you have the `kimi-account` tool installed:

```bash
kimi-account add sk-YOUR-KEY        # Add by API key (auto-numbered)
kimi-account login                   # OAuth login (auto-numbered)
kimi-account login 3                 # OAuth login for specific account number
kimi-account list                    # Show all accounts
kimi-account check                   # Verify all accounts work
```

### Auto-approve mode

Kimi supports `--yolo` (or `--yes` / `-y`) for auto-approve mode. When you use `ais create --yolo`, this flag is passed automatically.

You can also set it as default in the account config:

```bash
# Add to ~/.kimi-accounts/<name>/config.toml
echo 'default_yolo = true' >> ~/.kimi-accounts/$ACCOUNT/config.toml
```

### Verify

```bash
ais accounts
# Should show your Kimi account as "(OAuth)" or "(API key)"
```

---

## Container Setup (Docker)

When running ais inside a Docker container (e.g., for OpenClaw):

### Claude Code in containers

```bash
# The root check bypass is required
export IS_SANDBOX=1

# Prevent nested session detection if running from another Claude session
unset CLAUDECODE

# Then proceed with normal setup
CLAUDE_CONFIG_DIR=~/.claude-accounts/cc1 claude auth login
```

### Kimi Code in containers

No special setup needed — Kimi doesn't have a root check:

```bash
KIMI_SHARE_DIR=~/.kimi-accounts/1 kimi login
```

### Install ais in a container

```bash
# From the repo
git clone https://github.com/gastown-publish/ais.git /tmp/ais
cp /tmp/ais/bin/ais ~/.local/bin/ais
chmod +x ~/.local/bin/ais

# Or direct download
curl -sL https://raw.githubusercontent.com/gastown-publish/ais/main/bin/ais \
  -o ~/.local/bin/ais && chmod +x ~/.local/bin/ais
```

---

## Account Summary

| Agent | Env Var | Account Dir | Auth Methods |
|-------|---------|-------------|--------------|
| Claude Code | `CLAUDE_CONFIG_DIR` | `~/.claude-accounts/<name>/` | OAuth (browser) |
| Kimi Code | `KIMI_SHARE_DIR` | `~/.kimi-accounts/<name>/` | OAuth (browser), API key |

| Account | Best For | Notes |
|---------|----------|-------|
| Claude Sonnet (cc1, cc2) | Standard fixes, medium tasks | Fast, consumes credits |
| Claude Opus (cc3, etc.) | Complex reasoning, architecture | Slow but best quality |
| Kimi (1, 2, 3...) | Boilerplate, tests, simple edits | Free, no credit cost |
