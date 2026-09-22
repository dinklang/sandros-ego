#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
SOCKET="ego-test-$$"

test "$(rg -c "printf 'exec codex --sandbox workspace-write --add-dir" "$ROOT/bin/ego")" -eq 1
grep -q "printf 'exec kiro-cli chat" "$ROOT/bin/ego"
# --add-dir is variadic in Claude Code and swallows a trailing prompt.
grep -q "printf 'exec claude %s --add-dir %s" "$ROOT/bin/ego"
grep -q 'EGO_CLI_PATH.*session-start' "$ROOT/bin/ego"
# The controller inherits its session's workspace root, with the neutral state
# directory only as a fallback.
grep -q 'controller_dir=$(resolve_session_root "$session"' "$ROOT/bin/ego"
grep -q 'controller_dir="$EGO_HOME/controller"' "$ROOT/bin/ego"
# Claude runs the controller by default; Kiro runs the workers.
grep -q 'local session= window=ego agent=claude scope=' "$ROOT/bin/ego"
grep -q 'local name=$1 session= root= id= brief= command_text= agent=kiro' "$ROOT/bin/ego"
# Retirement must survive a rescan, or archive-workspace and forget undo themselves.
grep -q "active=\$(meta_get \"\$meta\" active)" "$ROOT/bin/ego"
# display-message needs "=name:"; the bare "=name" form silently returns nothing.
grep -q 'display-message -p -t "=$session:" .#{session_path}.' "$ROOT/bin/ego"
# A stale pane id also makes display-message exit 0 with empty fields.
grep -q "case \"\$out\" in ''|\$'\\\\t'\*) return 1 ;; esac" "$ROOT/bin/ego"
# A session path equal to a workspace root must descend into the session directory.
grep -q 'refine_workspace_root "$session" "$root"' "$ROOT/bin/ego"
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
"$TMP/install/ego" handoff --help | grep -q '^Usage: ego handoff'
"$TMP/install/ego" report --help | grep -q 'working|idle|blocked|needs-decision|done|failed|note'
"$TMP/install/ego" press --help | grep -q '^Usage: ego press'

{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' '# Fail unless Ego pointed us at its socket through $TMUX, as the real navigator relies on.'
  printf '%s\n' 'case "${TMUX:-}" in */'"$SOCKET"',*) ;; *) printf "navigator TMUX=%s\n" "${TMUX:-unset}" >&2; exit 1 ;; esac'
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
"$ROOT/bin/ego" report alpha--agent-one validating "checking output" >/dev/null
grep -q $'\tworking\tchecking output$' "$EGO_HOME/agents/alpha--agent-one/status.log"
"$ROOT/bin/ego" report alpha--agent-one waiting "no assignment" >/dev/null
grep -q $'\tidle\tno assignment$' "$EGO_HOME/agents/alpha--agent-one/status.log"
"$ROOT/bin/ego" report alpha--agent-one working "baseline started" >/dev/null

"$ROOT/bin/ego" onboard alpha--agent-one >/dev/null
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--agent-one/meta"
message=$(find "$EGO_HOME/agents/alpha--agent-one/inbox" -maxdepth 1 -name '*.msg' -exec basename {} .msg \; | head -1)
test -n "$message"
"$ROOT/bin/ego" inbox alpha--agent-one | grep -q "MESSAGE $message"
"$ROOT/bin/ego" ack alpha--agent-one "$message" >/dev/null
test -f "$EGO_HOME/agents/alpha--agent-one/inbox/handled/$message.msg"
"$ROOT/bin/ego" press alpha--agent-one enter | grep -q '^pressed enter for alpha--agent-one$'
if "$ROOT/bin/ego" press alpha--agent-one arbitrary >/dev/null 2>&1; then
  printf 'press accepted an unrestricted key\n' >&2
  exit 1
fi

onboard_output=$("$ROOT/bin/ego" onboard-workspace alpha)
printf '%s\n' "$onboard_output" | grep -q '^onboarded 1 agents in workspace alpha; 1 already reporting; 0 unavailable$'
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--optimizer/meta"
optimizer_messages_before=$(find "$EGO_HOME/agents/alpha--optimizer/inbox" -maxdepth 1 -name '*.msg' | wc -l | tr -d ' ')
onboard_output=$("$ROOT/bin/ego" onboard-workspace alpha)
printf '%s\n' "$onboard_output" | grep -q '^onboarded 0 agents in workspace alpha; 2 already reporting; 0 unavailable$'
optimizer_messages_after=$(find "$EGO_HOME/agents/alpha--optimizer/inbox" -maxdepth 1 -name '*.msg' | wc -l | tr -d ' ')
test "$optimizer_messages_before" -eq "$optimizer_messages_after"

takeback_output=$("$ROOT/bin/ego" takeback alpha--agent-one)
printf '%s\n' "$takeback_output" | grep -q 'latest report:.*working.*baseline started'
printf '%s\n' "$takeback_output" | grep -q '^reporting remains on$'
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

# Kiro is launchable: the fake kiro-cli stands in for the real binary.
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'sleep 5'
} > "$TMP/fake-bin/kiro-cli"
chmod 700 "$TMP/fake-bin/kiro-cli"
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" spawn kiro-worker --session alpha --root "$TMP" --agent kiro --brief "kiro worker" >/dev/null
grep -q '^agent=kiro$' "$EGO_HOME/agents/alpha--kiro-worker/meta"
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--kiro-worker/meta"
grep -q "^exec kiro-cli chat 'You are worker alpha--kiro-worker" "$EGO_HOME/agents/alpha--kiro-worker/launch.sh"
grep -q "^cd '$TMP'$" "$EGO_HOME/agents/alpha--kiro-worker/launch.sh"
if "$ROOT/bin/ego" spawn bad-agent --session alpha --root "$TMP" --agent gemini >/dev/null 2>&1; then
  printf 'spawn accepted a non-launchable agent\n' >&2
  exit 1
