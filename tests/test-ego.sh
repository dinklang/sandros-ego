#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
SOCKET="ego-test-$$"

test "$(grep -c "printf 'exec codex --sandbox workspace-write --add-dir" "$ROOT/bin/ego")" -eq 1
grep -q "printf 'exec kiro-cli chat" "$ROOT/bin/ego"
# --add-dir is variadic in Claude Code and swallows a trailing prompt.
grep -q "printf 'exec claude %s --add-dir %s" "$ROOT/bin/ego"
grep -q 'Start by running $EGO_CLI_PATH context' "$ROOT/bin/ego"
# The controller inherits its session's workspace root, with the neutral state
# directory only as a fallback.
grep -q 'controller_dir=$(resolve_session_root "$session"' "$ROOT/bin/ego"
grep -q 'controller_dir="$EGO_HOME/controller"' "$ROOT/bin/ego"
# Claude runs the controller by default; Kiro runs the workers.
grep -q 'local session= window=ego agent=claude scope=' "$ROOT/bin/ego"
grep -q 'local name=$1 session= root= id= brief= command_text= agent=kiro' "$ROOT/bin/ego"
# Retirement must survive a rescan, or retire undoes itself.
grep -q "active=\$(meta_get \"\$meta\" active)" "$ROOT/bin/ego"
# display-message needs "=name:"; the bare "=name" form silently returns nothing.
grep -q 'display-message -p -t "=$session:" .#{session_path}.' "$ROOT/bin/ego"
# A stale pane id also makes display-message exit 0 with empty fields.
grep -q "case \"\$out\" in ''|\$'\\\\t'\*) return 1 ;; esac" "$ROOT/bin/ego"
# A session path equal to a workspace root must descend into the session directory.
grep -q 'refine_workspace_root "$session" "$root"' "$ROOT/bin/ego"
grep -Fq 'follow $guide' "$ROOT/bin/ego"
# A controller is a record, so starting one cannot overwrite another's identity.
grep -q 'launch="$CONTROLLERS_DIR/$id/launch.sh"' "$ROOT/bin/ego"
grep -q 'export EGO_CONTROLLER_ID=' "$ROOT/bin/ego"
if grep -q '> "$EGO_HOME/controller.meta"' "$ROOT/bin/ego"; then
  printf 'ego still writes the shared controller.meta\n' >&2
  exit 1
fi
# The scope override must not read as the way out of a refusal.
grep -Fq 'A refusal is not a reason to add it' "$ROOT/CONTROLLER.md"
if grep -q 'new-window.*-c "$REPO_ROOT"' "$ROOT/bin/ego"; then
  printf 'controller still starts in the source repository\n' >&2
  exit 1
fi
grep -q 'Only a controller runs `watch` and the supervision commands' "$ROOT/CONTROLLER.md"
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
# Keep every command away from Sandro's live ~/.ego.
export EGO_ROOT="$TMP/live-root"
export EGO_TMUX_SOCKET="$SOCKET"
export EGO_AGENT_NAVIGATOR="$TMP/fake-agent-navigator"

# install.sh copies the command and the guide, and records where the repository
# is. It runs from any directory and only ever into a temporary root here.
(cd "$TMP" && EGO_ROOT="$TMP/ego-root" EGO_INSTALL_DIR="$TMP/install" bash "$ROOT/install.sh") \
  | grep -qx "installed Ego at $TMP/install/ego"
test -n "$(find "$TMP/install/ego" -perm 755)"
cmp -s "$ROOT/bin/ego" "$TMP/install/ego"
test "$(cat "$TMP/install/repo-root")" = "$ROOT"
test -n "$(find "$TMP/ego-root/CONTROLLER.md" -perm 644)"
cmp -s "$ROOT/CONTROLLER.md" "$TMP/ego-root/CONTROLLER.md"
test ! -e "$TMP/ego-root/bin"
test -z "$(find "$TMP/install" -name '.repo-root.*')"
# EGO_ROOT alone moves both defaults; EGO_CONTROLLER_GUIDE moves the guide.
EGO_ROOT="$TMP/ego-root2" EGO_CONTROLLER_GUIDE="$TMP/guide/guide.md" bash "$ROOT/install.sh" >/dev/null
test -x "$TMP/ego-root2/bin/ego"
test -f "$TMP/guide/guide.md"
test ! -e "$TMP/ego-root2/CONTROLLER.md"
# help lists exactly the current commands.
help_commands=$("$TMP/install/ego" help | awk '$1 == "ego" { print $2 }' | sort -u | paste -sd' ' -)
test "$help_commands" = "context handback handoff inbox list onboard peek press report reset retire scope send spawn start watch"
# Every removed command, older alias, and fold fails as unknown, for any caller.
for removed in ack inspect offboard scan register purge install takeback handoff-workspace \
  takeback-workspace onboard-workspace session-start status recover forget prune archive-workspace \
  controllers workspaces promote checkpoint stow init; do
  if "$ROOT/bin/ego" "$removed" >/dev/null 2>&1; then
    printf 'ego %s still runs\n' "$removed" >&2
    exit 1
  fi
  "$ROOT/bin/ego" "$removed" x 2>&1 >/dev/null | grep -q "^error: unknown command '$removed'$"
  EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" "$removed" 2>&1 >/dev/null | grep -q "^error: unknown command '$removed'$"
done
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

"$ROOT/bin/ego" context >/dev/null

test -f "$EGO_HOME/agents/alpha--agent-one/meta"
test -f "$EGO_HOME/agents/beta--agent-two/meta"
test -f "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^origin=human$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^kind=primary$' "$EGO_HOME/workspaces/alpha/meta"

