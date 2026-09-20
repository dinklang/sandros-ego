# Sandro's Ego development

These instructions apply only when developing the Ego source repository. They
are not the runtime controller instructions.

- Keep runtime state and task deliverables outside this repository.
- Update `CONTROLLER.md` when controller behavior changes.
- Run `bash tests/test-ego.sh` after changing `bin/ego`.
- Preserve existing user state during migrations.
- Do not close tmux sessions, delete worktrees, or move user deliverables unless
  Sandro explicitly requests it.
