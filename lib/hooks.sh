# OpenHarness hooks helper
# Shared utilities for hook scripts. Not sourced by the CLI directly.

# Read the active task status from a repo root.
# Usage: oh_hook_read_status /path/to/repo
# Returns: status string or empty
oh_hook_read_status() {
  local repo_root="$1"
  local tasks_dir="$repo_root/.openharness/tasks"

  [ -d "$tasks_dir" ] || return 1

  local latest
  latest="$(ls -1t "$tasks_dir" 2>/dev/null | head -1)"
  [ -n "$latest" ] || return 1

  local status_file="$tasks_dir/$latest/status.json"
  [ -f "$status_file" ] || return 1

  sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$status_file" | head -1
}