"$ROOT/bin/ego" handoff alpha--agent-one --summary "profiling is active" --next "collect a baseline" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/alpha--agent-one/meta"
grep -q 'profiling is active' "$EGO_HOME/agents/alpha--agent-one/handoff.md"
# The note records the worker's live state, whatever the summary says.
grep -q '^## Worker state at handoff$' "$EGO_HOME/agents/alpha--agent-one/handoff.md"
grep -q '^Latest report: none recorded$' "$EGO_HOME/agents/alpha--agent-one/handoff.md"
grep -q '^Agent process: yes$' "$EGO_HOME/agents/alpha--agent-one/handoff.md"
grep -q '^Observed screen: idle$' "$EGO_HOME/agents/alpha--agent-one/handoff.md"
grep -q '^Last 20 pane lines:$' "$EGO_HOME/agents/alpha--agent-one/handoff.md"
tmux -L "$SOCKET" send-keys -t alpha:agent-one 'echo long-running-marker' Enter
for _ in $(seq 1 50); do
  tmux -L "$SOCKET" capture-pane -p -t alpha:agent-one | grep -qx 'long-running-marker' && break
  sleep 0.1
done
handoff_output=$("$ROOT/bin/ego" handoff alpha--agent-one --summary "profiling is active" --next "collect a baseline")
printf '%s\n' "$handoff_output" | grep -q '^handed off alpha--agent-one to Ego$'
printf '%s\n' "$handoff_output" | grep -q '^long-running-marker$'
grep -q '^long-running-marker$' "$EGO_HOME/agents/alpha--agent-one/handoff.md"

"$ROOT/bin/ego" report alpha--agent-one working "baseline started" >/dev/null
grep -q $'\tworking\tbaseline started$' "$EGO_HOME/agents/alpha--agent-one/status.log"
"$ROOT/bin/ego" report alpha--agent-one validating "checking output" >/dev/null
grep -q $'\tworking\tchecking output$' "$EGO_HOME/agents/alpha--agent-one/status.log"
"$ROOT/bin/ego" report alpha--agent-one waiting "no assignment" >/dev/null
grep -q $'\tidle\tno assignment$' "$EGO_HOME/agents/alpha--agent-one/status.log"
"$ROOT/bin/ego" report alpha--agent-one working "baseline started" >/dev/null

# peek prints the handoff note while Ego owns the agent, the latest report, and
# the last pane lines, but not the handoff's own older pane snapshot.
peek_output=$("$ROOT/bin/ego" peek alpha--agent-one)
printf '%s\n' "$peek_output" | grep -q '^# alpha--agent-one$'
printf '%s\n' "$peek_output" | grep -q '^## Next action$'
printf '%s\n' "$peek_output" | grep -q '^collect a baseline$'
printf '%s\n' "$peek_output" | grep -q '^Latest report: .* working baseline started$'
printf '%s\n' "$peek_output" | grep -q '^Last 60 pane lines:$'
printf '%s\n' "$peek_output" | grep -q '^long-running-marker$'
if printf '%s\n' "$peek_output" | grep -q '^## Worker state at handoff$'; then
  printf 'peek repeated the handoff snapshot\n' >&2
  exit 1
fi
"$ROOT/bin/ego" peek alpha:agent-one 5 | grep -q '^Last 5 pane lines:$'

"$ROOT/bin/ego" onboard alpha--agent-one >/dev/null
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--agent-one/meta"
message=$(find "$EGO_HOME/agents/alpha--agent-one/inbox" -maxdepth 1 -name '*.msg' -exec basename {} .msg \; | head -1)
test -n "$message"
# Reading the inbox handles what it lists, so nothing is left to acknowledge.
# Capture first: grep -q would close the pipe before the read finished.
inbox_output=$("$ROOT/bin/ego" inbox alpha--agent-one)
printf '%s\n' "$inbox_output" | grep -q "^MESSAGE $message$"
test -f "$EGO_HOME/agents/alpha--agent-one/inbox/handled/$message.msg"
test ! -f "$EGO_HOME/agents/alpha--agent-one/inbox/$message.msg"
grep -q $'\thandled\talpha--agent-one\t'"$message"$'\talpha$' "$EGO_HOME/events.log"
"$ROOT/bin/ego" inbox alpha--agent-one | grep -q '^No pending messages\.$'
"$ROOT/bin/ego" press alpha--agent-one enter | grep -q '^pressed enter for alpha--agent-one$'
if "$ROOT/bin/ego" press alpha--agent-one arbitrary >/dev/null 2>&1; then
  printf 'press accepted an unrestricted key\n' >&2
  exit 1
fi

# An unknown agent id must fail loudly. An empty tmux target resolves to the
# caller's own pane, so a lookup failure that fell through would make Ego type
# into itself. 'die' cannot prevent that on its own: bash ignores set -e inside
# the command substitutions these callers use.
if "$ROOT/bin/ego" send no-such-agent hello >/dev/null 2>&1; then
  printf 'send accepted an unknown agent id\n' >&2
  exit 1
fi
if "$ROOT/bin/ego" peek no-such-agent >/dev/null 2>&1; then
  printf 'peek accepted an unknown agent id\n' >&2
  exit 1
fi
if "$ROOT/bin/ego" onboard no-such-agent >/dev/null 2>&1; then
  printf 'onboard accepted an unknown agent id\n' >&2
  exit 1
fi
if grep -q 'no-such-agent' "$EGO_HOME/events.log"; then
  printf 'a failed send recorded an event\n' >&2
  exit 1
fi
# A recorded agent whose pane id is empty must not reach tmux either.
"$ROOT/bin/ego" onboard alpha:agent-one --id paneless >/dev/null
grep -q '^window=agent-one$' "$EGO_HOME/agents/paneless/meta"
sed -i 's/^pane_id=.*/pane_id=/' "$EGO_HOME/agents/paneless/meta"
if "$ROOT/bin/ego" send paneless hello >/dev/null 2>&1; then
  printf 'send reached an agent with no recorded pane\n' >&2
  exit 1
fi
if "$ROOT/bin/ego" peek paneless | grep -q 'pane lines:$'; then
  printf 'peek reached an agent with no recorded pane\n' >&2
  exit 1
fi
"$ROOT/bin/ego" peek paneless | grep -q '^Pane: gone$'
if "$ROOT/bin/ego" press paneless enter >/dev/null 2>&1; then
  printf 'press reached an agent with no recorded pane\n' >&2
  exit 1
fi
rm -rf "$EGO_HOME/agents/paneless"
# meta_get on a missing file must return empty instead of blocking on stdin.
test -z "$("$ROOT/bin/ego" peek no-such-agent 2>/dev/null </dev/null || true)"

