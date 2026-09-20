#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
SOCKET="ego-test-$$"

test "$(rg -c "printf 'exec codex --sandbox workspace-write --add-dir" "$ROOT/bin/ego")" -eq 2
grep -q 'EGO_CLI_PATH.*session-start' "$ROOT/bin/ego"
grep -q 'controller_dir="$EGO_HOME/controller"' "$ROOT/bin/ego"
grep -Fq 'follow $guide' "$ROOT/bin/ego"
if grep -q 'new-window.*-c "$REPO_ROOT"' "$ROOT/bin/ego"; then
  printf 'controller still starts in the source repository\n' >&2
  exit 1
fi
grep -q 'Only the main controller runs `session-start` and `watch`' "$ROOT/CONTROLLER.md"
if grep -q 'ego watch' "$ROOT/AGENTS.md"; then
  printf 'development AGENTS.md contains controller watch instructions\n' >&2
  exit 1
fi

cleanup() {
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

export EGO_HOME="$TMP/state"
export EGO_TMUX_SOCKET="$SOCKET"
export EGO_AGENT_NAVIGATOR="$TMP/fake-agent-navigator"

EGO_ROOT="$TMP/ego-root" EGO_INSTALL_DIR="$TMP/install" "$ROOT/bin/ego" install >/dev/null
test -x "$TMP/install/ego"
test "$(cat "$TMP/install/repo-root")" = "$ROOT"
test -f "$TMP/ego-root/CONTROLLER.md"
"$TMP/install/ego" --help | grep -q '^  ego install$'

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'tmux -L "$EGO_TMUX_SOCKET" list-panes -a -F $'\''#{pane_id}\t#{window_name}\t#{session_name}:#{window_index}.#{pane_index}'\'' |'
  printf '%s\n' '  awk -F '\''\t'\'' '\''$2 ~ /^agent-/ || $2 == "optimizer" { print $1 "\tcodex\tidle\t" $3 }'\'''
} > "$EGO_AGENT_NAVIGATOR"
chmod 700 "$EGO_AGENT_NAVIGATOR"

tmux -L "$SOCKET" new-session -d -s alpha -c "$TMP" -n base
tmux -L "$SOCKET" set-option -g @workspace_primary "$TMP"
tmux -L "$SOCKET" new-window -d -t alpha: -n agent-one -c "$TMP"
tmux -L "$SOCKET" new-window -d -t alpha: -n optimizer -c "$TMP"
tmux -L "$SOCKET" new-session -d -s beta -c "$TMP" -n agent-two

"$ROOT/bin/ego" init >/dev/null
"$ROOT/bin/ego" scan >/dev/null

test -f "$EGO_HOME/agents/alpha--agent-one/meta"
test -f "$EGO_HOME/agents/beta--agent-two/meta"
test -f "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^origin=human$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^kind=primary$' "$EGO_HOME/workspaces/alpha/meta"

"$ROOT/bin/ego" handoff alpha--agent-one --summary "profiling is active" --next "collect a baseline" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/alpha--agent-one/meta"
grep -q 'profiling is active' "$EGO_HOME/agents/alpha--agent-one/handoff.md"

"$ROOT/bin/ego" report alpha--agent-one working "baseline started" >/dev/null
grep -q $'\tworking\tbaseline started$' "$EGO_HOME/agents/alpha--agent-one/status.log"

"$ROOT/bin/ego" onboard alpha--agent-one >/dev/null
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--agent-one/meta"
message=$(find "$EGO_HOME/agents/alpha--agent-one/inbox" -maxdepth 1 -name '*.msg' -exec basename {} .msg \; | head -1)
test -n "$message"
"$ROOT/bin/ego" inbox alpha--agent-one | grep -q "MESSAGE $message"
"$ROOT/bin/ego" ack alpha--agent-one "$message" >/dev/null
test -f "$EGO_HOME/agents/alpha--agent-one/inbox/handled/$message.msg"

onboard_output=$("$ROOT/bin/ego" onboard-workspace alpha)
printf '%s\n' "$onboard_output" | grep -q '^onboarded 1 agents in workspace alpha; 1 already reporting; 0 unavailable$'
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--optimizer/meta"
optimizer_messages_before=$(find "$EGO_HOME/agents/alpha--optimizer/inbox" -maxdepth 1 -name '*.msg' | wc -l | tr -d ' ')
onboard_output=$("$ROOT/bin/ego" onboard-workspace alpha)
printf '%s\n' "$onboard_output" | grep -q '^onboarded 0 agents in workspace alpha; 2 already reporting; 0 unavailable$'
optimizer_messages_after=$(find "$EGO_HOME/agents/alpha--optimizer/inbox" -maxdepth 1 -name '*.msg' | wc -l | tr -d ' ')
test "$optimizer_messages_before" -eq "$optimizer_messages_after"

