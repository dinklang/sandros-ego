#!/usr/bin/env bash
# Live supervision check: spawn a real agent through Ego, then verify that
# context detects it, peek reads its pane, and send lands an inbox notice in it.
#
# Usage: tests/integration-agents.sh [--strict] [--keep] [kiro] [claude] [codex]
#
# Runs against real agent CLIs on an isolated tmux socket and EGO_HOME, so it
# needs the agents installed and authenticated. Default checks stop at the
# notice being visible in the pane. --strict also waits for the worker to react
# (read its inbox or write a report), which depends on the agent being allowed
# to run shell commands without a permission prompt. --keep leaves the tmux
# server and state directory in place for inspection.
set -eu

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STRICT=0
KEEP=0
AGENTS=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --keep) KEEP=1 ;;
    kiro|claude|codex) AGENTS+=("$arg") ;;
    *) printf 'unknown argument %s\n' "$arg" >&2; exit 2 ;;
  esac
done
[ ${#AGENTS[@]} -gt 0 ] || AGENTS=(kiro claude codex)

READY_TIMEOUT=${EGO_IT_READY_TIMEOUT:-90}
NOTICE_TIMEOUT=${EGO_IT_NOTICE_TIMEOUT:-15}
REACT_TIMEOUT=${EGO_IT_REACT_TIMEOUT:-120}

TMP=$(mktemp -d)
SOCKET="ego-it-$$"
SESSION=ego-it
export EGO_HOME="$TMP/state"
export EGO_TMUX_SOCKET="$SOCKET"
EGO="$ROOT/bin/ego"
NAVIGATOR=${EGO_AGENT_NAVIGATOR:-}
if [ -z "$NAVIGATOR" ]; then
  for candidate in "$HOME/.tmux/plugins/agent-navigator/scripts/agent-navigator" \
    "$HOME/.local/share/agent-navigator/bin/agent-navigator"; do
    [ -x "$candidate" ] && { NAVIGATOR=$candidate; break; }
  done
fi
[ -x "$NAVIGATOR" ] || { printf 'Agent Navigator not found at %s\n' "$NAVIGATOR" >&2; exit 2; }

PASS=0
FAIL=0
WARN=0
log() { printf '%s\n' "$*"; }
pass() { PASS=$((PASS + 1)); log "  PASS $*"; }
fail() { FAIL=$((FAIL + 1)); log "  FAIL $*"; }
warn() { WARN=$((WARN + 1)); log "  WARN $*"; }

cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    log "kept tmux socket $SOCKET and state $EGO_HOME"
    return
  fi
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

tm() { tmux -L "$SOCKET" "$@"; }

# Poll a command until it succeeds or the timeout elapses.
wait_for() {
  local timeout=$1 deadline
  shift
  deadline=$((SECONDS + timeout))
  while [ $SECONDS -lt $deadline ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  return 1
}

pane_has() { "$EGO" peek "$1" 200 | grep -q -- "$2"; }

navigator_state() {
  local pane=$1 socket_path
  socket_path=$(tm display-message -p '#{socket_path}')
  TMUX="$socket_path,0,0" "$NAVIGATOR" list | awk -F '\t' -v p="$pane" '$1 == p { print $2 "\t" $3; exit }'
}

navigator_idle() {
  local state
  state=$(navigator_state "$1")
  [ "${state#*	}" = idle ]
}

# Claude asks whether to trust a new directory before running the prompt.
# Answering it is harness work, so it uses tmux directly rather than ego press.
answer_claude_trust() {
  local id=$1 pane=$2
  if wait_for 30 pane_has "$id" 'Yes, I trust this folder'; then
    tm send-keys -t "$pane" Down
    sleep 1
    tm send-keys -t "$pane" Enter
    log "  info answered Claude trust dialog"
  fi
}

reacted() {
  local dir=$1
  [ -n "$(find "$dir/inbox/handled" -maxdepth 1 -name '*.msg' 2>/dev/null)" ] \
    || [ -s "$dir/status.log" ]
}

run_agent() {
  local agent=$1 id="$SESSION--$agent-worker" dir pane state exe
  log "== $agent =="
  exe=$agent
  [ "$agent" != kiro ] || exe=kiro-cli
  if ! command -v "$exe" >/dev/null 2>&1; then
    warn "$exe not installed; skipped"
    return
  fi
  if ! "$EGO" spawn "$agent-worker" --session "$SESSION" --root "$TMP/ws" --agent "$agent" \
      --brief "Integration check. Do nothing until an instruction arrives." >/dev/null; then
    fail "spawn"
    return
  fi
  pass "spawn"
  dir="$EGO_HOME/agents/$id"
  pane=$(awk -F= '$1 == "pane_id" { print $2 }' "$dir/meta")

  [ "$agent" != claude ] || answer_claude_trust "$id" "$pane"

  if wait_for "$READY_TIMEOUT" navigator_idle "$pane"; then
    pass "agent-navigator reports idle ($(navigator_state "$pane" | cut -f1))"
  else
    state=$(navigator_state "$pane")
    fail "agent not idle within ${READY_TIMEOUT}s (navigator: ${state:-not detected})"
    "$EGO" peek "$id" 15 | sed 's/^/    | /'
    return
  fi

  "$EGO" context >/dev/null
  if grep -q "^agent=$agent\$" "$dir/meta"; then
    pass "context records agent=$agent"
  else
    fail "context recorded $(grep '^agent=' "$dir/meta")"
  fi

  if "$EGO" peek "$id" 40 | grep -q '^Last 40 pane lines:$'; then
    pass "peek returns pane content"
  else
    fail "peek returned nothing"
  fi

  local message
  message=$("$EGO" send "$id" "Integration check: read this inbox message, then report idle with the message PONG." | awk '{ print $2 }')
  if wait_for "$NOTICE_TIMEOUT" pane_has "$id" "EGO_INBOX: message $message"; then
    pass "send notice visible in pane"
  else
    fail "send notice not visible within ${NOTICE_TIMEOUT}s"
  fi

  if [ "$STRICT" -eq 1 ]; then
    if wait_for "$REACT_TIMEOUT" reacted "$dir"; then
      pass "worker reacted (inbox read or report)"
      [ ! -s "$dir/status.log" ] || tail -n 1 "$dir/status.log" | sed 's/^/    | /'
    else
      fail "worker did not read its inbox or report within ${REACT_TIMEOUT}s"
      "$EGO" peek "$id" 15 | sed 's/^/    | /'
    fi
  fi
}

mkdir -p "$TMP/ws"
# A tmux server inherits its creator's environment; drop sandbox variables that
# would break agents launched from a sandboxed shell.
env -u SANDBOX_SESSION_ID -u AWS_CONFIG_FILE -u AWS_SHARED_CREDENTIALS_FILE -u KIRO_ENABLED_FEATURES \
  tmux -L "$SOCKET" new-session -d -s "$SESSION" -n base -c "$TMP/ws" -x 200 -y 50

for agent in "${AGENTS[@]}"; do
  run_agent "$agent"
done

log ""
log "passed=$PASS failed=$FAIL warnings=$WARN"
[ "$FAIL" -eq 0 ]