onboard_output=$("$ROOT/bin/ego" onboard alpha:)
printf '%s\n' "$onboard_output" | grep -q '^onboarded 1 agents in workspace alpha; 1 already reporting; 0 unavailable$'
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--optimizer/meta"
optimizer_messages_before=$(find "$EGO_HOME/agents/alpha--optimizer/inbox" -maxdepth 1 -name '*.msg' | wc -l | tr -d ' ')
onboard_output=$("$ROOT/bin/ego" onboard alpha:)
printf '%s\n' "$onboard_output" | grep -q '^onboarded 0 agents in workspace alpha; 2 already reporting; 0 unavailable$'
optimizer_messages_after=$(find "$EGO_HOME/agents/alpha--optimizer/inbox" -maxdepth 1 -name '*.msg' | wc -l | tr -d ' ')
test "$optimizer_messages_before" -eq "$optimizer_messages_after"

handback_output=$("$ROOT/bin/ego" handback alpha--agent-one)
printf '%s\n' "$handback_output" | grep -q 'latest report:.*working.*baseline started'
printf '%s\n' "$handback_output" | grep -q '^reporting remains on$'
printf '%s\n' "$handback_output" | grep -q '^Last 60 pane lines:$'
grep -q $'\thandback\talpha--agent-one\t' "$EGO_HOME/events.log"
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--agent-one/meta"
"$ROOT/bin/ego" handoff agent-one --session alpha --summary "short selector" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/alpha--agent-one/meta"
"$ROOT/bin/ego" handback agent-one --session alpha >/dev/null
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--agent-one/meta"
alpha_pane=$(tmux -L "$SOCKET" list-panes -t alpha:agent-one -F '#{pane_id}')
TMUX=test TMUX_PANE="$alpha_pane" "$ROOT/bin/ego" handoff agent-one --summary "current session selector" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/alpha--agent-one/meta"
TMUX=test TMUX_PANE="$alpha_pane" "$ROOT/bin/ego" handback agent-one >/dev/null
grep -q '^owner=human$' "$EGO_HOME/agents/alpha--agent-one/meta"

# A session: target hands off or back every active agent in a workspace.
handoff_output=$("$ROOT/bin/ego" handoff beta: --summary "delegate beta" --next "collect results")
printf '%s\n' "$handoff_output" | grep -q '^handed workspace beta and 1 registered agents to Ego$'
printf '%s\n' "$handoff_output" | grep -q '^beta--agent-two: process=yes, latest report: none$'
grep -q '^owner=ego$' "$EGO_HOME/agents/beta--agent-two/meta"
grep -q '^## Worker state at handoff$' "$EGO_HOME/agents/beta--agent-two/handoff.md"
grep -q '^delegate beta$' "$EGO_HOME/agents/beta--agent-two/handoff.md"
grep -q '^Mode: handoff$' "$EGO_HOME/workspaces/beta/checkpoint.md"
"$ROOT/bin/ego" context --full --session beta | grep -q '^collect results$'
"$ROOT/bin/ego" handback beta: | grep -q '^returned workspace beta and 1 registered agents to human control$'
grep -q $'\tworkspace-handback\tbeta\t' "$EGO_HOME/events.log"
grep -q '^owner=human$' "$EGO_HOME/agents/beta--agent-two/meta"
"$ROOT/bin/ego" handoff beta:agent-two --summary "one agent by session:window" >/dev/null
grep -q '^owner=ego$' "$EGO_HOME/agents/beta--agent-two/meta"
"$ROOT/bin/ego" handback beta:agent-two | grep -q '^returned beta--agent-two to human control$'
grep -q '^owner=human$' "$EGO_HOME/agents/beta--agent-two/meta"

# onboard registers a window Ego has no record of, and --off reverses it
# without retiring the record.
tmux -L "$SOCKET" new-window -d -t beta: -n late -c "$TMP"
"$ROOT/bin/ego" onboard beta:late | grep -q '^onboarded beta--late with message '
grep -q '^reporting=on$' "$EGO_HOME/agents/beta--late/meta"
"$ROOT/bin/ego" inbox beta--late >/dev/null
"$ROOT/bin/ego" onboard beta:late --off | grep -q '^turned reporting off for beta--late with message '
grep -q '^reporting=off$' "$EGO_HOME/agents/beta--late/meta"
grep -q '^active=yes$' "$EGO_HOME/agents/beta--late/meta"
grep -q '^owner=human$' "$EGO_HOME/agents/beta--late/meta"
inbox_output=$("$ROOT/bin/ego" inbox beta--late)
printf '%s\n' "$inbox_output" | grep -q "^Leave Ego's reporting protocol"
grep -q $'\treporting-off\tbeta--late\t' "$EGO_HOME/events.log"
for bad_off in "beta: --off" "beta:late --off --agent kiro"; do
  # shellcheck disable=SC2086
  if "$ROOT/bin/ego" onboard $bad_off >/dev/null 2>&1; then
    printf 'onboard accepted %s\n' "$bad_off" >&2
    exit 1
  fi
done
tmux -L "$SOCKET" kill-window -t beta:late

# Worker names stay short role names.
for bad_name in availability-zone-analysis-worker AZ-analyzer az_analyzer a-very-long-worker-name-x; do
  if "$ROOT/bin/ego" spawn "$bad_name" --session alpha --root "$TMP" --command 'sleep 5' >/dev/null 2>&1; then
    printf 'spawn accepted the worker name %s\n' "$bad_name" >&2
    exit 1
  fi
done
"$ROOT/bin/ego" spawn --help | grep -q 'az-analyzer or stt-research'

"$ROOT/bin/ego" context --full | grep -q '^# Recovery view$'

test ! -e "$EGO_ROOT/bin/ego"
"$ROOT/bin/ego" spawn three --session alpha --root "$TMP" --command 'sleep 5' --brief "test worker" >/dev/null 2>&1
# The first spawn or start installs Ego when no installed copy exists yet.
test -x "$EGO_ROOT/bin/ego"
cmp -s "$ROOT/bin/ego" "$EGO_ROOT/bin/ego"
test -f "$EGO_ROOT/CONTROLLER.md"
# That first install goes through install.sh, which also records the repository.
test "$(cat "$EGO_ROOT/bin/repo-root")" = "$ROOT"
# The installed copy warns when it no longer matches its repository.
if "$EGO_ROOT/bin/ego" context 2>&1 >/dev/null | grep -q 'installed Ego differs'; then
  printf 'a matching installed copy reported drift\n' >&2
  exit 1
