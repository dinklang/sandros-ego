# Sandro's Ego

Sandro's Ego is a small tmux agent supervisor built for a human-led workflow.

You can create sessions, windows, agents, and experimental workflows yourself.
Ego can track their material reports while you work directly with them.
When you step away, hand continuing supervision to Ego.

## Current prototype

The prototype can:

- Find live coding-agent panes across all tmux sessions through Agent Navigator process detection.
- Register an existing window without restarting its agent.
- Open a named worker window in an existing workspace session.
- Record whether Sandro or Ego currently owns supervision.
- Store a handoff note and worker status history.
- Inspect and send text to a registered pane.
- Press a restricted set of keys for an explicitly authorized terminal prompt.
- Start a dedicated Ego agent in a tmux window.
- Rebuild its view after a restart from tmux and files on disk.
- Record a recovery checkpoint for each workspace session.
- Launch Codex, Claude, or Kiro agents.
- Queue durable instructions and record worker acknowledgements.
- Create an optional Git branch and worktree for a spawned agent.
- Save a compact pre-restart workspace checkpoint.

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

Ego uses Agent Navigator to find agent processes across tmux panes. Clone or
copy its repository, then run:

```sh
cd /path/to/agent-navigator
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
./bin/ego install
```

Add Ego to the shell path in `~/.zshrc`, `~/.bashrc`, or the equivalent file:

```sh
export PATH="$HOME/.ego/bin:$PATH"
```

Open a new shell or reload that configuration, then initialize the state:

```sh
ego init
```

The installation lives under `~/.ego`: protected executable code is in `bin/`,
controller instructions are in `CONTROLLER.md`, and mutable records are in
`state/`. Set `EGO_ROOT` or `EGO_HOME` before installation to override these
defaults.

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
ego scan
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
spawns each agent, and verifies that `scan`, `peek`, and `send` work:

```sh
bash tests/integration-agents.sh            # kiro, claude, and codex
bash tests/integration-agents.sh kiro       # one agent
bash tests/integration-agents.sh --strict   # also wait for the worker to ack and report
```

`--strict` requires the agent to run the `ego` command without a permission
prompt, so it depends on each tool's own trust configuration.

### Updating

After updating the repository, reinstall the protected copy and restart the
controller:

```sh
./bin/ego install
```

## Use your existing windows

Suppose your tmux server has these windows:

```text
project-a:profile
project-a:review
project-b:optimizer
```

Discover every supported coding-agent pane:

```sh
ego scan
ego list
```

Detection uses the pane TTY foreground process group, not the window name. It recognizes Codex, Claude, Kiro, Gemini, Aider, and OpenCode. Register an unsupported custom agent explicitly:

```sh
ego register project-a:review --id project-a-review
```

Registering locates the agent but does not alter its prompt. Add the reporting and inbox contract to an existing agent with:

```sh
ego onboard project-a-review
```

Onboard every active agent in one workspace session with:

```sh
ego onboard-workspace project-a
```

The command scans first, skips agents that already report, and leaves ownership unchanged. Agents whose panes are unavailable are reported and skipped.

The agent then reports material changes whether its owner is `human` or `ego`.
It keeps its existing conversation and working directory. Onboarding sends only the reporting and inbox contract. It does not make the worker read Ego's workspace checkpoint, handoff, or controller instructions.

## Hand off an agent

```sh
ego handoff project-a--profile \
  --summary "The agent built a sampling profiler and is comparing two capture formats." \
  --next "Have it validate overhead below 2 percent and summarize the result."
```

This changes the record from `owner=human` to `owner=ego`.
It does not restart the worker or change its tmux window.

Take control back with:

```sh
ego takeback project-a--profile
```

`takeback` prints the latest durable worker report. When the controller handles
the request, it also inspects the live pane and gives a short return brief. The
brief is expected controller behavior, not a model-generated feature of the
ownership change itself.

Hand off a whole workspace with one recovery summary:

```sh
ego handoff-workspace project-a \
  --summary "The profiler works. The optimizer is testing the hot loop." \
  --next "Collect both results and compare total runtime."
```

This marks every registered agent in that session as Ego-owned.

Return every active agent in that workspace to human supervision with:

```sh
ego takeback-workspace project-a
```

Reporting stays enabled after takeback.

## Spawn an agent

When run inside tmux, `ego spawn` uses the current session and its session path:

```sh
ego spawn profiler --agent codex --brief "Build the first profiling experiment."
```

That creates a `profiler` window and starts Codex there. Ego records it as `origin=ego`, `owner=ego`, and `reporting=on`.

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
Kiro is the default; use `--agent codex` for Codex.
Other agent programs are outside the supported set for now, although `--command` remains available for experiments.
Ego starts Codex in `workspace-write` mode and adds `EGO_HOME` as a writable root so the controller and workers can update durable state without full filesystem access. Claude and Kiro use their own permission configuration; Kiro reads its default agent profile and model from `~/.kiro`.