fi
tmux -L "$SOCKET" new-window -d -t alpha: -n kiro-manual -c "$TMP"
"$ROOT/bin/ego" register alpha:kiro-manual --agent kiro >/dev/null
grep -q '^agent=kiro$' "$EGO_HOME/agents/alpha--kiro-manual/meta"
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session alpha --window ego-kiro --agent kiro >/dev/null
grep -q "^exec kiro-cli chat 'You are Sandro'\\\\''s Ego" "$EGO_HOME/controller-launch.sh"
# The controller launches from the session root, not the neutral state directory.
grep -q "^cd '$TMP'$" "$EGO_HOME/controller-launch.sh"
tmux -L "$SOCKET" display-message -p -t "=alpha:ego-kiro" '#{pane_current_path}' | grep -qx "$TMP"
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
"$ROOT/bin/ego" watch 0 | grep -q '^No actionable events within 0 seconds\.$'

# An event that lands between two watch calls is surfaced by the next one.
"$ROOT/bin/ego" report alpha--agent-one blocked "arrived while busy" >/dev/null
"$ROOT/bin/ego" watch 0 | grep -q 'arrived while busy'
"$ROOT/bin/ego" watch 0 | grep -q '^No actionable events within 0 seconds\.$'
test -n "$(find "$EGO_HOME/watch" -name '*.cursor' -print -quit)"

# A live pane whose agent has exited is recorded as having no process.
"$ROOT/bin/ego" scan >/dev/null
grep -q '^process=yes$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^process=no$' "$EGO_HOME/agents/alpha--three/meta"
"$ROOT/bin/ego" list | head -1 | grep -q $'STATE\tPROCESS\tAGENT'
"$ROOT/bin/ego" list | grep 'alpha--three' | grep -q $'live\tno'

tmux -L "$SOCKET" kill-session -t beta
"$ROOT/bin/ego" archive-workspace beta >/dev/null
grep -q '^state=archived$' "$EGO_HOME/workspaces/beta/meta"
if "$ROOT/bin/ego" context | grep -q '^beta'; then
  printf 'archived workspace remained in active context\n' >&2
  exit 1
fi