fi
printf '\n' >> "$EGO_ROOT/CONTROLLER.md"
"$EGO_ROOT/bin/ego" context 2>&1 >/dev/null | grep -q "installed Ego differs from $ROOT; run ./install.sh there"
bash "$ROOT/install.sh" >/dev/null
if "$EGO_ROOT/bin/ego" context 2>&1 >/dev/null | grep -q 'installed Ego differs'; then
  printf 'a reinstalled copy still reported drift\n' >&2
  exit 1
fi
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
"$ROOT/bin/ego" context >/dev/null
grep -q '^branch=ego/alpha--isolated$' "$EGO_HOME/agents/alpha--isolated/meta"
grep -q "^root=$EGO_HOME/worktrees/alpha--isolated$" "$EGO_HOME/agents/alpha--isolated/meta"

"$ROOT/bin/ego" list | grep -q 'alpha--three'

# Kiro is launchable: the fake kiro-cli stands in for the real binary.
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'sleep 600'
} > "$TMP/fake-bin/kiro-cli"
chmod 700 "$TMP/fake-bin/kiro-cli"
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" spawn kiro-worker --session alpha --root "$TMP" --agent kiro --brief "kiro worker" >/dev/null
grep -q '^agent=kiro$' "$EGO_HOME/agents/alpha--kiro-worker/meta"
grep -q '^reporting=on$' "$EGO_HOME/agents/alpha--kiro-worker/meta"
grep -q "^exec kiro-cli chat 'You are worker alpha--kiro-worker" "$EGO_HOME/agents/alpha--kiro-worker/launch.sh"
# The launch prompt only points at context, which carries the protocol.
grep -q "Run $EGO_ROOT/bin/ego context now" "$EGO_HOME/agents/alpha--kiro-worker/launch.sh"
if grep -q 'report alpha--kiro-worker' "$EGO_HOME/agents/alpha--kiro-worker/launch.sh"; then
  printf 'the launch prompt still embeds the reporting protocol\n' >&2
  exit 1
fi
grep -q "^cd '$TMP'$" "$EGO_HOME/agents/alpha--kiro-worker/launch.sh"
if "$ROOT/bin/ego" spawn bad-agent --session alpha --root "$TMP" --agent gemini >/dev/null 2>&1; then
  printf 'spawn accepted a non-launchable agent\n' >&2
  exit 1
fi
tmux -L "$SOCKET" new-window -d -t alpha: -n kiro-manual -c "$TMP"
"$ROOT/bin/ego" onboard alpha:kiro-manual --agent kiro >/dev/null
grep -q '^agent=kiro$' "$EGO_HOME/agents/alpha--kiro-manual/meta"
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session alpha --window ego-kiro --agent kiro >/dev/null
grep -q "^exec kiro-cli chat 'You are Sandro'\\\\''s Ego" "$EGO_HOME/controllers/alpha--ego-kiro/launch.sh"
# The controller launches from the session root, not the neutral state directory.
grep -q "^cd '$TMP'$" "$EGO_HOME/controllers/alpha--ego-kiro/launch.sh"
# The same script resumes the previous conversation with --continue.
grep -q '^  exec kiro-cli chat --resume$' "$EGO_HOME/controllers/alpha--ego-kiro/launch.sh"
# The launch script restores this controller's own identity when re-run in place.
grep -q "^export EGO_CONTROLLER_ID='alpha--ego-kiro'$" "$EGO_HOME/controllers/alpha--ego-kiro/launch.sh"
# A controller covers its own session unless told otherwise.
grep -q '^scope=alpha$' "$EGO_HOME/controllers/alpha--ego-kiro/meta"
tmux -L "$SOCKET" display-message -p -t "=alpha:ego-kiro" '#{pane_current_path}' | grep -qx "$TMP"
"$ROOT/bin/ego" list --controllers | grep 'alpha--ego-kiro' | grep -q $'alpha\tyes\tlive'
"$ROOT/bin/ego" context | grep -q "Sandro's Ego context"
# A controller pane is a controller, never also a worker record: onboarding one
# as a worker is undone by the next scan.
"$ROOT/bin/ego" onboard alpha:ego-kiro >/dev/null
grep -q '^active=yes$' "$EGO_HOME/agents/alpha--ego-kiro/meta"
"$ROOT/bin/ego" context >/dev/null
grep -q '^active=no$' "$EGO_HOME/agents/alpha--ego-kiro/meta"
if "$ROOT/bin/ego" list active | grep -q 'alpha--ego-kiro'; then
  printf 'a controller pane stayed in the active worker list\n' >&2
  exit 1
fi

(
  sleep 1
  "$ROOT/bin/ego" report alpha--agent-one working "quiet progress" >/dev/null
  sleep 1
  "$ROOT/bin/ego" report alpha--agent-one done "actionable completion" >/dev/null
) &
reporter=$!
watch_output=$("$ROOT/bin/ego" watch 5)
wait "$reporter"
printf '%s\n' "$watch_output" | grep -q $'\tdone\talpha--agent-one\tactionable completion\talpha$'
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
"$ROOT/bin/ego" context >/dev/null
grep -q '^process=yes$' "$EGO_HOME/agents/alpha--optimizer/meta"
grep -q '^process=no$' "$EGO_HOME/agents/alpha--three/meta"
"$ROOT/bin/ego" list | head -1 | grep -q $'STATE\tPROCESS\tAGENT'
"$ROOT/bin/ego" list | grep 'alpha--three' | grep -q $'live\tno'
# An open pane with no agent is a cleanup candidate that scan never retires.
"$ROOT/bin/ego" list --stale | grep 'alpha--three' | grep -q $'no agent process\talpha:three\ttmux kill-window -t @'
# A scan that changes nothing leaves no event.
scans_before=$(grep -c $'\tscan\t' "$EGO_HOME/events.log")
"$ROOT/bin/ego" context >/dev/null
test "$(grep -c $'\tscan\t' "$EGO_HOME/events.log")" -eq "$scans_before"

