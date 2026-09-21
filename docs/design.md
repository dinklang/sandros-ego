# Design

## Human-led ownership

Sandro remains the normal supervisor.
Discovering a worker records it with `origin=human` and `owner=human`, which allows inspection but does not authorize autonomous steering.
An explicit handoff changes the owner to `ego` and supplies the context that terminal output cannot provide.

Ownership records unattended responsibility. It does not disable reporting or prevent a one-off instruction that Sandro explicitly requests.
The durable inbox carries instructions to workers. Status logs carry material reports back to Ego. Reporting remains active while Sandro is present.

This supports workflows that develop during the work.
The agent can keep its existing conversation, shell state, and working directory when ownership changes.

## One controller, many workspaces

One tmux server may contain many workspace sessions.
Each session has its own session path and agent windows.
Ego reads the entire server and records the exact session, window, window ID, and pane ID for each agent.

One controller can supervise agents across those sessions.
The controller's own tmux location does not decide which agents it can see.
The controller runs from `~/.ego/state/controller`, not from the Ego source
repository or a project workspace. Its runtime instructions come from the
installed `~/.ego/CONTROLLER.md`; the repository `AGENTS.md` applies only while
developing Ego.

Discovery delegates identity to Agent Navigator. It matches recognized processes in each pane TTY's foreground process group, so window names are irrelevant and suspended background agents are excluded. Ego joins the detected pane IDs with its tmux inventory and excludes its own controller pane.

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

`archive-workspace` is the context-retirement operation. It archives the current checkpoint and hides that workspace and its agents from normal startup context. It does not terminate processes or delete code. Recovery can still inspect the records.

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
- Optional workspace-scoped mini Ego processes if one controller becomes too broad.
