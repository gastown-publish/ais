#!/bin/bash
# shellcheck disable=SC2001,SC2034
# check-credit.sh — Check Claude Code credit usage for all accounts
# Launches a temp Claude Code session per account, runs /usage, parses output
# Times displayed in GMT+7 (Bangkok)
#
# Usage: bash check-credit.sh
#        bash check-credit.sh cc3 hataricc   # check specific accounts only

set -uo pipefail

CLAUDE_BIN=~/.npm/bin/claude
ACCOUNTS_DIR=~/.claude-accounts
TMUX_SESSION="credit-check-tmp"
WAIT_LOAD=22        # seconds to wait for Claude to load (includes MOTD, trust prompt, plugins)
WAIT_USAGE=10       # seconds to wait for /usage output

# If specific accounts passed as args, use those; otherwise check all
if [ $# -gt 0 ]; then
  ACCOUNTS=("$@")
else
  ACCOUNTS=(cc1 cc2 cc3 hataricc nicxxx)
fi

# ============================================================================
# UTC to GMT+7 converter
# ============================================================================
convert_to_gmt7() {
  local time_str="$1"
  # Handle various formats from Claude Code /usage output

  # "Resets 12am (UTC)" -> today at 00:00 UTC
  # "Resets 8pm (UTC)" -> today at 20:00 UTC
  # "Resets 9am (UTC)" -> today at 09:00 UTC
  # "Resets Feb 28, 2am (UTC)" -> Feb 28 at 02:00 UTC
  # "Resets Mar 1, 6:59am (UTC)" -> Mar 1 at 06:59 UTC
  # "Resets Mar 1, 2pm (UTC)" -> Mar 1 at 14:00 UTC
  # "Resets Mar 4, 4am (UTC)" -> Mar 4 at 04:00 UTC

  # Extract the time string after "Resets "
  local reset_part
  reset_part=$(echo "$time_str" | sed 's/.*Resets //' | sed 's/ (UTC).*//' | sed 's/[[:space:]]*$//')

  if [ -z "$reset_part" ]; then
    echo "$time_str"
    return
  fi

  # Try to parse with GNU date
  local utc_epoch=""
  local year
  year=$(date +%Y)

  # Check if it has a date component (month name present)
  if echo "$reset_part" | grep -qE '^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'; then
    # Format: "Mar 1, 6:59am" or "Feb 28, 2am" or "Mar 1, 2pm"
    local month_day time_part
    month_day=$(echo "$reset_part" | sed 's/,.*//')
    time_part=$(echo "$reset_part" | sed 's/.*,[ ]*//')

    # Normalize time: "2am" -> "2:00am", "6:59am" stays "6:59am", "2pm" -> "2:00pm"
    if ! echo "$time_part" | grep -q ':'; then
      time_part=$(echo "$time_part" | sed 's/\([0-9]\+\)\([ap]m\)/\1:00\2/')
    fi
    # Convert 12h to 24h via date
    utc_epoch=$(date -u -d "$month_day $year $time_part UTC" +%s 2>/dev/null || echo "")
  else
    # Format: "12am" or "8pm" or "9am" — today's date
    local time_only="$reset_part"
    if ! echo "$time_only" | grep -q ':'; then
      time_only=$(echo "$time_only" | sed 's/\([0-9]\+\)\([ap]m\)/\1:00\2/')
    fi
    utc_epoch=$(date -u -d "today $time_only UTC" +%s 2>/dev/null || echo "")
  fi

  if [ -n "$utc_epoch" ]; then
    # Add 7 hours (25200 seconds) for GMT+7
    local gmt7_epoch=$((utc_epoch + 25200))
    local gmt7_str
    gmt7_str=$(date -u -d "@$gmt7_epoch" "+%b %d, %I:%M%p" 2>/dev/null | sed 's/AM/am/;s/PM/pm/')
    echo "$gmt7_str (GMT+7)"
  else
    echo "$time_str (UTC)"
  fi
}

# ============================================================================
# Check one account
# ============================================================================
check_account() {
  local acct="$1"
  local config_dir="$ACCOUNTS_DIR/$acct"

  if [ ! -d "$config_dir" ]; then
    echo "SKIP|$acct|Directory not found|–|–|–"
    return
  fi

  # Kill any leftover session
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

  # Start Claude Code with the account's config dir
  tmux new-session -d -s "$TMUX_SESSION" -x 160 -y 50
  tmux send-keys -t "$TMUX_SESSION" "CLAUDE_CONFIG_DIR=$config_dir $CLAUDE_BIN" Enter

  # Poll for Claude to be ready (prompt visible), handling trust/login screens
  local screen ready=false
  for _attempt in $(seq 1 30); do
    sleep 2
    screen=$(tmux capture-pane -t "$TMUX_SESSION" -p -S -30 2>/dev/null || true)

    # Check for login screen
    if echo "$screen" | grep -qiE "Select login method|log in to use"; then
      tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
      echo "AUTH|$acct|Not logged in|–|–|–"
      return
    fi

    # Check for trust/permissions prompt — accept it
    if echo "$screen" | grep -qiE "Yes, I (accept|trust)"; then
      tmux send-keys -t "$TMUX_SESSION" Enter
      continue
    fi

    # Check if Claude prompt is ready (the ❯ prompt or "Try" suggestion)
    if echo "$screen" | grep -qE '❯ $|Try "|esc to interrupt'; then
      ready=true
      break
    fi
  done

  if [ "$ready" != true ]; then
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    echo "TIMEOUT|$acct|Timed out waiting for prompt|–|–|–"
    return
  fi

  # Type '/' to trigger the slash-command picker (use -l for literal)
  tmux send-keys -t "$TMUX_SESSION" -l '/'
  sleep 2
  # Type 'usage' to filter the picker
  tmux send-keys -t "$TMUX_SESSION" -l 'usage'
  sleep 2
  # Enter to select /usage from picker
  tmux send-keys -t "$TMUX_SESSION" Enter
  sleep "$WAIT_USAGE"

  # Capture the usage output
  local output
  output=$(tmux capture-pane -t "$TMUX_SESSION" -p -S -40 2>/dev/null || true)

  # Parse usage data
  local week_all week_sonnet session_used
  local reset_all reset_sonnet

  # Extract weekly all-models percentage
  week_all=$(echo "$output" | grep -A2 "Current week (all models)" | grep -oP '\d+(?=% used)' | head -1)
  [ -z "$week_all" ] && week_all="?"

  # Extract Sonnet percentage
  week_sonnet=$(echo "$output" | grep -A2 "Sonnet only" | grep -oP '\d+(?=% used)' | head -1)
  [ -z "$week_sonnet" ] && week_sonnet="0"

  # Extract session percentage
  session_used=$(echo "$output" | grep -A2 "Current session" | grep -oP '\d+(?=% used)' | head -1)
  [ -z "$session_used" ] && session_used="0"

  # Extract reset times
  reset_all=$(echo "$output" | grep -A3 "Current week (all models)" | grep "Resets" | head -1 | sed 's/^[[:space:]]*//')
  reset_sonnet=$(echo "$output" | grep -A3 "Sonnet only" | grep "Resets" | head -1 | sed 's/^[[:space:]]*//')

  # Convert reset times to GMT+7
  local reset_all_gmt7 reset_sonnet_gmt7
  if [ -n "$reset_all" ]; then
    reset_all_gmt7=$(convert_to_gmt7 "$reset_all")
  else
    reset_all_gmt7="–"
  fi

  # Clean up
  tmux send-keys -t "$TMUX_SESSION" Escape 2>/dev/null
  sleep 1
  tmux send-keys -t "$TMUX_SESSION" '/exit' Enter 2>/dev/null
  sleep 2
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true

  local remaining="?"
  if [[ "$week_all" =~ ^[0-9]+$ ]]; then
    remaining=$((100 - week_all))
  fi
  echo "OK|$acct|$week_all|$week_sonnet|$remaining|$reset_all_gmt7"
}

# ============================================================================
# Main
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Claude Code Credit Check (GMT+7)                                  ║"
echo "║  Checking ${#ACCOUNTS[@]} accounts...                                            ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Collect results
declare -a RESULTS
for acct in "${ACCOUNTS[@]}"; do
  printf "  Checking %-12s ... " "$acct"
  result=$(check_account "$acct")
  RESULTS+=("$result")

  status=$(echo "$result" | cut -d'|' -f1)
  case "$status" in
    OK)   printf "done\n" ;;
    AUTH) printf "NOT LOGGED IN\n" ;;
    SKIP) printf "skipped\n" ;;
  esac
