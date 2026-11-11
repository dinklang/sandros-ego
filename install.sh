#!/usr/bin/env bash
# Install or update Sandro's Ego from this repository.
#
# Controllers and workers run the installed copy, never the repository. That
# keeps an uncommitted or half-finished edit here from going live on its own,
# and gives permission rules one fixed executable path to allow. Run this again
# after pulling or merging changes to bin/ego or CONTROLLER.md; until then
# 'ego start' and 'ego context' warn that the installed copy differs.
#
# What it writes (defaults in parentheses):
#   $EGO_INSTALL_DIR/ego        the command, mode 755    (~/.ego/bin/ego)
#   $EGO_INSTALL_DIR/repo-root  this repository's path   (~/.ego/bin/repo-root)
#   $EGO_CONTROLLER_GUIDE       controller instructions  (~/.ego/CONTROLLER.md)
# EGO_ROOT (~/.ego) moves both defaults at once. State under $EGO_ROOT/state is
# never touched here.
set -eu

# The repository is wherever this script lives, whatever the caller's cwd.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EGO_ROOT=${EGO_ROOT:-$HOME/.ego}
install_dir=${EGO_INSTALL_DIR:-$EGO_ROOT/bin}
controller_guide=${EGO_CONTROLLER_GUIDE:-$EGO_ROOT/CONTROLLER.md}

mkdir -p "$install_dir" "$(dirname "$controller_guide")"

# The command itself. install(1) replaces the file and sets its mode in one step.
install -m 755 "$REPO_ROOT/bin/ego" "$install_dir/ego"

# The guide every controller's launch prompt tells it to read.
install -m 644 "$REPO_ROOT/CONTROLLER.md" "$controller_guide"

# The installed ego reads repo-root to find this repository: for the drift
# warning, and for the controller guide when the installed one is missing.
# Written to a temporary file and renamed, so a running ego never reads a
# partial path.
root_tmp=$(mktemp "$install_dir/.repo-root.XXXXXX")
printf '%s\n' "$REPO_ROOT" > "$root_tmp"
mv "$root_tmp" "$install_dir/repo-root"

printf 'installed Ego at %s\n' "$install_dir/ego"