# A pane id is never reused, so a scan retires the record of a pane that is gone.
tmux -L "$SOCKET" new-window -d -t alpha: -n agent-transient -c "$TMP"
"$ROOT/bin/ego" register alpha:agent-transient --agent kiro >/dev/null
grep -q '^active=yes$' "$EGO_HOME/agents/alpha--agent-transient/meta"
tmux -L "$SOCKET" kill-window -t alpha:agent-transient
"$ROOT/bin/ego" scan | grep -q 'retired [1-9]'
grep -q '^active=no$' "$EGO_HOME/agents/alpha--agent-transient/meta"
grep -q '^last_seen=' "$EGO_HOME/agents/alpha--agent-transient/meta"
"$ROOT/bin/ego" list | grep 'alpha--agent-transient' | grep -q 'missing'
if "$ROOT/bin/ego" list active | grep -q 'alpha--agent-transient'; then
  printf 'retired agent stayed in the active list\n' >&2
  exit 1
fi

# forget retires one record, and only --purge removes it.
"$ROOT/bin/ego" forget alpha--agent-transient | grep -q 'already retired'
"$ROOT/bin/ego" forget alpha--agent-transient --purge >/dev/null
test ! -d "$EGO_HOME/agents/alpha--agent-transient"
if "$ROOT/bin/ego" forget alpha--optimizer --purge >/dev/null 2>&1; then
  printf 'forget purged an agent with a live pane\n' >&2
  exit 1
fi
"$ROOT/bin/ego" forget alpha--optimizer | grep -q '^retired alpha--optimizer'
grep -q '^active=no$' "$EGO_HOME/agents/alpha--optimizer/meta"
"$ROOT/bin/ego" scan >/dev/null
grep -q '^active=no$' "$EGO_HOME/agents/alpha--optimizer/meta"
"$ROOT/bin/ego" register alpha:optimizer >/dev/null
grep -q '^active=yes$' "$EGO_HOME/agents/alpha--optimizer/meta"
# register without --agent must not overwrite the detected agent type
grep -q '^agent=codex$' "$EGO_HOME/agents/alpha--optimizer/meta"

# A killed session keeps its workspace record while the directory survives.
mkdir -p "$TMP/delta"
tmux -L "$SOCKET" new-session -d -s delta -c "$TMP/delta" -n base
"$ROOT/bin/ego" scan >/dev/null
grep -q '^live=yes$' "$EGO_HOME/workspaces/delta/meta"
tmux -L "$SOCKET" kill-session -t delta
"$ROOT/bin/ego" scan >/dev/null
grep -q '^live=no$' "$EGO_HOME/workspaces/delta/meta"
grep -q '^state=active$' "$EGO_HOME/workspaces/delta/meta"
if "$ROOT/bin/ego" context | grep -q '^delta'; then
  printf 'a workspace with no live session stayed in active context\n' >&2
  exit 1
fi
"$ROOT/bin/ego" prune | grep -q 'archived 0 workspace records'
rmdir "$TMP/delta"
"$ROOT/bin/ego" prune | grep -q 'archived 1 workspace records'
grep -q '^state=archived$' "$EGO_HOME/workspaces/delta/meta"
# An explicit archive is not undone by a later scan of a session that lives on.
"$ROOT/bin/ego" archive-workspace gamma >/dev/null
"$ROOT/bin/ego" scan >/dev/null
grep -q '^state=archived$' "$EGO_HOME/workspaces/gamma/meta"

# The controller records its scope, and context honors it.
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'sleep 5'
} > "$TMP/fake-bin/claude"
chmod 700 "$TMP/fake-bin/claude"
mkdir -p "$TMP/epsilon"
tmux -L "$SOCKET" new-session -d -s epsilon -c "$TMP/epsilon" -n base
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session epsilon --window ego \
  | grep -q 'with session scope'
grep -q '^scope=session$' "$EGO_HOME/controller.meta"
grep -q '^exec claude ' "$EGO_HOME/controller-launch.sh"
"$ROOT/bin/ego" context | grep -q '^Scope: session epsilon\.'
if "$ROOT/bin/ego" context | grep -q '^alpha'; then
  printf 'session-scoped context leaked another workspace\n' >&2
  exit 1
fi
"$ROOT/bin/ego" context --all | grep -q '^alpha'
"$ROOT/bin/ego" context --session alpha | grep -q '^alpha'
# A controller sitting in a workspace root itself has no single project.
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session alpha --window ego-server >/dev/null
grep -q '^scope=server$' "$EGO_HOME/controller.meta"
"$ROOT/bin/ego" context | grep -q '^Scope: every session'

printf 'ok\n'