"$ROOT/bin/ego" takeback alpha--agent-one >/dev/null
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--agent-one/meta"
"$ROOT/bin/ego" handoff agent-one --session alpha --summary "short selector" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/alpha--agent-one/meta"
"$ROOT/bin/ego" takeback agent-one --session alpha >/dev/null
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--agent-one/meta"
alpha_pane=$(tmux -L "$SOCKET" list-panes -t alpha:agent-one -F '#{pane_id}')
TMUX=test TMUX_PANE="$alpha_pane" "$ROOT/bin/ego" handoff agent-one --summary "current session selector" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/alpha--agent-one/meta"
TMUX=test TMUX_PANE="$alpha_pane" "$ROOT/bin/ego" takeback agent-one >/dev/null
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--agent-one/meta"

"$ROOT/bin/ego" checkpoint alpha --summary "workspace can recover" --next "run checks" >/dev/null
grep -q 'workspace can recover' "$EGO_HOME/workspaces/alpha/checkpoint.md"
"$ROOT/bin/ego" recover alpha | grep -q 'run checks'
"$ROOT/bin/ego" stow alpha --summary "only volatile context" --next "resume later" >/dev/null
grep -q '^Mode: stow$' "$EGO_HOME/workspaces/alpha/checkpoint.md"

"$ROOT/bin/ego" handoff-workspace beta --summary "delegate beta" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/beta--agent-two/meta"
"$ROOT/bin/ego" takeback-workspace beta >/dev/null
grep -q '^owner=human$' "$EGO_HOME/agents/beta--agent-two/meta"

"$ROOT/bin/ego" spawn three --session alpha --root "$TMP" --command 'sleep 5' --brief "test worker" >/dev/null
test -f "$EGO_HOME/agents/alpha--three/meta"
grep -q '^reporting=unknown$' "$EGO_HOME/agents/alpha--three/meta"
grep -q '^owner=ego$' "$EGO_HOME/agents/alpha--three/meta"
grep -q '^origin=ego$' "$EGO_HOME/agents/alpha--three/meta"
tmux -L "$SOCKET" list-windows -t alpha -F '#{window_name}' | grep -qx three

"$ROOT/bin/ego" spawn auto --session gamma --command 'sleep 5' --brief "auto workspace" >/dev/null
test -d "$TMP/gamma"
test "$(tmux -L "$SOCKET" display-message -p -t gamma '#{session_path}')" = "$TMP/gamma"
tmux -L "$SOCKET" list-windows -t gamma -F '#{window_name}' | grep -qx auto
grep -q '^root='"$TMP/gamma"'$' "$EGO_HOME/workspaces/gamma/meta"
if "$ROOT/bin/ego" spawn bad --session 'bad session' --command 'sleep 5' >/dev/null 2>&1; then
  printf 'spawn accepted a space in a new session name\n' >&2
  exit 1
fi

mkdir -p "$TMP/fake-bin"
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'case "$*" in'
  printf '%s\n' '  *"rev-parse --show-toplevel"*) printf "%s\\n" "$2" ;;'
  printf '%s\n' '  *"check-ref-format --branch"*) exit 0 ;;'
  printf '%s\n' '  *"show-ref --verify --quiet"*) exit 1 ;;'
  printf '%s\n' '  *"worktree add -b"*) mkdir -p "$7" ;;'
  printf '%s\n' '  *) exit 1 ;;'
  printf '%s\n' 'esac'
} > "$TMP/fake-bin/git"
chmod 700 "$TMP/fake-bin/git"
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" spawn isolated --session alpha --root "$TMP" --worktree --command 'sleep 5' --brief "isolated worker" >/dev/null
grep -q '^branch=ego/alpha--isolated$' "$EGO_HOME/agents/alpha--isolated/meta"
grep -q "^worktree=$EGO_HOME/worktrees/alpha--isolated$" "$EGO_HOME/agents/alpha--isolated/meta"
test -d "$EGO_HOME/worktrees/alpha--isolated"
"$ROOT/bin/ego" scan >/dev/null
grep -q '^branch=ego/alpha--isolated$' "$EGO_HOME/agents/alpha--isolated/meta"
grep -q "^root=$EGO_HOME/worktrees/alpha--isolated$" "$EGO_HOME/agents/alpha--isolated/meta"

"$ROOT/bin/ego" list | grep -q 'alpha--three'
"$ROOT/bin/ego" context | grep -q "Sandro's Ego context"
"$ROOT/bin/ego" session-start | grep -q "Sandro's Ego context"

(
  sleep 1
  "$ROOT/bin/ego" report alpha--agent-one working "quiet progress" >/dev/null
  sleep 1
  "$ROOT/bin/ego" report alpha--agent-one done "actionable completion" >/dev/null
) &
reporter=$!
watch_output=$("$ROOT/bin/ego" watch 5)
wait "$reporter"
printf '%s\n' "$watch_output" | grep -q $'\tdone\talpha--agent-one\tactionable completion$'
if printf '%s\n' "$watch_output" | grep -q 'quiet progress'; then
  printf 'watch surfaced routine progress\n' >&2
  exit 1
fi

tmux -L "$SOCKET" kill-session -t beta
"$ROOT/bin/ego" archive-workspace beta >/dev/null
grep -q '^state=archived$' "$EGO_HOME/workspaces/beta/meta"
if "$ROOT/bin/ego" context | grep -q '^beta'; then
  printf 'archived workspace remained in active context\n' >&2
  exit 1
fi

printf 'ok\n'