tmux -L "$SOCKET" kill-session -t beta
"$ROOT/bin/ego" retire beta: | grep -q '^retired 1 agent records in workspace beta$'
grep -q '^active=no$' "$EGO_HOME/agents/beta--agent-two/meta"
if "$ROOT/bin/ego" context | grep -q '^beta'; then
  printf 'a workspace with no live session remained in active context\n' >&2
  exit 1
fi

# A pane id is never reused, so a scan retires the record of a pane that is gone.
tmux -L "$SOCKET" new-window -d -t alpha: -n agent-transient -c "$TMP"
"$ROOT/bin/ego" onboard alpha:agent-transient --agent kiro >/dev/null
grep -q '^active=yes$' "$EGO_HOME/agents/alpha--agent-transient/meta"
tmux -L "$SOCKET" kill-window -t alpha:agent-transient
"$ROOT/bin/ego" context >/dev/null
grep -q '^active=no$' "$EGO_HOME/agents/alpha--agent-transient/meta"
grep -q '^last_seen=' "$EGO_HOME/agents/alpha--agent-transient/meta"
"$ROOT/bin/ego" list | grep 'alpha--agent-transient' | grep -q 'missing'
if "$ROOT/bin/ego" list active | grep -q 'alpha--agent-transient'; then
  printf 'retired agent stayed in the active list\n' >&2
  exit 1
fi

# A context read joins tmux first, so a dead pane leaves context without a scan.
tmux -L "$SOCKET" new-window -d -t alpha: -n agent-ctx -c "$TMP"
"$ROOT/bin/ego" onboard alpha:agent-ctx --agent kiro >/dev/null
tmux -L "$SOCKET" kill-window -t alpha:agent-ctx
if "$ROOT/bin/ego" context | grep -q 'alpha--agent-ctx'; then
  printf 'context showed an agent whose pane is gone\n' >&2
  exit 1
fi
grep -q '^active=no$' "$EGO_HOME/agents/alpha--agent-ctx/meta"

# retire marks one record inactive, and only retire --purge removes it.
"$ROOT/bin/ego" retire alpha--agent-transient | grep -q 'already retired'
"$ROOT/bin/ego" retire --purge alpha--agent-transient | grep -q '^purged the record for alpha--agent-transient$'
test ! -d "$EGO_HOME/agents/alpha--agent-transient"
grep -q $'\tpurged\talpha--agent-transient\t' "$EGO_HOME/events.log"
"$ROOT/bin/ego" retire alpha:agent-ctx --purge 2>&1 | grep -q 'put --purge first: ego retire --purge <id>'
test -d "$EGO_HOME/agents/alpha--agent-ctx"
"$ROOT/bin/ego" retire --purge alpha:agent-ctx >/dev/null
test ! -d "$EGO_HOME/agents/alpha--agent-ctx"
if "$ROOT/bin/ego" retire --purge alpha--optimizer >/dev/null 2>&1; then
  printf 'retire --purge removed an agent with a live pane\n' >&2
  exit 1
fi
test -f "$EGO_HOME/agents/alpha--optimizer/meta"
for bad_purge in "--purge alpha:" "--purge --stale" "--purge" "--purge --controller alpha--ego-kiro"; do
  # shellcheck disable=SC2086
  if "$ROOT/bin/ego" retire $bad_purge >/dev/null 2>&1; then
    printf 'retire accepted %s\n' "$bad_purge" >&2
    exit 1
  fi
done
"$ROOT/bin/ego" retire alpha:optimizer | grep -q '^retired alpha--optimizer'
grep -q '^active=no$' "$EGO_HOME/agents/alpha--optimizer/meta"
"$ROOT/bin/ego" context >/dev/null
grep -q '^active=no$' "$EGO_HOME/agents/alpha--optimizer/meta"
"$ROOT/bin/ego" onboard alpha:optimizer >/dev/null
grep -q '^active=yes$' "$EGO_HOME/agents/alpha--optimizer/meta"
# onboard without --agent must not overwrite the detected agent type
grep -q '^agent=codex$' "$EGO_HOME/agents/alpha--optimizer/meta"

# A killed session keeps its workspace record while the directory survives.
mkdir -p "$TMP/delta"
tmux -L "$SOCKET" new-session -d -s delta -c "$TMP/delta" -n base
"$ROOT/bin/ego" context >/dev/null
grep -q '^live=yes$' "$EGO_HOME/workspaces/delta/meta"
tmux -L "$SOCKET" kill-session -t delta
"$ROOT/bin/ego" context >/dev/null
grep -q '^live=no$' "$EGO_HOME/workspaces/delta/meta"
if "$ROOT/bin/ego" context | grep -q '^delta'; then
  printf 'a workspace with no live session stayed in active context\n' >&2
  exit 1
fi
"$ROOT/bin/ego" list --workspaces | grep -q $'^delta\tprimary\tno\t'
# retire --stale takes every cleanup candidate.
"$ROOT/bin/ego" retire --stale | grep -q '^retired [0-9]* stale agent records$'
"$ROOT/bin/ego" retire --stale | grep -q '^retired 0 stale agent records$'
# Retiring a workspace's agents is not undone by a later scan.
tmux -L "$SOCKET" new-window -d -t gamma: -n agent-gamma -c "$TMP"
"$ROOT/bin/ego" context >/dev/null
grep -q '^active=yes$' "$EGO_HOME/agents/gamma--agent-gamma/meta"
"$ROOT/bin/ego" retire gamma: >/dev/null
"$ROOT/bin/ego" context >/dev/null
grep -q '^active=no$' "$EGO_HOME/agents/gamma--agent-gamma/meta"

