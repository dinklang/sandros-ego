# Sandro's Ego

Sandro's Ego is a small tmux agent supervisor built for a human-led workflow.

You can create sessions, windows, agents, and experimental workflows yourself.
Ego can track their material reports while you work directly with them.
When you step away, hand continuing supervision to Ego.

## Current prototype

The prototype can:

- Find live coding-agent panes across all tmux sessions through Agent Navigator process detection.
- Onboard an existing window without restarting its agent.
- Open a named worker window in an existing workspace session.
- Record whether Sandro or Ego currently owns supervision.
- Store a handoff note and worker status history.
- Peek at and send text to a registered pane.
- Press a restricted set of keys for an explicitly authorized terminal prompt.
- Start a dedicated Ego agent in a tmux window.
- Run several controllers at once, each with its own record and scope.
- Keep a controller inside the workspaces its scope lists.
- Change a running controller's scope without restarting it.
- Rebuild its view after a restart from tmux and files on disk.
- Tell panes apart across tmux server restarts, which reuse pane ids.
- Launch Codex, Claude, or Kiro agents.
- Retire the records of panes and workspaces that no longer exist, and list the
  cleanup candidates a scan cannot judge.
- Record each worker's live state in its handoff note.
- Limit each command to the roles that should run it.
- Give each worker its own startup context with its brief, inbox, and protocol.
- Queue durable instructions and record which ones a worker has read.
- Create an optional Git branch and worktree for a spawned agent.
- Save a compact pre-reset workspace note and restart or resume a controller.

It does not merge code, remove windows, or remove worktrees. Agent Navigator's screen status is only an observation, never a durable worker report.
Those can be added after the handoff model works well in daily use.

## First-time installation

These instructions support macOS and Linux. They assume Codex, Claude Code, Kiro
CLI, or another agent CLI is already installed. Ego launches Codex, Claude, and Kiro
directly; other programs can be started with `--command`.

### 1. Check prerequisites

Install these prerequisites using the method appropriate for your environment:

- Bash 4 or newer
- tmux
- Git
- Standard Unix tools such as `awk`, `sed`, `find`, and `mktemp`
- Codex, Claude Code, Kiro CLI, or another agent CLI

Verify that the required commands are available before installing Ego:

```sh
bash --version
tmux -V
git --version
```

### 2. Install Agent Navigator