done

echo ""
echo "┌──────────────┬──────────┬──────────┬───────────┬──────────────────────────┐"
echo "│ Account      │ Week All │  Sonnet  │ Remaining │ Resets (GMT+7)           │"
echo "├──────────────┼──────────┼──────────┼───────────┼──────────────────────────┤"

for result in "${RESULTS[@]}"; do
  status=$(echo "$result" | cut -d'|' -f1)
  acct=$(echo "$result" | cut -d'|' -f2)

  if [ "$status" = "AUTH" ]; then
    printf "│ %-12s │  %-7s │  %-7s │  %-8s │ %-24s │\n" "$acct" "–" "–" "NO AUTH" "Needs login"
  elif [ "$status" = "SKIP" ]; then
    printf "│ %-12s │  %-7s │  %-7s │  %-8s │ %-24s │\n" "$acct" "–" "–" "SKIP" "Not found"
  else
    week_all=$(echo "$result" | cut -d'|' -f3)
    week_sonnet=$(echo "$result" | cut -d'|' -f4)
    remaining=$(echo "$result" | cut -d'|' -f5)
    resets=$(echo "$result" | cut -d'|' -f6)

    # Color coding
    bar=""
    if [ "$remaining" -le 0 ] 2>/dev/null; then
      bar="EMPTY"
    elif [ "$remaining" -le 20 ] 2>/dev/null; then
      bar="LOW"
    elif [ "$remaining" -le 50 ] 2>/dev/null; then
      bar="MED"
    else
      bar="OK"
    fi

    printf "│ %-12s │  %3s%%    │  %3s%%    │  %3s%% %-3s │ %-24s │\n" \
      "$acct" "$week_all" "$week_sonnet" "$remaining" "$bar" "$resets"
  fi
done

echo "└──────────────┴──────────┴──────────┴───────────┴──────────────────────────┘"
echo ""

# Summary recommendation
best_acct=""
best_remaining=0
for result in "${RESULTS[@]}"; do
  status=$(echo "$result" | cut -d'|' -f1)
  [ "$status" != "OK" ] && continue
  acct=$(echo "$result" | cut -d'|' -f2)
  remaining=$(echo "$result" | cut -d'|' -f5)
  if [ "$remaining" -gt "$best_remaining" ] 2>/dev/null; then
    best_remaining="$remaining"
    best_acct="$acct"
  fi
done

if [ -n "$best_acct" ]; then
  echo "  Best account: $best_acct ($best_remaining% remaining)"
  echo "  To use:  gt crew start <crew-name> --account $best_acct"
  echo ""
fi