# Each controller has its own record, so starting one changes nothing about
# another, and scope resolves from the caller rather than a shared file.
{
  printf '%s\n' '#!/usr/bin/env bash'
  printf '%s\n' 'sleep 600'
} > "$TMP/fake-bin/claude"
chmod 700 "$TMP/fake-bin/claude"
mkdir -p "$TMP/epsilon" "$TMP/zeta"
tmux -L "$SOCKET" new-session -d -s epsilon -c "$TMP/epsilon" -n base
tmux -L "$SOCKET" new-session -d -s zeta -c "$TMP/zeta" -n base
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session epsilon --window ego \
  | grep -q 'started Ego epsilon--ego .* covering epsilon$'
grep -q '^scope=epsilon$' "$EGO_HOME/controllers/epsilon--ego/meta"
grep -q '^exec claude ' "$EGO_HOME/controllers/epsilon--ego/launch.sh"
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session zeta --window ego >/dev/null
grep -q '^scope=zeta$' "$EGO_HOME/controllers/zeta--ego/meta"
# Starting the second controller left the first one alone.
grep -q '^session=epsilon$' "$EGO_HOME/controllers/epsilon--ego/meta"
grep -q '^scope=epsilon$' "$EGO_HOME/controllers/epsilon--ego/meta"

context_epsilon=$(EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" context)
printf '%s\n' "$context_epsilon" | grep -q '^Scope: session epsilon\.'
if printf '%s\n' "$context_epsilon" | grep -q '^zeta'; then
  printf 'session-scoped context leaked another workspace\n' >&2
  exit 1
fi
context_zeta=$(EGO_CONTROLLER_ID=zeta--ego "$ROOT/bin/ego" context)
printf '%s\n' "$context_zeta" | grep -q '^Scope: session zeta\.'
if printf '%s\n' "$context_zeta" | grep -q '^epsilon'; then
  printf 'session-scoped context leaked another workspace\n' >&2
  exit 1
fi
# Neither controller appears in the other's agent list.
if printf '%s\n' "$context_epsilon" | grep -q 'zeta--ego'; then
  printf 'a controller appeared in another controller context\n' >&2
  exit 1
fi
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" context --all | grep -q '^alpha'
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" context --session alpha | grep -q '^alpha'
# A human in a plain shell has server scope.
"$ROOT/bin/ego" context | grep -q '^Scope: every session'
# A controller over several workspaces lists them explicitly.
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session alpha --window ego-multi --scope alpha,zeta >/dev/null
grep -q '^scope=alpha,zeta$' "$EGO_HOME/controllers/alpha--ego-multi/meta"
context_multi=$(EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" context)
printf '%s\n' "$context_multi" | grep -q '^Scope: sessions alpha, zeta\.'
printf '%s\n' "$context_multi" | grep -q '^zeta'
if printf '%s\n' "$context_multi" | grep -q '^epsilon'; then
  printf 'a multi-session scope leaked a workspace it does not list\n' >&2
  exit 1
fi
EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" scope | grep -qx 'alpha, zeta'
# Adding a workspace is Sandro's decision, never the controller's own.
if EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" scope +epsilon >/dev/null 2>&1; then
  printf 'a controller widened its own scope\n' >&2
  exit 1
fi
"$ROOT/bin/ego" scope alpha--ego-multi +epsilon 2>"$TMP/overlap.err" | grep -q 'now covers alpha, zeta, epsilon$'
# Two live controllers covering one session both wake for it, so Ego says so.
grep -q 'epsilon is also covered by live controller epsilon--ego' "$TMP/overlap.err"
EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" scope -zeta | grep -q 'now covers alpha, epsilon$'
"$ROOT/bin/ego" scope alpha--ego-multi alpha,zeta >/dev/null
grep -q '^scope=alpha,zeta$' "$EGO_HOME/controllers/alpha--ego-multi/meta"
if EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" scope -alpha,zeta >/dev/null 2>&1; then
  printf 'scope accepted an empty session list\n' >&2
  exit 1
fi
# A controller that creates a new workspace keeps reach over it.
EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" spawn made --session theta --command 'sleep 600' >/dev/null
grep -q '^scope=alpha,zeta,theta$' "$EGO_HOME/controllers/alpha--ego-multi/meta"
# A multi-session watch wakes for any listed session and no other.
EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" watch 0 >/dev/null
"$ROOT/bin/ego" report theta--made blocked "listed session is stuck" >/dev/null
EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" watch 0 | grep -q 'listed session is stuck'

# reset writes the workspace note for every covered session and prints how to
# restart; it never ends the controller's process itself.
reset_output=$("$ROOT/bin/ego" reset alpha--ego-multi --note "carry this across the reset")
printf '%s\n' "$reset_output" | grep -q '^wrote the workspace note for alpha, zeta, theta$'
printf '%s\n' "$reset_output" | grep -q "controllers/alpha--ego-multi/launch.sh' --continue"
grep -q '^Mode: reset$' "$EGO_HOME/workspaces/zeta/checkpoint.md"
EGO_CONTROLLER_ID=alpha--ego-multi "$ROOT/bin/ego" context | grep -q '^carry this across the reset$'
tmux -L "$SOCKET" list-windows -t alpha -F '#{window_name}' | grep -qx ego-multi
if EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" reset zeta--ego >/dev/null 2>&1; then
  printf 'a controller reset another controller\n' >&2
  exit 1
fi
# start --continue resumes through the same launch script.
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session zeta --window ego-resumed --continue 2>/dev/null \
  | grep -q 'started Ego zeta--ego-resumed'

# Scope is a boundary, not only a display filter.
if EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" peek alpha--agent-one >/dev/null 2>&1; then
  printf 'a session-scoped controller peeked into another workspace\n' >&2
  exit 1
fi
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" peek alpha--agent-one --any-session >/dev/null
if EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" spawn intruder --session alpha --root "$TMP" --command 'sleep 5' >/dev/null 2>&1; then
  printf 'a session-scoped controller spawned into another workspace\n' >&2
  exit 1
fi
test ! -d "$EGO_HOME/agents/alpha--intruder"
if EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" handoff alpha: --summary out-of-scope >/dev/null 2>&1; then
  printf 'a session-scoped controller handed off another workspace\n' >&2
  exit 1
fi
# A refused onboard leaves no record behind.
if EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" onboard alpha:base >/dev/null 2>&1; then
  printf 'a session-scoped controller onboarded a window elsewhere\n' >&2
  exit 1
fi
test ! -d "$EGO_HOME/agents/alpha--base"
# A worker is scoped to its own session for the same reason.
if EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" send beta--agent-two hello >/dev/null 2>&1; then
  printf 'a worker reached a sibling in another workspace\n' >&2
  exit 1
fi
EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" report alpha--three note "self report is exempt" >/dev/null
# A worker reports and reads its inbox only for itself, and its own id is
# implied.
EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" report note "implied id" | grep -q '^recorded note for alpha--three$'
grep -q $'\tnote\timplied id$' "$EGO_HOME/agents/alpha--three/status.log"
if EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" report alpha--agent-one done "impersonated" >/dev/null 2>&1; then
  printf 'a worker reported under another agent id\n' >&2
  exit 1
fi
if grep -q 'impersonated' "$EGO_HOME/events.log"; then
  printf 'a refused report still reached the event log\n' >&2
  exit 1
fi
EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" inbox | grep -q '^No pending messages\.$'
three_message=$("$ROOT/bin/ego" send alpha--three "worker instruction" | awk '{ print $2 }')
inbox_output=$(EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" inbox)
printf '%s\n' "$inbox_output" | grep -q "^MESSAGE $three_message$"
test -f "$EGO_HOME/agents/alpha--three/inbox/handled/$three_message.msg"
EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" inbox | grep -q '^No pending messages\.$'
if EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" inbox alpha--agent-one >/dev/null 2>&1; then
  printf 'a worker read another agent inbox\n' >&2
  exit 1
fi
# Supervision commands belong to controllers and Sandro.
for worker_command in "handoff alpha--agent-one --summary x" "handback alpha--agent-one" \
  "press alpha--agent-one enter" "watch 0" "scope" "retire alpha--agent-one" \
  "spawn helper --command true" "start"; do
  # shellcheck disable=SC2086
  if EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" $worker_command >/dev/null 2>&1; then
    printf 'a worker ran ego %s\n' "$worker_command" >&2
    exit 1
  fi
done
EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" handoff alpha--agent-one --summary x 2>&1 \
  | grep -q "'ego handoff' is not available to a worker"
if EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" context --all >/dev/null 2>&1; then
  printf 'a worker read every workspace\n' >&2
  exit 1
fi
# A worker's context is its own: who it is, how to report, its brief, and its
# pending instructions.
context_message=$("$ROOT/bin/ego" send alpha--three "context instruction" | awk '{ print $2 }')
# Sandro looking at a worker's context leaves its messages pending.
"$ROOT/bin/ego" context --agent alpha--three | grep -q "^MESSAGE $context_message$"
test -f "$EGO_HOME/agents/alpha--three/inbox/$context_message.msg"
worker_context=$(EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" context)
printf '%s\n' "$worker_context" | grep -q "^MESSAGE $context_message$"
test ! -f "$EGO_HOME/agents/alpha--three/inbox/$context_message.msg"
test -f "$EGO_HOME/agents/alpha--three/inbox/handled/$context_message.msg"
grep -q $'\thandled\talpha--three\t'"$context_message" "$EGO_HOME/events.log"
EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" inbox | grep -q '^No pending messages\.$'
printf '%s\n' "$worker_context" | grep -q '^Worker: alpha--three$'
printf '%s\n' "$worker_context" | grep -q '^## How to report$'
printf '%s\n' "$worker_context" | grep -q 'report alpha--three <working|idle|blocked|needs-decision|done|failed|note> <message>$'
printf '%s\n' "$worker_context" | grep -q '^test worker$'
printf '%s\n' "$worker_context" | grep -q '^## Other agents in this workspace$'
printf '%s\n' "$worker_context" | grep -q 'Reading them marks them handled:$'
if printf '%s\n' "$worker_context" | grep -qw 'ack'; then
  printf 'the worker contract still asks for an acknowledgement\n' >&2
  exit 1
fi
if EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" context --agent alpha--agent-one >/dev/null 2>&1; then
  printf 'a worker read another worker context\n' >&2
  exit 1
fi
# An onboarded agent names itself, since Ego did not launch it.
"$ROOT/bin/ego" context --agent alpha--agent-one | grep -q '^Worker: alpha--agent-one$'
grep -rq 'context --agent alpha--agent-one now' "$EGO_HOME/agents/alpha--agent-one/inbox"
if EGO_AGENT_ID=alpha--three "$ROOT/bin/ego" peek alpha--agent-one --any-session >/dev/null 2>&1; then
  printf 'a worker used --any-session\n' >&2
  exit 1
fi
# A controller cannot start another controller.
if EGO_CONTROLLER_ID=epsilon--ego PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session epsilon --window ego2 >/dev/null 2>&1; then
  printf 'a controller started another controller\n' >&2
  exit 1
fi

# Widening a scope is a field write, not a restart.
"$ROOT/bin/ego" scope epsilon--ego +alpha 2>/dev/null | grep -q 'now covers epsilon, alpha$'
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" context | grep -q '^Scope: sessions '
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" peek alpha--agent-one >/dev/null
"$ROOT/bin/ego" scope epsilon--ego epsilon >/dev/null
grep -q '^scope=epsilon$' "$EGO_HOME/controllers/epsilon--ego/meta"

# Events carry a session, so a session-scoped controller wakes only for its own.
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" watch 0 >/dev/null
"$ROOT/bin/ego" report alpha--agent-one blocked "another workspace is stuck" >/dev/null
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" watch 0 | grep -q '^No actionable events within 0 seconds\.$'
"$ROOT/bin/ego" handoff epsilon: --summary "epsilon needs supervision" >/dev/null
EGO_CONTROLLER_ID=epsilon--ego "$ROOT/bin/ego" watch 0 | grep -q 'epsilon needs supervision'
grep -q $'\tworkspace-handoff\tepsilon\tepsilon needs supervision\tepsilon$' "$EGO_HOME/events.log"
grep -q $'\tscan\tfleet\t.*\t$' "$EGO_HOME/events.log"

# Retiring a controller record drops its event cursor.
test -f "$EGO_HOME/watch/epsilon--ego.cursor"
tmux -L "$SOCKET" kill-session -t epsilon
"$ROOT/bin/ego" context >/dev/null
grep -q '^active=no$' "$EGO_HOME/controllers/epsilon--ego/meta"
test ! -f "$EGO_HOME/watch/epsilon--ego.cursor"
"$ROOT/bin/ego" list --controllers | grep 'epsilon--ego' | grep -q $'no\tmissing'

# A controller.meta from before controllers had records is migrated once.
rm -rf "$TMP/legacy"
mkdir -p "$TMP/legacy/state"
tmux -L "$SOCKET" new-window -d -t alpha: -n legacy-ego -c "$TMP"
legacy_pane=$(tmux -L "$SOCKET" list-panes -t alpha:legacy-ego -F '#{pane_id}')
{
  printf 'session=alpha\nwindow=legacy-ego\npane_id=%s\nscope=session\nstarted_at=x\n' "$legacy_pane"
} > "$TMP/legacy/state/controller.meta"
EGO_HOME="$TMP/legacy/state" "$ROOT/bin/ego" list >/dev/null
grep -q '^scope=session$' "$TMP/legacy/state/controllers/alpha--legacy-ego/meta"
grep -q "^pane_id=$legacy_pane\$" "$TMP/legacy/state/controllers/alpha--legacy-ego/meta"
test -f "$TMP/legacy/state/controller.meta"
# Migration runs once, so a later scope change is not reverted.
EGO_HOME="$TMP/legacy/state" "$ROOT/bin/ego" scope alpha--legacy-ego alpha,zeta >/dev/null
EGO_HOME="$TMP/legacy/state" "$ROOT/bin/ego" list >/dev/null
grep -q '^scope=alpha,zeta$' "$TMP/legacy/state/controllers/alpha--legacy-ego/meta"

# A pane id is unique only within one tmux server's lifetime. A restarted server
# numbers its panes from %0 again, so an old record must be retired rather than
# refreshed onto whatever new pane took its id, and a caller in that new pane
# must not inherit an old controller's scope.
# kill-server returns before the server is gone, and a new-session in that
# window fails with "server exited unexpectedly".
restart_server() {
  local tries=0
  tmux -L "$SOCKET" kill-server 2>/dev/null || true
  while [ "$tries" -lt 50 ]; do
    sleep 0.2
    tmux -L "$SOCKET" new-session -d -s "$1" -c "$TMP" -n "$2" 2>/dev/null && return 0
    tries=$((tries + 1))
  done
  printf 'could not restart the test tmux server\n' >&2
  exit 1
}
export EGO_HOME="$TMP/restart/state"
restart_server old agent-old
tmux -L "$SOCKET" set-option -g @workspace_primary "$TMP"
tmux -L "$SOCKET" new-window -d -t old: -n agent-legacy -c "$TMP"
"$ROOT/bin/ego" context >/dev/null
old_pane=$(tmux -L "$SOCKET" list-panes -t old:agent-old -F '#{pane_id}')
grep -q '^server_started=[0-9]' "$EGO_HOME/agents/old--agent-old/meta"
# A record written before the server stamp existed is judged by its age.
sed -i '/^server_started=/d' "$EGO_HOME/agents/old--agent-legacy/meta"
PATH="$TMP/fake-bin:$PATH" "$ROOT/bin/ego" start --session old --window ego --scope session >/dev/null
controller_pane=$(tmux -L "$SOCKET" list-panes -t old:ego -F '#{pane_id}')
socket_path=$(tmux -L "$SOCKET" display-message -p '#{socket_path}')
TMUX="$socket_path,1,0" TMUX_PANE="$controller_pane" "$ROOT/bin/ego" context | grep -q '^Scope: session old\.'
# The start time has one-second resolution.
sleep 1
restart_server new agent-new
tmux -L "$SOCKET" set-option -g @workspace_primary "$TMP"
tmux -L "$SOCKET" new-window -d -t new: -n agent-new2 -c "$TMP"
tmux -L "$SOCKET" new-window -d -t new: -n plain -c "$TMP"
test "$(tmux -L "$SOCKET" list-panes -t new:agent-new -F '#{pane_id}')" = "$old_pane"
"$ROOT/bin/ego" list --controllers | grep 'old--ego' | grep -q $'yes\tmissing'
if "$ROOT/bin/ego" peek old--agent-old | grep -q 'pane lines:$'; then
  printf 'peek reached a pane that only shares an id with the recorded one\n' >&2
  exit 1
fi
"$ROOT/bin/ego" peek old--agent-old | grep -q '^Pane: gone$'
"$ROOT/bin/ego" context >/dev/null
grep -q '^active=no$' "$EGO_HOME/agents/old--agent-old/meta"
grep -q '^session=old$' "$EGO_HOME/agents/old--agent-old/meta"
grep -q '^active=no$' "$EGO_HOME/agents/old--agent-legacy/meta"
grep -q '^session=old$' "$EGO_HOME/agents/old--agent-legacy/meta"
grep -q '^session=new$' "$EGO_HOME/agents/new--agent-new/meta"
grep -q '^active=yes$' "$EGO_HOME/agents/new--agent-new/meta"
grep -q '^session=new$' "$EGO_HOME/agents/new--agent-new2/meta"
grep -q '^active=no$' "$EGO_HOME/controllers/old--ego/meta"
test "$(tmux -L "$SOCKET" list-panes -t new:plain -F '#{pane_id}')" = "$controller_pane"
TMUX="$socket_path,1,0" TMUX_PANE="$controller_pane" "$ROOT/bin/ego" context | grep -q '^Scope: every session'
# An id already taken by an older record is never overwritten by a new pane.
tmux -L "$SOCKET" new-window -d -t new: -n agent-new3 -c "$TMP"
new3_index=$(tmux -L "$SOCKET" display-message -p -t new:agent-new3 '#{pane_index}')
mkdir -p "$EGO_HOME/agents/new--agent-new3" "$EGO_HOME/agents/new--agent-new3--p$new3_index"
"$ROOT/bin/ego" context >/dev/null
grep -q '^window=agent-new3$' "$EGO_HOME/agents/new--agent-new3--p$new3_index-2/meta"
test ! -f "$EGO_HOME/agents/new--agent-new3/meta"

printf 'ok\n'
