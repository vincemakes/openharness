# OpenHarness hooks helper
# Shared utilities for hook scripts. Not sourced by the CLI directly.

# Read the active task status from a repo root.
# Usage: oh_hook_read_status /path/to/repo
# Returns: status string or empty
oh_hook_read_status() {
  local repo_root="$1"
  local tasks_dir="$repo_root/.openharness/tasks"
  local active_file="$repo_root/.openharness/active-task"

  # Primary: active-task file
  local task_id=""
  if [ -f "$active_file" ]; then
    task_id="$(cat "$active_file")"
  fi

  # Fallback: most recent by mtime
  if [ -z "$task_id" ] && [ -d "$tasks_dir" ]; then
    task_id="$(ls -1t "$tasks_dir" 2>/dev/null | head -1)"
  fi

  [ -n "$task_id" ] || return 1

  local status_file="$tasks_dir/$task_id/status.json"
  [ -f "$status_file" ] || return 1

  sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$status_file" | head -1
}
