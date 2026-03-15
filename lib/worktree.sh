# OpenHarness worktree module
# Manages git worktrees for task isolation.

# Branch naming convention: oh/<task-id>
_oh_branch_name() {
  local task_id="$1"
  echo "oh/${task_id}"
}

# Worktree path: .openharness/worktrees/<task-id>/
_oh_worktree_path() {
  local root="$1"
  local task_id="$2"
  echo "$root/.openharness/worktrees/$task_id"
}

oh_worktree() {
  case "${1:-}" in
    --help|-h)
      echo "Usage: openharness worktree [create|remove|status]"
      echo ""
      echo "Manage git worktree for the active task."
      echo ""
      echo "Subcommands:"
      echo "  create    Create a worktree for the active task"
      echo "  remove    Remove the worktree (after delivery)"
      echo "  status    Show worktree info"
      return 0
      ;;
    create)
      shift
      _oh_worktree_create "$@"
      ;;
    remove)
      shift
      _oh_worktree_remove "$@"
      ;;
    status)
      shift
      _oh_worktree_status "$@"
      ;;
    "")
      # Default: create if no worktree, status if exists
      _oh_worktree_create "$@"
      ;;
    *)
      echo "openharness worktree: unknown subcommand '$1'" >&2
      echo "Run 'openharness worktree --help' for usage." >&2
      exit 1
      ;;
  esac
}

_oh_worktree_create() {
  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness worktree: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local id
  id="$(_oh_read_field "$task_dir" "id")"
  local status
  status="$(_oh_read_field "$task_dir" "status")"

  # Only allow worktree creation in early states
  case "$status" in
    intake|planning|implementing) ;;
    *)
      echo "openharness worktree: cannot create worktree in '$status' state" >&2
      exit 1
      ;;
  esac

  local branch
  branch="$(_oh_branch_name "$id")"
  local wt_path
  wt_path="$(_oh_worktree_path "$root" "$id")"

  if [ -d "$wt_path" ]; then
    echo "openharness worktree: worktree already exists at $wt_path" >&2
    exit 1
  fi

  # Check if branch already exists
  if git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "openharness worktree: branch '$branch' already exists" >&2
    exit 1
  fi

  # Create worktree directory parent
  mkdir -p "$(dirname "$wt_path")"

  # Create worktree with new branch from HEAD
  git worktree add -b "$branch" "$wt_path" HEAD 2>&1

  # Update status.json with worktree info
  local attempt vp lfc hs created_at
  attempt="$(_oh_read_num_field "$task_dir" "attempt")"
  vp="$(_oh_read_field "$task_dir" "verification_passed")"
  vp="${vp:-false}"
  lfc="$(_oh_read_field "$task_dir" "last_failed_command")"
  hs="$(_oh_read_field "$task_dir" "handoff_state")"
  hs="${hs:-null}"
  created_at="$(sed -n 's/.*"created_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"

  # Write status with worktree fields using the atomic writer
  _oh_write_status "$task_dir" "$id" "$status" "$attempt" "$vp" "$lfc" "$hs" "$created_at"

  # Append worktree fields to status.json (before closing brace)
  local tmp_file="$task_dir/status.json.tmp"
  sed '$ d' "$task_dir/status.json" > "$tmp_file"
  printf '  "branch": "%s",\n  "worktree_path": "%s"\n}\n' "$branch" "$wt_path" >> "$tmp_file"
  mv "$tmp_file" "$task_dir/status.json"

  echo "Worktree created:"
  echo "  Branch:   $branch"
  echo "  Path:     $wt_path"
  echo ""
  echo "To work in the worktree: cd $wt_path"
}

_oh_worktree_remove() {
  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness worktree: no active task" >&2
    exit 1
  fi

  local root
  root="$(_oh_repo_root)"
  local id
  id="$(_oh_read_field "$task_dir" "id")"

  local branch
  branch="$(_oh_branch_name "$id")"
  local wt_path
  wt_path="$(_oh_worktree_path "$root" "$id")"

  if [ ! -d "$wt_path" ]; then
    echo "openharness worktree: no worktree found for task '$id'" >&2
    exit 1
  fi

  # Remove worktree
  git worktree remove "$wt_path" --force 2>&1

  # Delete the branch if it exists and is not current
  local current_branch
  current_branch="$(git branch --show-current 2>/dev/null || true)"
  if [ "$current_branch" != "$branch" ] && git rev-parse --verify "$branch" >/dev/null 2>&1; then
    git branch -D "$branch" 2>&1
  fi

  echo "Worktree removed: $wt_path"
  echo "Branch deleted: $branch"
}

_oh_worktree_status() {
  _oh_require_init

  local task_dir
  if ! task_dir="$(_oh_active_task_dir)"; then
    echo "openharness worktree: no active task" >&2
    exit 1
  fi

  local id
  id="$(_oh_read_field "$task_dir" "id")"
  local branch
  branch="$(sed -n 's/.*"branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"
  local wt_path
  wt_path="$(sed -n 's/.*"worktree_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$task_dir/status.json" | head -1)"

  if [ -z "$branch" ]; then
    echo "No worktree configured for task '$id'"
    return 0
  fi

  echo "Task:       $id"
  echo "Branch:     $branch"
  echo "Worktree:   $wt_path"
  if [ -d "$wt_path" ]; then
    echo "Exists:     yes"
  else
    echo "Exists:     no (removed)"
  fi
}
