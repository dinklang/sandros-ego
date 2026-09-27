# Design

## Human-led ownership

Sandro remains the normal supervisor.
Discovering a worker records it with `origin=human` and `owner=human`, which allows inspection but does not authorize autonomous steering.
An explicit handoff changes the owner to `ego` and supplies the context that terminal output cannot provide.

Ownership records unattended responsibility. It does not disable reporting or prevent a one-off instruction that Sandro explicitly requests.
The durable inbox carries instructions to workers. Status logs carry material reports back to Ego. Reporting remains active while Sandro is present.

This supports workflows that develop during the work.
The agent can keep its existing conversation, shell state, and working directory when ownership changes.

## Controllers, workspaces, and scope

One tmux server may contain many workspace sessions.
Each session has its own session path and agent windows.
Ego reads the entire server and records the exact session, window, window ID, and pane ID for each agent.

A controller's scope is an explicit list of sessions, and several controllers
can run at once.
The controller window inherits its session's workspace root, so it matches every
other window in that session. The neutral
`~/.ego/state/controller` directory remains the fallback for a session whose root
cannot be resolved. Its runtime instructions come from the installed
`~/.ego/CONTROLLER.md`; the repository `AGENTS.md` applies only while developing
Ego.

A controller covers its own session by default. More sessions are listed
explicitly, at start or with `ego scope`, and a controller that spawns into a
brand-new session gets that session added, so it keeps reach over what it
created. There is no implicit whole-server scope: a controller over several
workspaces names them. Scope bounds what a controller reads,
wakes for, and may touch. It does not bound what `ego scan` records: keeping the
fleet record complete costs one tmux call and preserves cross-session handoff on
request. Every context read names its scope so the controller knows it is seeing
a subset.

A controller is a record, `state/controllers/<id>/meta`, keyed like an agent id.
Starting one therefore has no effect on one already running, and its launch
script lives beside its record so a restart in place restores the same identity.
The script exports `EGO_CONTROLLER_ID`, and each invocation resolves its own
scope from that, from `$TMUX_PANE`, or from `EGO_AGENT_ID` when the caller is a
worker. A human in a plain shell gets every session. Because scope is data read
at call time, `ego scope` changes it without a restart. An older record holding
`session` reads as its own session, and one holding `server` as every session,
until it is rewritten.

A pane is a controller or a worker, never both. `ego scan` excludes every live
controller pane and retires any agent record that claims one, so a controller
from an earlier session is never adopted as a worker.

Scope is a boundary as well as a filter. `require_in_scope` keys on a session, so
one check covers both agent commands and workspace commands, and `spawn` cannot
open a window in someone else's workspace. `--any-session` is
the deliberate override. This is a coordination guard, not a security boundary: a
caller that unsets `EGO_AGENT_ID` escapes it, and keeping server scope for humans
is intended.

Events carry the session they belong to, so `ego watch` wakes a controller only
for the workspaces its scope lists. An event with no session, such as a fleet
`scan`, reaches every controller. Each caller keeps its own cursor, so one
controller consuming an event cannot hide it from another. Two controllers whose
scopes list the same session still both wake for its events, so each session is
covered by one controller at a time.

Ownership and reporting are records, not messages. Nothing is pushed into a pane
except an `ego send` inbox notice and an `ego press` keystroke, so a handoff or a
takeback never tells an agent to change behavior. An agent behaves like a
controller because its launch prompt pointed it at `CONTROLLER.md`, and it
reports because its launch prompt or onboarding message told it to.

Discovery delegates identity to Agent Navigator. It matches recognized processes in each pane TTY's foreground process group, so window names are irrelevant and suspended background agents are excluded. Ego joins the detected pane IDs with its tmux inventory and excludes every live controller pane.

An Ego spawn records `origin=ego`, starts with `owner=ego`, and receives the reporting contract in its initial prompt. A discovered worker starts human-owned and does not report until it is onboarded.
`onboard-workspace` scans the tmux server and sends that contract to every active, non-reporting worker in one session. It leaves ownership unchanged and does not resend the contract to workers already reporting.

## Recovery

The files under `EGO_HOME`, normally `~/.ego/state`, hold the durable records.
The tmux server holds the running processes.
`ego scan` joins those two views after Ego starts or restarts.

Each workspace also has a checkpoint file.
It records the current state and next action without requiring a model to stay alive.
`handoff-workspace` changes every registered agent in that session to Ego ownership and writes the checkpoint in one command.