Ego uses Agent Navigator to find agent processes across tmux panes. Its source
lives in the dotfiles repository
([dinklang/dotfiles](https://github.com/dinklang/dotfiles), `agent-navigator/`):

```sh
git clone git@github.com:dinklang/dotfiles.git
cd dotfiles/agent-navigator
./install.sh
```

The default executable is:

```text
~/.local/share/agent-navigator/bin/agent-navigator
```

For another location, export its absolute path:

```sh
export EGO_AGENT_NAVIGATOR=/path/to/agent-navigator/bin/agent-navigator
```

Persist that export in the machine's shell configuration.

### 3. Configure the workspace root

Create the directory that will contain project workspaces and configure tmux:

```sh
mkdir -p "$HOME/Work"
tmux set-option -g @workspace_primary "$HOME/Work"
```

Add the persistent setting to `~/.tmux.conf` or the machine's active tmux
configuration:

```tmux
set -g @workspace_primary "$HOME/Work"
```

An optional secondary root uses `@workspace_secondary`.

### 4. Install Ego

Clone or copy this private repository, then run from its root:

```sh
./install.sh
```

Add Ego to the shell path in `~/.zshrc`, `~/.bashrc`, or the equivalent file:

```sh
export PATH="$HOME/.ego/bin:$PATH"
```

Open a new shell or reload that configuration. The state directory is created on
first use. If you skip `./install.sh`, the first `ego start` or `ego spawn` run
from the repository runs it for you; later installs are always explicit.

The installation lives under `~/.ego`: protected executable code is in `bin/`,
controller instructions are in `CONTROLLER.md`, and mutable records are in
`state/`. Set `EGO_ROOT` or `EGO_HOME` before installation to override these
defaults, or `EGO_INSTALL_DIR` and `EGO_CONTROLLER_GUIDE` to move the command
and the guide individually.

### 5. Configure the Codex rule

Copy `.example-codex-rule` into a `.rules` file under `~/.codex/rules/`. Replace
`/ABSOLUTE/HOME` with the machine's absolute home directory, then restart Codex:

```sh
mkdir -p "$HOME/.codex/rules"
cp .example-codex-rule "$HOME/.codex/rules/ego.rules"
```

The rule path must be absolute. Codex matches command prefixes literally. The
rule lets the protected Ego command reach tmux without granting every tmux
command access outside the sandbox.

### 6. Verify the installation

Start or attach to a tmux server, then check each layer:

```sh
command -v ego
ego --help
~/.local/share/agent-navigator/bin/agent-navigator list
ego context
```

Start the controller from a tmux session:

```sh
ego start
```

To test automatic workspace creation, this command creates
`$HOME/Work/ego-test`, creates the `ego-test` tmux session, and starts a worker
window there:

```sh
ego spawn planner --session ego-test --brief "Wait for instructions."
```

To check the supervision path against real agents, run the live integration
test from the repository. It uses an isolated tmux server and state directory,
spawns each agent, and verifies that `context`, `peek`, and `send` work:

```sh
bash tests/integration-agents.sh            # kiro, claude, and codex
bash tests/integration-agents.sh kiro       # one agent
bash tests/integration-agents.sh --strict   # also wait for the worker to read its inbox and report
```

`--strict` requires the agent to run the `ego` command without a permission
prompt, so it depends on each tool's own trust configuration.

### Updating

After updating the repository, reinstall the protected copy and restart the
controller:

```sh
./install.sh
```

Ego never copies the repository over the installed copy on its own, so an
uncommitted edit cannot go live by accident. When the two differ, `ego start`
and `ego context` print a warning naming the repository.

## Use your existing windows

Suppose your tmux server has these windows:

```text
project-a:profile
project-a:review
project-b:optimizer
```

Every `ego context` read discovers the supported coding-agent panes first:

```sh
ego context
ego list
```

Detection uses the pane TTY foreground process group, not the window name. It recognizes Codex, Claude, Kiro, Gemini, Aider, and OpenCode. Add the reporting and inbox contract to an existing agent with:

```sh
ego onboard project-a:review
```

Onboarding a window Ego has not recorded registers it first. When detection
misses the agent, set its type and, optionally, its record id:

```sh
ego onboard project-a:review --agent aider --id project-a-review
```

`--root` sets the workspace directory Ego records for it. Onboarding a retired
record brings it back into context.

Onboard every active agent in one workspace session with:

```sh
ego onboard project-a:
```

The command scans first, skips agents that already report, and leaves ownership unchanged. Agents whose panes are unavailable are reported and skipped.

The agent then reports material changes whether its owner is `human` or `ego`.
It keeps its existing conversation and working directory. Onboarding sends one
short instruction: run `ego context --agent <id>`. That prints the worker's own
view: how to report, how to read instructions, its brief, its pending messages,
its workspace note, and the other agents in its workspace. A
worker Ego spawned gets the same view from plain `ego context`, since its launch
script exports its id. The protocol text lives in `bin/ego`, so updating Ego
updates it for every worker without a respawn.

Withdraw the contract again with `ego onboard project-a-review --off`. The
record stays, with reporting off.

`ego peek <id>` is the controller's one-call look at an agent before acting:
its handoff note while Ego owns it, latest report, and last 60 pane lines. Pass
a line count for more history, as in `ego peek <id> 200`. `ego handback` prints
the same bundle.

## Hand off an agent

```sh
ego handoff project-a--profile \
  --summary "The agent built a sampling profiler and is comparing two capture formats." \
  --next "Have it validate overhead below 2 percent and summarize the result."
```

This changes the record from `owner=human` to `owner=ego`.
It does not restart the worker or change its tmux window.

Below your summary, the handoff note records the worker's state at that moment:
its latest report, whether its agent process is running, Agent Navigator's
screen observation, unread inbox messages, and the last 20 pane lines. The
command prints the same section, so a controller that runs the handoff for you
sees a running process even when the summary does not mention it.

Take control back with:

```sh
ego handback project-a--profile
```

`handback` prints the latest durable worker report. When the controller handles
the request, it also reads the live pane and gives a short return brief. The
brief is expected controller behavior, not a model-generated feature of the
ownership change itself.

Hand off a whole workspace with one recovery summary:

```sh
ego handoff project-a: \
  --summary "The profiler works. The optimizer is testing the hot loop." \
  --next "Collect both results and compare total runtime."
```

This marks every registered agent in that session as Ego-owned.

Return every active agent in that workspace to human supervision with:

```sh
ego handback project-a:
```

Reporting stays enabled after handback.

## Spawn an agent

When run inside tmux, `ego spawn` uses the current session and its session path:

```sh
ego spawn profiler --agent codex --brief "Build the first profiling experiment."
```

That creates a `profiler` window and starts Codex there. Ego records it as `origin=ego`, `owner=ego`, and `reporting=on`.

Worker names are short `<topic>-<role>` kebab-case names such as `az-analyzer`
or `stt-research`. `spawn` refuses names longer than 3 parts or 24 characters.

From outside tmux, name the workspace session:

```sh
ego spawn optimizer \
  --session project-b \
  --brief "Measure the current binary and find the largest cost."
```

If `project-b` does not exist, `spawn` creates both the directory under
`@workspace_primary` and the tmux session before launching the worker. The
session and directory use the same name. New names must be directory-safe, so
use `music-generation` rather than `music generation`.

Ego reads `@workspace_primary` from the running tmux server, not from `.zshrc`.
Check the effective value with:

```sh
tmux show-options -gv @workspace_primary
```

If it is missing or wrong, fix the tmux configuration and reload it before
creating a workspace. For an existing session, Ego uses tmux's session path,
then its recorded workspace root, then a live pane path. Pass `--root` when none
of those is the intended workspace directory.

Pass `--root` to create a missing session somewhere else or to override an
existing session's path. The controller never substitutes its runtime directory
or the Ego source repository.
Use `--agent claude` for Claude Code and `--agent kiro` for Kiro CLI.
Kiro is the default worker; use `--agent codex` for Codex. The controller
started by `ego start` defaults to Claude Code instead.
Other agent programs are outside the supported set for now, although `--command` remains available for experiments.
Ego starts Codex in `workspace-write` mode and adds `EGO_HOME` as a writable root so the controller and workers can update durable state without full filesystem access. Claude and Kiro use their own permission configuration; Kiro reads its default agent profile and model from `~/.kiro`.

Internally, an agent ID includes the session and window, such as
`music-generation--planner`. You can avoid typing that ID for individual
ownership changes:

```sh
ego handoff planner --session music-generation --summary "Ready for supervision."
ego handback planner --session music-generation
```

Inside any window in that tmux session, omit the session entirely:

```sh
ego handoff planner --summary "Ready for supervision."
ego handback planner
```

The main Ego controller runs in a separate session, so it uses the full agent ID
or `--session` when acting for you.

Use an isolated branch and worktree when the worker may edit or commit independently:

```sh
ego spawn optimizer --session project-b --worktree \
  --brief "Optimize the hot loop and validate the result."
```

Ego creates branch `ego/<agent-id>` and records the worktree path. Pass `--branch <name>` to choose another branch. Shared checkout remains the default. The controller that creates the next agent decides which mode fits the task.

## Communication

Instructions and reports use separate paths.

- `ego send` writes an instruction into the agent's durable inbox and rings its tmux pane.
- `ego inbox` lets the worker read pending instructions and moves them to `inbox/handled/`. A worker reading its own `ego context` handles them the same way.
- `ego report` appends a material worker update to its status log.

Reporting stays active during attended work. Handoff changes who must react and continue supervision. It does not turn reporting on.

Ego checks who is calling. A worker, identified by the `EGO_AGENT_ID` its launch
script exports, may only report, read its own inbox, and look at its own
workspace; it can leave out its own id, as in `ego report done
"tests pass"`, and may not name another agent's. Supervision commands such as
`handoff`, `press`, `retire`, `spawn`, and `watch` refuse a worker. A controller
cannot start another controller or add a workspace to its own scope. Commands
you run from a plain shell are never refused for role.

`ego watch` keeps a cursor per caller under `state/watch/`, so a report that
lands while the controller is busy is surfaced by the next watch call instead of
being missed. The first watch of a session starts from the present and does not
replay an old log.

Every event records the session it belongs to, so a controller wakes only for
the workspaces its scope lists. An event that names no session, such as a
fleet-wide scan event, reaches every controller.

## Clean up agents and workspaces

A tmux pane id is never reused while one server runs, so a pane that disappears
is gone for good. A restarted server numbers panes from `%0` again, so Ego also
records the server's start time and treats a matching id on a newer server as a
different pane: the old record is retired, and the new pane gets its own.

Every `ego context` read joins tmux first. An agent whose pane has vanished is
retired, which keeps dead workers out of every later read, and the same rule
applies to a controller record, which also drops its event cursor. A workspace
is in context while its tmux session is live.

A scan cannot judge a window you left open after its agent finished. List those
cleanup candidates, with the reason and the command that would close each
window:

```sh
ego list --stale
```

Retire records with:

```sh
ego retire project-a--profile     # one agent, by id
ego retire project-a:profile      # one agent, by session:window
ego retire project-a:             # every agent in a workspace
ego retire --stale                # every cleanup candidate in scope
ego retire --controller Main--ego # a controller record
```

A retired record leaves context and stays on disk. Onboarding or spawning the
same id again brings it back, and a later scan does not undo a retirement.
`ego retire --purge <id>` removes an agent's record directory, including its
brief, handoff, status log, and inbox, and refuses while the pane is still live.
Ego never closes a tmux window, deletes a working directory, or removes a
worktree.

Use `ego list` to see the difference: the `STATE` column reads `live` or
`missing` from tmux, the `PROCESS` column says whether the last scan found an
agent process in that pane, and `ego list active` hides retired records
entirely. A pane can be `live` with `process=no`, meaning the window is still
open but its agent has exited. Ego keeps that record, because starting an agent
in the same pane again reuses it. `ego list --controllers` and `ego list
--workspaces` are the same view for controller and workspace records.

## Start Ego

Start a controller near the beginning of your work session:

```sh
ego start
```

Or put it in a selected session and window:

```sh
ego start --session Main --window ego --agent codex
```

Claude Code runs the controller by default. Use `--agent kiro` or
`--agent codex` for another one. Workers default to Kiro.

The controller window inherits its session's workspace root, the same root every
other window in that session uses.

A controller's scope is the list of sessions it sees and may touch. It covers its
own session unless you list more:

```sh
ego start --session ProfilerShi --scope ProfilerShi,LoadTestShi
```

Starting a controller has no effect on any controller already running. Each one
gets its own record, so an earlier controller keeps its pane, scope, and workers.

Either way the record is only a default. The controller can widen or narrow any
single read:

```sh
ego context              # the recorded scope
ego context --all        # every session on this server
ego context --session project-b
```

Scope is also a limit, not only a display filter. A controller is refused when
it tries to peek, send, spawn, onboard, or hand off in a workspace its scope
does not list. `--any-session` is the deliberate override, for a request from Sandro
that names another workspace:

```sh
ego peek project-b--optimizer --any-session
```

Scope is read at call time, so a running controller can change it without a
restart:

```sh
ego scope                          # the calling controller's sessions
ego scope +project-b               # also cover project-b
ego scope -project-b               # stop covering it
ego scope project-a--ego project-a,project-b
```

To let one controller take over another workspace, add the workspace to its
scope and close the other workspace's controller; the next scan retires that
record. To go back, `ego start` in that workspace again. A controller that
spawns into a brand-new session gets that session added to its scope.

Ego can see registered agents in every session on the same tmux server.
You do not need one Ego process per workspace.

To restart the controller in place after a context reset, run its own generated
launch script in the same pane instead of closing the window:

```sh
~/.ego/state/controllers/<session>--<window>/launch.sh              # fresh conversation
~/.ego/state/controllers/<session>--<window>/launch.sh --continue   # resume the last one
```

`ego reset --note '<state>'` saves what the conversation knows as the workspace
note first and prints both commands. `ego start --continue` opens a new
controller window that resumes the most recent conversation in that workspace's
root. That is the right way to bring back an old controller conversation:
resuming it by hand in a new pane leaves it without a controller identity.

The script exports that controller's id, so a restart in place always restores
the same identity and scope. `ego start` refuses a window that already exists.
List the controllers and their launch paths with:

```sh
ego list --controllers
```

Ego may also start later. Use `ego context` and `ego onboard`, or `ego onboard <session>:`, to add agents that already exist.

## More than one controller

Nothing stops several controllers from running at once, and starting a new one
does not stop or demote an old one. Each has its own record under
`state/controllers/<id>/`, so nothing about an earlier controller changes when a
later one starts. Every controller still reads and writes the same agent and
workspace records.

A pane is a controller or a worker, never both. A scan excludes every live
controller pane from its agent list, and retires any agent record that claims a
controller's pane. A controller whose pane is gone is retired by the next scan.

Scope keeps controllers out of each other's way. A controller reads only the
sessions its scope lists, wakes only for events in them, and is refused when it
tries to act on another one. List several sessions when one controller should
supervise several workspaces.

Every `ego report` appends to one shared `state/events.log`, and `ego watch`
filters it by the caller's scope. Two controllers whose scopes list the same
session both wake on its events, so cover each session with one controller.

## Recovery

Sandro's Ego recovers from workspace notes, agent metadata, handoff notes, status logs, and live tmux checks.
Each tmux session is a workspace, and each workspace can have one note. Before an
intentional controller reset, store only the conversation facts that are missing
from durable records:

```sh
ego reset AgentOrchestrator--ego \
  --note "The benchmark result is valid. The remaining choice is the cache policy. Next: ask Sandro to choose it, then resume optimizer."
```

That writes the note for every workspace the controller covers and prints the
command that restarts it. A controller resetting itself leaves out its id.
Read the note and current agents later:

```sh
ego context --full --session AgentOrchestrator
```

A replacement controller begins with `ego context`. That command scans tmux and prints compact context. It includes no more than five recent status lines per tracked agent. Use `ego context --full --session <session>` only when more workspace detail is needed.

The note does not need a second model session.
It survives even if tmux or Ego stops.
One controller per workspace and one controller over several workspaces are both
supported, and the per-workspace files keep recovery local and clear either way.

## Your tmux workspace roots

Ego reads the tmux options already used by your configuration:

```tmux
@workspace_primary
@workspace_secondary
```

It labels each recorded session as `primary`, `secondary`, or `external` based on its `session_path`.
The dotfiles tmux templates set `@workspace_primary` to `~/workplace` and `@workspace_secondary` to `~/Work` when `~/workplace` exists (Brazil machines).
Otherwise `@workspace_primary` is `~/Work` and the secondary root is unset.

## Files and locations

The terminal process, working directory, and management record are separate:

```text
tmux server
  workspace session
    profiler window             running Codex process

workspace root                 files the agent edits

~/.ego/
  bin/ego                       protected installed command
  CONTROLLER.md                 installed controller instructions
  state/controller/             fallback controller working directory
  state/agents/<id>/meta        tmux and directory location
  state/agents/<id>/brief.md    initial task
  state/agents/<id>/handoff.md  Sandro's current handoff
  state/agents/<id>/status.log  worker and supervisor events
  state/agents/<id>/inbox/      pending durable instructions
  state/workspaces/<session>/meta
                                session root, workspace kind, live flag
  state/workspaces/<session>/checkpoint.md
                                recovery summary and next action
  state/events.log              wake stream for Ego, one session per line
  state/watch/<caller>.cursor   per-caller position in the event log
  state/controllers/<id>/meta   one controller's pane, root, and scope
  state/controllers/<id>/launch.sh
                                restart that controller in place
  state/worktrees/<id>/         optional isolated Git worktree
```

The `meta` file records the session, window, stable tmux pane ID, session root, current directory, foreground command, owner, whether the record is still active, and timestamps.

## Safety limits

`ego send` stores the full instruction on disk. It types only a short inbox notice into the agent terminal and presses Enter.
The notice can still collide with unfinished input. Inspect the pane first with `ego peek` when the agent may have unfinished input.

The prototype never closes a window or deletes a working directory.
That is intentional while the handoff workflow is still being tested.
`ego retire --purge` is the one command that deletes anything, and it only
removes Ego's own record of an agent whose pane is already gone.
