# OpenHarness maintenance module
# Stale task detection and worktree garbage collection.

# --- Platform-aware date math ---

# Returns seconds since epoch for a given ISO timestamp.
# Works on both BSD (macOS) and GNU (Linux) date.
_oh_date_to_epoch() {
  local ts="$1"
  # Strip trailing Z and replace T with space for parsing
  local clean
  clean="$(echo "$ts" | sed 's/T/ /;s/Z$//')"

  # Try GNU date first (Linux)
  if date -d "$clean UTC" +%s 2>/dev/null; then
    return 0
  fi

  # Try BSD date (macOS)
  # Format: YYYY-MM-DD HH:MM:SS
  local formatted
  formatted="$(echo "$clean" | sed 's/-//g;s/ //;s/://g')"
  if date -j -u -f "%Y%m%d%H%M%S" "$formatted" +%s 2>/dev/null; then
    return 0
  fi

  # Fallback: return 0 (epoch)
  echo "0"
}

_oh_now_epoch() {
  date +%s
}

# --- Commands ---

oh_maintain() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness maintain"
      echo ""
      echo "Scan all tasks and report stale or blocked items."
      return 0
      ;;
  esac

  _oh_require_init

  local tasks_dir
  tasks_dir="$(_oh_tasks_dir)"

  if [ ! -d "$tasks_dir" ]; then
    echo "No tasks directory found."
    return 0
  fi

  local now_epoch
  now_epoch="$(_oh_now_epoch)"

  local stale_count=0
  local total_count=0
  local has_issues=false

  echo "=== OpenHarness Maintenance Report ==="
  echo ""

  # Scan all tasks
  for task_path in "$tasks_dir"/*/; do
    [ -d "$task_path" ] || continue
    [ -f "$task_path/status.json" ] || continue

    total_count=$((total_count + 1))

    local id status updated_at
    id="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"
    status="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"
    updated_at="$(sed -n 's/.*"updated_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"

    if [ -z "$updated_at" ]; then
      continue
    fi

    local updated_epoch age_hours
    updated_epoch="$(_oh_date_to_epoch "$updated_at")"
    if [ "$updated_epoch" = "0" ]; then
      continue
    fi
    age_hours=$(( (now_epoch - updated_epoch) / 3600 ))

    # Check for stale tasks
    case "$status" in
      fixing)
        if [ "$age_hours" -gt 24 ]; then
          echo "STALE: $id — in 'fixing' for ${age_hours}h (>24h)"
          has_issues=true
          stale_count=$((stale_count + 1))
        fi
        ;;
      implementing)
        if [ "$age_hours" -gt 48 ]; then
          echo "STALE: $id — in 'implementing' for ${age_hours}h (>48h) with no progress"
          has_issues=true
          stale_count=$((stale_count + 1))
        fi
        ;;
      blocked)
        echo "BLOCKED: $id — needs attention"
        has_issues=true
        ;;
    esac

    # Check for orphaned worktrees
    local wt_path
    wt_path="$(sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"
    if [ -n "$wt_path" ] && [ ! -d "$wt_path" ]; then
      echo "ORPHANED WORKTREE: $id — path $wt_path no longer exists"
      has_issues=true
    fi
  done

  echo ""
  echo "Total tasks: $total_count"
  if [ "$has_issues" = "false" ]; then
    echo "No issues found."
  else
    echo "Stale tasks: $stale_count"
  fi
}

oh_gc() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness gc [--purge]"
      echo ""
      echo "Clean up worktrees for delivered/blocked tasks."
      echo ""
      echo "Options:"
      echo "  --purge    Also remove the task directory"
      return 0
      ;;
  esac

  _oh_require_init

  local purge=false
  if [ "${1:-}" = "--purge" ]; then
    purge=true
  fi

  local root
  root="$(_oh_repo_root)"
  local tasks_dir
  tasks_dir="$(_oh_tasks_dir)"

  if [ ! -d "$tasks_dir" ]; then
    echo "No tasks directory found."
    return 0
  fi

  local cleaned=0

  echo "=== OpenHarness Garbage Collection ==="
  echo ""

  for task_path in "$tasks_dir"/*/; do
    [ -d "$task_path" ] || continue
    [ -f "$task_path/status.json" ] || continue

    local id status
    id="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"
    status="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"

    # Only clean terminal-state tasks
    case "$status" in
      delivered|blocked) ;;
      *) continue ;;
    esac

    local wt_path branch
    wt_path="$(sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"
    branch="$(sed -n 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_path/status.json" | head -1)"

    local did_something=false

    # Remove worktree if exists
    if [ -n "$wt_path" ] && [ -d "$wt_path" ]; then
      git worktree remove "$wt_path" --force 2>/dev/null || true
      echo "Removed worktree: $wt_path"
      did_something=true
    fi

    # Delete branch if exists
    if [ -n "$branch" ]; then
      local current_branch
      current_branch="$(git branch --show-current 2>/dev/null || true)"
      if [ "$current_branch" != "$branch" ] && git rev-parse --verify "$branch" >/dev/null 2>&1; then
        git branch -D "$branch" 2>/dev/null || true
        echo "Deleted branch: $branch"
        did_something=true
      fi
    fi

    # Purge task directory if requested
    if [ "$purge" = "true" ]; then
      rm -rf "$task_path"
      echo "Purged task directory: $id"
      did_something=true
    fi

    if [ "$did_something" = "true" ]; then
      cleaned=$((cleaned + 1))
    fi
  done

  if [ "$cleaned" -eq 0 ]; then
    echo "Nothing to clean up."
  else
    echo ""
    echo "Cleaned: $cleaned task(s)"
  fi
}