Internally, an agent ID includes the session and window, such as
`music-generation--planner`. You can avoid typing that ID for individual
ownership changes:

```sh
ego handoff planner --session music-generation --summary "Ready for supervision."
ego takeback planner --session music-generation
```

Inside any window in that tmux session, omit the session entirely:

```sh
ego handoff planner --summary "Ready for supervision."
ego takeback planner
```

The main Ego controller runs in a separate session, so it uses the full agent ID
or `--session` when acting for you.

Use an isolated branch and worktree when the worker may edit or commit independently:

```sh
ego spawn optimizer --session project-b --worktree \
  --brief "Optimize the hot loop and validate the result."
```

Ego creates branch `ego/<agent-id>` and records the worktree path. Pass `--branch <name>` to choose another branch. Shared checkout remains the default. The controller or worker that creates the next agent decides which mode fits the task.

## Communication

Instructions and reports use separate paths.

- `ego send` writes an instruction into the agent's durable inbox and rings its tmux pane.
- `ego inbox` lets the worker read pending instructions.
- `ego ack` records that the worker handled an instruction.
- `ego report` appends a material worker update to its status log.

Reporting stays active during attended work. Handoff changes who must react and continue supervision. It does not turn reporting on.

## Finish a workspace

Skipping `stow` avoids a new checkpoint, but it does not remove an older checkpoint. After the tmux session is finished, remove it from active controller context without deleting its records:

```sh
ego archive-workspace optimizer
```

This archives the checkpoint, marks its agent records inactive, and returns their ownership to the human. It does not kill tmux, delete source files, or remove a worktree. `ego recover optimizer` can still read the retained records.

## Start Ego

Start one controller near the beginning of your work session:

```sh
ego start
```

Or put it in a selected session and window:

```sh
ego start --session Main --window ego --agent codex
```

The controller window inherits its session's workspace root, the same root every
other window in that session uses. Start it in a workspace session to supervise
that workspace from inside it, or in a session with a generic root to supervise
the whole server from a neutral place.

Ego can see registered agents in every session on the same tmux server.
You do not need one Ego process per workspace.

To restart the controller in place after a context reset, run its generated
launch script in the same pane instead of closing the window:

```sh
~/.ego/state/controller-launch.sh
```

`ego start` refuses a window that already exists. Run the launch script from
another pane only after closing the original, because `state/controller.meta`
still records the old pane.

Ego may also start later. Use `ego scan` and `ego onboard`, or `ego onboard-workspace`, to add agents that already exist.

## Recovery

Sandro's Ego recovers from workspace checkpoints, agent metadata, handoff notes, status logs, and live tmux checks.
Each tmux session is a workspace, and each workspace can have a checkpoint:

```sh
ego checkpoint AgentOrchestrator \
  --summary "Two experiments are running. The parser change is complete." \
  --next "Review the benchmark and decide whether to keep the cache."
```

Read the saved checkpoint and current agents later:

```sh
ego recover AgentOrchestrator
```

Before an intentional controller reset, Ego should store only conversation facts that are missing from durable records:

```sh
ego stow AgentOrchestrator \
  --summary "The benchmark result is valid. The remaining choice is the cache policy." \
  --next "Ask Sandro to choose the policy, then resume optimizer."
```

A replacement controller begins with `ego session-start`. That command scans tmux and prints compact context. It includes no more than five recent status lines per tracked agent. Use `ego recover <session>` only when more workspace detail is needed.

The checkpoint does not need a second model session.
It survives even if tmux or Ego stops.
A later version can add one mini Ego per workspace if separate supervisors prove useful.
For now, one Ego can supervise all sessions while the per-workspace files keep recovery local and clear.

## Your tmux workspace roots

Ego reads the tmux options already used by your configuration:

```tmux
@workspace_primary
@workspace_secondary
```

It labels each recorded session as `primary`, `secondary`, or `external` based on its `session_path`.
Your current personal configuration sets `@workspace_primary` to `~/Work` and leaves the secondary root unset.
The same code will recognize both roots on a machine that configures both.

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
                                session root and workspace kind
  state/workspaces/<session>/checkpoint.md
                                recovery summary and next action
  state/events.log              wake stream for Ego
  state/controller.meta         Ego's own tmux location
  state/worktrees/<id>/         optional isolated Git worktree
```

The `meta` file records the session, window, stable tmux pane ID, session root, current directory, foreground command, owner, and timestamps.

## Safety limits

`ego send` stores the full instruction on disk. It types only a short inbox notice into the agent terminal and presses Enter.
The notice can still collide with unfinished input. Inspect the pane first with `ego peek` when the agent may have unfinished input.

The prototype never closes a window or deletes a working directory.
That is intentional while the handoff workflow is still being tested.
