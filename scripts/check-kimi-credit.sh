#!/bin/bash
# check-kimi-credit.sh — Check Kimi Code status for all accounts
# Supports both API key and OAuth accounts
#
# Usage:
#   bash check-kimi-credit.sh              # check all accounts
#   bash check-kimi-credit.sh kimi1 kimi2  # check specific accounts
#
# Setup: see README in gist

set -uo pipefail

KIMI_BIN=~/.local/bin/kimi
ACCOUNTS_DIR=~/.kimi-accounts

# If specific accounts passed as args, use those; otherwise auto-discover
if [ $# -gt 0 ]; then
  ACCOUNTS=("$@")
else
  ACCOUNTS=()
  if [ -d "$ACCOUNTS_DIR" ]; then
    for d in "$ACCOUNTS_DIR"/*/; do
      [ -d "$d" ] && ACCOUNTS+=("$(basename "$d")")
    done
  fi
  if [ ${#ACCOUNTS[@]} -eq 0 ]; then
    echo ""
    echo "  No accounts found in $ACCOUNTS_DIR"
    echo ""
    echo "  Quick setup:"
    echo "    mkdir -p ~/.kimi-accounts/main && cp -r ~/.kimi/* ~/.kimi-accounts/main/"
    echo ""
    exit 1
  fi
fi

# ============================================================================
# Detect auth type from config.toml
# ============================================================================
detect_auth_type() {
  local share_dir="$1"
  local config="$share_dir/config.toml"
  [ ! -f "$config" ] && echo "none" && return

  # If api_key has a real value (not empty), it's API key auth
  if grep -q 'api_key = "sk-' "$config" 2>/dev/null; then
    echo "apikey"
  elif [ -f "$share_dir/credentials/kimi-code.json" ]; then
    echo "oauth"
  else
    echo "none"
  fi
}

# ============================================================================
# Check one account
# ============================================================================
check_account() {
  local acct="$1"
  local share_dir="$ACCOUNTS_DIR/$acct"

  [ ! -d "$share_dir" ] && echo "SKIP|$acct|–|Not found|–|–" && return

  local auth_type
  auth_type=$(detect_auth_type "$share_dir")

  # ---------- API Key account ----------
  if [ "$auth_type" = "apikey" ]; then
    local key_preview
    key_preview=$(grep 'api_key' "$share_dir/config.toml" 2>/dev/null | head -1 | sed 's/.*"sk-kimi-/sk-.../' | sed 's/".*//' | tail -c 9)

    local api_status
    local test_result
    test_result=$(KIMI_SHARE_DIR="$share_dir" timeout 20 "$KIMI_BIN" -c "Say just the word 'ok'" --quiet 2>/dev/null || echo "FAILED")

    if echo "$test_result" | grep -qi "ok\|yes\|hello\|sure\|certainly"; then
      api_status="WORKING"
    elif echo "$test_result" | grep -qi "rate.limit\|429\|quota\|exceeded\|too many"; then
      api_status="RATE LIMITED"
    elif echo "$test_result" | grep -qi "auth\|token\|unauthorized\|401\|403\|invalid.*key"; then
      api_status="BAD KEY"
    elif [ "$test_result" = "FAILED" ] || [ -z "$test_result" ]; then
      api_status="NO RESPONSE"
    else
      api_status="WORKING"
    fi

    echo "OK|$acct|API key|...$key_preview|No expiry|$api_status"
    return
  fi

  # ---------- OAuth account ----------
  if [ "$auth_type" = "oauth" ]; then
    local cred_file="$share_dir/credentials/kimi-code.json"

    local user_id
    user_id=$(python3 -c "
import json, base64
with open('$cred_file') as f:
    d = json.load(f)
token = d.get('access_token', '')
if '.' in token:
    payload = token.split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    decoded = json.loads(base64.urlsafe_b64decode(payload))
    print(decoded.get('user_id', '?')[:12])
else:
    print('?')
" 2>/dev/null || echo "?")

    local now
    now=$(date +%s)

    # Refresh token expiry (this is what matters — access tokens auto-refresh)
    local refresh_exp
    refresh_exp=$(python3 -c "
import json, base64
with open('$cred_file') as f:
    d = json.load(f)
token = d.get('refresh_token', '')
if '.' in token:
    payload = token.split('.')[1]
    payload += '=' * (4 - len(payload) % 4)
    decoded = json.loads(base64.urlsafe_b64decode(payload))
    print(decoded.get('exp', 0))
else:
    print(0)
" 2>/dev/null || echo "0")

    local refresh_status
    if [ "$refresh_exp" -gt "$now" ] 2>/dev/null; then
      local refresh_days=$(( (refresh_exp - now) / 86400 ))
      refresh_status="${refresh_days}d left"
    else
      refresh_status="EXPIRED"
    fi

    # API test
    local api_status
    local test_result
    test_result=$(KIMI_SHARE_DIR="$share_dir" timeout 20 "$KIMI_BIN" -c "Say just the word 'ok'" --quiet 2>/dev/null || echo "FAILED")

    if echo "$test_result" | grep -qi "ok\|yes\|hello\|sure\|certainly"; then
      api_status="WORKING"
    elif echo "$test_result" | grep -qi "rate.limit\|429\|quota\|exceeded\|too many"; then
      api_status="RATE LIMITED"
    elif echo "$test_result" | grep -qi "auth\|token\|unauthorized\|401\|403"; then
      api_status="AUTH ERROR"
    elif [ "$test_result" = "FAILED" ] || [ -z "$test_result" ]; then
      api_status="NO RESPONSE"
    else
      api_status="WORKING"
    fi

    echo "OK|$acct|OAuth|$user_id|$refresh_status|$api_status"
    return
  fi

  # ---------- No auth ----------
  echo "AUTH|$acct|–|No auth configured|–|–"
}

# ============================================================================
# Main
# ============================================================================
echo ""
echo "  Kimi Code Account Check"
echo "  ─────────────────────────────────────────────"
echo ""

declare -a RESULTS
for acct in "${ACCOUNTS[@]}"; do
  printf "  %-16s " "$acct"
  result=$(check_account "$acct")
  RESULTS+=("$result")

  status=$(echo "$result" | cut -d'|' -f1)
  api=$(echo "$result" | cut -d'|' -f6)
  case "$status" in
    OK)   printf "%s\n" "$api" ;;
    AUTH) printf "NOT CONFIGURED\n" ;;
    SKIP) printf "NOT FOUND\n" ;;
  esac
done

echo ""
echo "  ┌────────────────┬──────────┬──────────────┬─────────────┬──────────────┐"
echo "  │ Account        │ Auth     │ Identity     │ Expires     │ Status       │"
echo "  ├────────────────┼──────────┼──────────────┼─────────────┼──────────────┤"

for result in "${RESULTS[@]}"; do
  status=$(echo "$result" | cut -d'|' -f1)
  acct=$(echo "$result" | cut -d'|' -f2)
  auth=$(echo "$result" | cut -d'|' -f3)
  identity=$(echo "$result" | cut -d'|' -f4)
  expires=$(echo "$result" | cut -d'|' -f5)
  api=$(echo "$result" | cut -d'|' -f6)

  printf "  │ %-14s │ %-8s │ %-12s │ %-11s │ %-12s │\n" \
    "$acct" "$auth" "$identity" "$expires" "$api"
done

echo "  └────────────────┴──────────┴──────────────┴─────────────┴──────────────┘"
echo ""
echo "  Run:   KIMI_SHARE_DIR=~/.kimi-accounts/<name> kimi"
echo "  Add:   KIMI_SHARE_DIR=~/.kimi-accounts/<name> kimi login        (OAuth)"
echo "         or create config.toml with api_key                        (API key)"
echo ""