The first prototype does not import a model's private conversation history.
The handoff note records the information needed for another supervisor to continue.

Before an intentional controller reset, `ego stow` records only the volatile workspace delta and next action. Briefs, status logs, handoffs, and metadata remain authoritative and should not be copied into the checkpoint. A replacement controller starts with `ego session-start` and uses targeted recovery only when needed.

## Retirement

A record can outlive what it describes. A tmux pane id is never reused while one
server runs, so a recorded pane that is absent from the inventory is permanently
gone, and a scan retires that agent. A restarted server numbers its panes from
`%0` again, so the same id can later name an unrelated pane. Every record
therefore stores the server's start time, and a pane matches a record only when
that start time matches too. A record from an earlier server is retired, never
refreshed onto the new pane, and a caller in that pane never inherits an old
controller's scope. A record written before the stamp existed is trusted only
when it was created after the running server started. The same rule retires a
controller record whose pane is gone, which also removes that controller's event
cursor.

Every `ego context` read begins with that scan, so retirement does not depend on
anyone running `ego scan`. A scan logs an event only when it recorded or retired
something. Workspace records are written only from live sessions; a scan marks a
record `live=no` when its session is gone, and a workspace is in context exactly
while its session is live.

A scan cannot judge a window left open after its agent exited. `ego list
--stale` names those candidates and prints the `tmux kill-window` line that would
close each one, and `ego retire` takes one agent, a `session:` workspace, every
candidate in scope, or a controller. Retirement is deliberate, so a refresh
preserves it. Only `register` and `spawn` return a record to active context.

`ego purge` is the single operation in the prototype that deletes anything. It
removes Ego's bookkeeping for an agent whose pane is already gone, never a
window, a directory, or a worktree.

## Context control

The event log records every report and coordination action. The default watcher wakes the controller only for actionable events. Routine `working` and `note` reports stay on disk. `ego context` prints at most five recent status lines per tracked agent.

This keeps continuous reporting separate from continuous model context. The controller can read more history when a question or decision requires it.

Ownership persists after the controller ends a turn, but active monitoring does
not. The controller must remain in its watch loop when Sandro requests
supervision through a stated terminal condition. A completed or blocked worker
normally waits until the controller or Sandro sends another instruction.

## Reporting boundary

Ego has no background telemetry hook. A spawned or onboarded worker reports by calling `ego report` at material phase changes. The watcher reads Ego's event log rather than scraping every agent conversation.

Agent Navigator adds on-demand process and screen observation during `ego scan`. It can identify a live agent and estimate `working`, `blocked`, `idle`, or `unknown`, but that estimate does not replace a worker report.

A pane can outlive the agent that ran in it. `scan` records `process=yes` or
`process=no` from the detection set rather than retiring such a record, because
starting an agent in the same pane again reuses the same pane id. Pane liveness
and process presence are separate columns in `ego list`.

`ego watch` persists one cursor per caller, written as soon as the starting
position is known. Without a cursor, each call sampled the event log from the
present and lost anything reported while the controller was between calls; without
the early write, a call that returned empty left no cursor and the next one
sampled from the present again. The cursor is per caller so one controller
consuming an event cannot hide it from another.

An onboarded worker differs from a spawned worker. It keeps its prior conversation and directory, receives the protocol mid-session, and remains human-owned until handoff. It does not receive a generated brief or isolated worktree. Both use the same inbox and status files after onboarding.

Worker status describes the assigned scope. A worker reports `idle` when it has
no assignment, `done` when that scope is complete, and `blocked` only when that
scope cannot proceed. Later project gates belong in the report message and do
not turn completed work into a blocked assignment.

## Worktree choice

`ego spawn --worktree` creates a dedicated branch and Git worktree under `EGO_HOME/worktrees`. The default remains the workspace checkout.

The agent that creates a worker chooses isolation from the task. Independent editing and commits normally use a worktree. Read-only work and deliberate collaboration may use the shared checkout.

## Planned additions

- A composer check before ringing the durable instruction inbox.
- A tmux status indicator for human-owned and Ego-owned windows.
- Better completion signals for Codex and other agent commands.
- Explicit cleanup after work has landed.
- Small workflow templates for profiling, optimization, review, and test runs.
- `owner` naming which controller supervises a worker, instead of the two-value
  `human` or `ego` field, so a handoff can be addressed and a retired
  controller's workers can be reassigned.
